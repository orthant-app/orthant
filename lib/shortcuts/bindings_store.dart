import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'bindings.dart';
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
  /// v1 was a bare JSON list of bindings. v2 is an object that also carries the
  /// user's custom regions.
  ///
  /// v1 is still read when v2 is absent, so upgrading keeps every rebind.
  ///
  /// **Downgrading does not work, and an earlier version of this comment
  /// claimed it did.** `CommandRef.tryParse` returning null for an unknown
  /// `custom:` name is real, but irrelevant here: an older build never reads
  /// the v2 key at all. It reads whatever v1 held when it last ran, so every
  /// change made since — custom rows *and* rebinds of the built-ins — is
  /// invisible to it.
  ///
  /// Deliberately not fixed by dual-writing v1. That would leave a second file
  /// that is silently a subset of the truth, and downgrade is not a path this
  /// app supports: it has never been released.
  static const _v1Key = 'orthant.bindings.v1';
  static const _v2Key = 'orthant.bindings.v2';

  Future<StoredBindings> load() async {
    final prefs = await SharedPreferences.getInstance();

    final v2 = prefs.getString(_v2Key);
    if (v2 != null) {
      final parsed = _tryDecode(v2);
      final map = parsed is Map ? parsed : const {};
      final regions = _regionsFrom(map['regions']);
      return StoredBindings(
        _completed(_bindingsFrom(map['bindings']), regions),
        regions,
      );
    }

    final v1 = prefs.getString(_v1Key);
    if (v1 == null) return const StoredBindings(kDefaultBindings, []);
    return StoredBindings(
      _completed(_bindingsFrom(_tryDecode(v1)), const []),
      const [],
    );
  }

  Future<void> save(List<Binding> bindings, List<CustomRegion> regions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _v2Key,
      jsonEncode({
        'bindings': [for (final b in bindings) b.toJson()],
        'regions': [for (final r in regions) r.toJson()],
      }),
    );
  }
}

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

/// The bindings we could make sense of. A truncated file, a list of something
/// other than objects, an entry naming a command this build doesn't have — all
/// skipped rather than thrown. [BindingsStore.load] runs before any shortcut is
/// registered, so an exception here would leave the app with no shortcuts at
/// all and no way for the user to recover short of deleting the preferences by
/// hand.
List<Binding> _bindingsFrom(Object? parsed) {
  if (parsed is! List) return const [];
  final out = <Binding>[];
  for (final entry in parsed) {
    final binding = Binding.tryFromJson(entry);
    if (binding != null) out.add(binding);
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
    for (final b in kDefaultBindings) b.command: b
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
