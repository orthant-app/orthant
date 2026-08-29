import 'command_ref.dart';
import 'shortcut_command.dart';

/// Carbon modifier masks.
const int kControlKey = 4096;
const int kOptionKey = 2048;
const int kCmdKey = 256;
const int kShiftKey = 512;
const int kControlOption = kControlKey | kOptionKey; // 6144

/// Sentinel [Binding.keyCode] meaning "no shortcut assigned".
const int kUnboundKey = -1;

/// A command bound to a Carbon virtual key code + Carbon modifier mask.
/// A command may also be *unbound* ([kUnboundKey]) — it then has no shortcut
/// and is skipped when registering hotkeys.
class Binding {
  final CommandRef command;
  final int keyCode;
  final int modifiers;
  const Binding(this.command, this.keyCode, this.modifiers);

  /// An entry with no shortcut assigned.
  const Binding.unbound(this.command) : keyCode = kUnboundKey, modifiers = 0;

  bool get isBound => keyCode != kUnboundKey;

  Map<String, dynamic> toJson() =>
      {'command': command.jsonName, 'keyCode': keyCode, 'modifiers': modifiers};

  /// One persisted entry, or null if it isn't one we can trust.
  ///
  /// Tolerant by design. This reads a file we did not necessarily write — an
  /// older release's, a newer one's, or a corrupt one — and it is read before
  /// any shortcut is registered, so anything thrown here takes the entire
  /// feature down at launch with no user-visible way back. A rejected entry
  /// costs that one command its saved combo; a thrown one costs all eleven.
  static Binding? tryFromJson(Object? entry) {
    if (entry is! Map) return null;
    final name = entry['command'];
    final keyCode = entry['keyCode'];
    final modifiers = entry['modifiers'];
    if (name is! String || keyCode is! int || modifiers is! int) return null;
    if (!_isRegistrable(keyCode, modifiers)) return null;
    final command = CommandRef.tryParse(name);
    return command == null ? null : Binding(command, keyCode, modifiers);
  }

  /// Whether this pair is something the native side can actually be handed.
  ///
  /// Being an `int` is not enough. Both cross to Swift as `UInt32`, whose
  /// initialiser **traps** on a negative value — so a stored `keyCode: -2` is
  /// not a bad shortcut, it is a hard crash on the launch path that reads the
  /// preferences, every launch, with no way out but deleting them by hand.
  ///
  /// A bound combo must also carry a modifier. The recorder enforces that
  /// ("Combinations need ⌃, ⌥, ⇧ or ⌘"), but a hand-edited file need not, and
  /// registering a bare key would take that key away from *every* app on the
  /// system for as long as Orthant runs.
  static bool _isRegistrable(int keyCode, int modifiers) {
    if (keyCode == kUnboundKey) return modifiers == 0;
    if (keyCode < 0 || keyCode > 0x7F) return false; // Carbon virtual key codes
    if (modifiers < 0 || modifiers > 0xFFFF) return false;
    return modifiers & (kControlKey | kOptionKey | kShiftKey | kCmdKey) != 0;
  }

  Binding copyWith({int? keyCode, int? modifiers}) =>
      Binding(command, keyCode ?? this.keyCode, modifiers ?? this.modifiers);

  @override
  bool operator ==(Object other) =>
      other is Binding &&
      other.command == command &&
      other.keyCode == keyCode &&
      other.modifiers == modifiers;
  @override
  int get hashCode => Object.hash(command, keyCode, modifiers);
}

