import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'bindings.dart';
import '../core/carbon_keys.dart';
import 'command_ref.dart';
import 'custom_region.dart';
import 'shortcut_command.dart';

/// Everything the shortcuts feature persists, loaded together.
///
/// **One stored value, not two keys.** Split apart, a partial write leaves a
/// binding pointing at a region that does not exist — and the settings list
/// looks a row's binding up with `firstWhere`, so that state does not render as
/// a missing row, it renders as a crash.
class StoredBindings {
  final List<Binding> bindings;
  final List<CustomRegion> regions;
  const StoredBindings(this.bindings, this.regions);
}

class BindingsStore {
  /// v1 was a bare JSON list of bindings, each a Carbon key code and mask. v2
  /// is an object that also carries the user's custom regions, with v1's
  /// bindings inside it. v3 is v2's object with each combo held as a chord,
  /// which names its key both ways a platform can register one.
  ///
  /// **The newest key present is the only one read.** When it is v1 or v2,
  /// it is migrated: converted, written as v3, and from then on never read
  /// again.
  ///
  /// The older key is left in place, not deleted, so a downgrade reads what it
  /// always did. What it reads is the shortcuts as they were at the migration:
  /// nothing writes v2 any more, so a change made since is invisible to the
  /// older build, and a change the older build makes is invisible to this one,
  /// which reads v3 alone. Writing both was rejected for the reason v1 was
  /// never dual-written: a second copy that is silently a subset of the truth.
  static const _v1Key = 'orthant.bindings.v1';
  static const _v2Key = 'orthant.bindings.v2';
  static const _v3Key = 'orthant.bindings.v3';

  Future<StoredBindings> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Chosen by presence, then read: a key that is present but unreadable is
    // still the newest, and means the defaults, never an older key.
    if (prefs.containsKey(_v3Key)) {
      return _documentFrom(_decoded(prefs, _v3Key), Binding.tryFromJson);
    }

    // Before any shortcut registers, on every platform: a file this old was
    // written on macOS, but nothing about reading it needs to know that.
    final StoredBindings migrated;
    if (prefs.containsKey(_v2Key)) {
      migrated = _documentFrom(_decoded(prefs, _v2Key), _bindingFromCarbon);
    } else if (prefs.containsKey(_v1Key)) {
      migrated = StoredBindings(
        _completed(
            _bindingsFrom(_decoded(prefs, _v1Key), _bindingFromCarbon), const []),
        const [],
      );
    } else {
      return StoredBindings(runningDefaults(), const []);
    }
    try {
      await save(migrated.bindings, migrated.regions);
    } catch (_) {
      // Deliberately swallowed. A write that fails costs a repeat, not the
      // shortcuts: v3 stays absent, so the next launch migrates the same file
      // the same way. Thrown from here it would cost every shortcut instead.
    }
    return migrated;
  }

  Future<void> save(List<Binding> bindings, List<CustomRegion> regions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _v3Key,
      jsonEncode({
        'bindings': [for (final b in bindings) b.toJson()],
        'regions': [for (final r in regions) r.toJson()],
      }),
    );
  }
}

/// The JSON stored under [key], or null when it is not text holding JSON.
///
/// Not `getString`, which casts and so throws on a value of any other type: a
/// hand-written preference would then stop the launch, before any shortcut
/// registers, which is what every tolerance in this file exists to prevent.
Object? _decoded(SharedPreferences prefs, String key) {
  final raw = prefs.get(key);
  return raw is String ? _tryDecode(raw) : null;
}

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

/// A v2 or v3 document: an object holding bindings and regions.
StoredBindings _documentFrom(
  Object? parsed,
  Binding? Function(Object? entry) binding,
) {
  final map = parsed is Map ? parsed : const {};
  final regions = _regionsFrom(map['regions']);
  return StoredBindings(
    _completed(_bindingsFrom(map['bindings'], binding), regions),
    regions,
  );
}

/// One v1 or v2 entry: a command, and a Carbon key code and mask.
///
/// The validation those versions applied, with one narrowing: the key code
/// must be one the recorder can produce, and the mask may hold only the four
/// modifiers. Every file Orthant wrote passes both, so the narrowing reaches
/// only a hand-edited one, where a stray value used to go straight to
/// `RegisterEventHotKey` and would now leave that command at its default.
Binding? _bindingFromCarbon(Object? entry) {
  if (entry is! Map) return null;
  final name = entry['command'];
  final keyCode = entry['keyCode'];
  final modifiers = entry['modifiers'];
  if (name is! String || keyCode is! int || modifiers is! int) return null;
  final command = CommandRef.tryParse(name);
  if (command == null) return null;
  if (keyCode == kUnboundKey) {
    return modifiers == 0 ? Binding.unbound(command) : null;
  }
  final chord = chordFromCarbon(keyCode, modifiers);
  return chord == null ? null : Binding(command, chord);
}

/// The bindings we could make sense of. A truncated file, a list of something
/// other than objects, an entry naming a command this build doesn't have — all
/// skipped rather than thrown. [BindingsStore.load] runs before any shortcut is
/// registered, so an exception here would leave the app with no shortcuts at
/// all and no way for the user to recover short of deleting the preferences by
/// hand.
List<Binding> _bindingsFrom(
  Object? parsed,
  Binding? Function(Object? entry) binding,
) {
  if (parsed is! List) return const [];
  final out = <Binding>[];
  for (final entry in parsed) {
    final b = binding(entry);
    if (b != null) out.add(b);
  }
  return out;
}

/// Regions that validated, with duplicate ids dropped. Same tolerance, same
/// reason — and duplicates matter beyond tidiness, because two rows sharing an
/// id would both resolve to the first one's shape.
List<CustomRegion> _regionsFrom(Object? parsed) {
  if (parsed is! List) return const [];
  final out = <CustomRegion>[];
  final seen = <String>{};
  for (final entry in parsed) {
    final region = CustomRegion.tryFromJson(entry);
    if (region == null) continue;
    if (!seen.add(region.id)) continue;
    out.add(region);
  }
  return out;
}

/// Exactly one binding per row this build will show: the eleven built-ins in
/// enum order, then one per surviving region in list order.
///
/// Completeness is not cosmetic. The settings list looks a row's binding up
/// with `firstWhere`, so a command absent from the file — one added since that
/// file was written — would throw while building the UI rather than simply
/// showing an unset row.
///
/// Two rules for the custom half. A region with no stored combo still gets a
/// row, unbound: it exists, so it must be visible and rebindable. And a binding
/// whose region did **not** survive validation is dropped rather than kept —
/// it would be a row with no shape to place and no name to show.
List<Binding> _completed(List<Binding> stored, List<CustomRegion> regions) {
  final byCommand = <CommandRef, Binding>{for (final b in stored) b.command: b};
  final defaults = <CommandRef, Binding>{
    for (final b in runningDefaults()) b.command: b
  };
  return [
    for (final command in ShortcutCommand.values)
      byCommand[BuiltIn(command)] ??
          defaults[BuiltIn(command)] ??
          Binding.unbound(BuiltIn(command)),
    for (final region in regions)
      byCommand[Custom(region.id)] ?? Binding.unbound(Custom(region.id)),
  ];
}