/// Collision-safe ⌃⌥ defaults.
///
/// The summon leads, because it is the one that opens the grid rather than
/// placing a window — and because it is the first row of the Shortcuts pane.
///
/// `O` for **Open grid**, which is what the row and the menu item both say —
/// macOS convention leans on the verb (`⌘O` is Open), so the letter matches the
/// words on screen rather than the object. It sits beside the `U`/`I`/`J`/`K`
/// quarters cluster too, keeping every letter shortcut in one hand and region.
/// That it is also Orthant's initial is a free bonus, not the reason.
const List<Binding> kDefaultBindings = [
  Binding(BuiltIn(ShortcutCommand.showGrid), 31, kControlOption),    // ⌃⌥O
  Binding(BuiltIn(ShortcutCommand.leftHalf), 123, kControlOption),   // ⌃⌥←
  Binding(BuiltIn(ShortcutCommand.rightHalf), 124, kControlOption),  // ⌃⌥→
  Binding(BuiltIn(ShortcutCommand.topHalf), 126, kControlOption),    // ⌃⌥↑
  Binding(BuiltIn(ShortcutCommand.bottomHalf), 125, kControlOption), // ⌃⌥↓
  Binding(BuiltIn(ShortcutCommand.topLeft), 32, kControlOption),     // ⌃⌥U
  Binding(BuiltIn(ShortcutCommand.topRight), 34, kControlOption),    // ⌃⌥I
  Binding(BuiltIn(ShortcutCommand.bottomLeft), 38, kControlOption),  // ⌃⌥J
  Binding(BuiltIn(ShortcutCommand.bottomRight), 40, kControlOption), // ⌃⌥K
  Binding(BuiltIn(ShortcutCommand.maximize), 36, kControlOption),    // ⌃⌥↩
  Binding(BuiltIn(ShortcutCommand.center), 8, kControlOption),       // ⌃⌥C
];

/// What [ref] is bound to once *Reset Shortcuts* has run.
///
/// A region is not in [kDefaultBindings] and so comes back unbound — regions
/// survive a reset, their combos do not. Stated once because two places need
/// it: `OrthantCoordinator.resetBindings`, which performs the reset, and the
/// pane's Undo, which has to know **which rows a reset actually changed** so it
/// can leave every other row alone. A coordinator test asserts the two agree.
Binding defaultBindingFor(CommandRef ref) => kDefaultBindings.firstWhere(
      (b) => b.command == ref,
      orElse: () => Binding.unbound(ref),
    );

/// The command already using [candidate]'s combo, or null if it is free.
/// The command being rebound is ignored (keeping its own combo isn't a clash).
CommandRef? conflictFor(List<Binding> bindings, Binding candidate) {
  for (final b in bindings) {
    if (b.command == candidate.command) continue;
    if (!b.isBound) continue;
    if (b.keyCode == candidate.keyCode && b.modifiers == candidate.modifiers) {
      return b.command;
    }
  }
  return null;
}

/// [bindings] with [updated] applied.
///
/// If another command already owned that combo it is *unbound* rather than left
/// as a duplicate — two Carbon registrations of one chord shadow each other
/// unpredictably, so a duplicate is not an option this can take.
///
/// **The UI reaches this branch deliberately, and reports it.** It briefly did
/// not: both entry points checked [conflictFor] first and *refused*, on the
/// argument that a change should not silently undo a setting made earlier. The
/// silence was the real problem, not the displacement — refusing turned out to
/// be a six-interaction dead end. Both now ask first, name the owner, and offer
/// the way back (`ShortcutsScreen._notifyDisplaced`, `onRestoreBindings`).
///
/// The rule this enforces — never two commands on one chord — must hold for any
/// caller regardless, including a hand-edited preferences file arriving through
/// a path that never saw the UI.
List<Binding> withRebind(List<Binding> bindings, Binding updated) {
  final displaced = conflictFor(bindings, updated);
  final known = bindings.any((b) => b.command == updated.command);
  return [
    for (final b in bindings)
      if (b.command == updated.command)
        updated
      else if (b.command == displaced)
        Binding.unbound(b.command)
      else
        b,
    // Appended when the list has no entry for this command yet. Rebuilding the
    // list from its existing entries **silently dropped** such an update: the
    // rebind returned a list that did not contain it, so the row went on
    // showing "Not set" and pressing a combo appeared to do nothing at all,
    // forever. The rows are built from the commands that exist rather than from
    // whatever preferences happen to hold — see `_bindingFor`'s `orElse` — so a
    // row can legitimately be on screen with no entry behind it.
    if (!known) updated,
  ];
}

/// Carbon virtual key code → how macOS displays that key in a shortcut.
///
/// Must cover everything `carbonFromKeyEvent` (settings/key_capture.dart) can
/// produce, or a rebound key shows up as a raw `key:<code>`. Letters are
/// uppercase because that is how macOS renders shortcuts (⌘C, not ⌘c).
const Map<int, String> _keySymbols = {
  // Letters (kVK_ANSI_A …), in alphabetical order of the letter.
  0: 'A', 11: 'B', 8: 'C', 2: 'D', 14: 'E', 3: 'F', 5: 'G', 4: 'H',
  34: 'I', 38: 'J', 40: 'K', 37: 'L', 46: 'M', 45: 'N', 31: 'O', 35: 'P',
  12: 'Q', 15: 'R', 1: 'S', 17: 'T', 32: 'U', 9: 'V', 13: 'W', 7: 'X',
  16: 'Y', 6: 'Z',
  // Digits 1…9, 0.
  18: '1', 19: '2', 20: '3', 21: '4', 23: '5',
  22: '6', 26: '7', 28: '8', 25: '9', 29: '0',
  // Editing / navigation.
  123: '←', 124: '→', 125: '↓', 126: '↑',
  36: '↩', 49: '␣', 48: '⇥', 51: '⌫', 53: '⎋',
};

/// The combo as individual symbols, in macOS order (⌃⌥⇧⌘ then the key), for
/// rendering one keycap per element. Empty when unbound.
List<String> comboSymbols(int keyCode, int modifiers) {
  if (keyCode == kUnboundKey) return const [];
  return [...modifierSymbols(modifiers), _keySymbols[keyCode] ?? 'key:$keyCode'];
}

/// The modifier glyphs held, in macOS's canonical order.
///
/// Split out of [comboSymbols], which answers with **nothing at all** for an
/// unbound key code — precisely the moment the recorder needs to draw: while
/// modifiers are down and no key has completed the combination yet. A field
/// that shows the same "Press keys…" whether or not ⌃⌥ is held reads as one
/// that is not listening.
List<String> modifierSymbols(int modifiers) => [
  if (modifiers & kControlKey != 0) '⌃',
  if (modifiers & kOptionKey != 0) '⌥',
  if (modifiers & kShiftKey != 0) '⇧',
  if (modifiers & kCmdKey != 0) '⌘',
];

/// Human-readable combo, e.g. `⌃⌥←`. Falls back to `key:<code>` for unmapped keys.
String formatCombo(int keyCode, int modifiers) {
  final b = StringBuffer();
  if (modifiers & kControlKey != 0) b.write('⌃');
  if (modifiers & kOptionKey != 0) b.write('⌥');
  if (modifiers & kShiftKey != 0) b.write('⇧');
  if (modifiers & kCmdKey != 0) b.write('⌘');
  b.write(_keySymbols[keyCode] ?? 'key:$keyCode');
  return b.toString();
}

/// [command]'s combo for display outside the settings list, or null when there
/// is nothing honest to show.
///
/// Null in two cases, and the distinction matters: the command is **unbound**,
/// or the OS **refused** the chord. Both mean pressing it does nothing, so a
/// menu that printed the combo anyway would be advertising a shortcut that
/// cannot fire — the exact silence `unavailable` exists to break.
String? comboLabelFor(
  List<Binding> bindings,
  CommandRef command, {
  Set<CommandRef> unavailable = const {},
}) {
  if (unavailable.contains(command)) return null;
  for (final b in bindings) {
    if (b.command != command) continue;
    return b.isBound ? formatCombo(b.keyCode, b.modifiers) : null;
  }
  return null;
}
