import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show PhysicalKeyboardKey;

import 'command_ref.dart';
import '../core/key_chord.dart';
import 'shortcut_command.dart';

/// A command and the chord that fires it.
/// A command may also be *unbound* (no [chord]); it then has no shortcut and
/// is skipped when registering hotkeys.
class Binding {
  final CommandRef command;

  /// Null when the command has no shortcut.
  final KeyChord? chord;

  const Binding(this.command, this.chord);

  /// An entry with no shortcut assigned.
  const Binding.unbound(this.command) : chord = null;

  bool get isBound => chord != null;

  @override
  bool operator ==(Object other) =>
      other is Binding && other.command == command && other.chord == chord;
  @override
  int get hashCode => Object.hash(command, chord);
}

/// The default shortcuts for [platform].
///
/// The summon leads, because it is the one that opens the grid rather than
/// placing a window, and because it is the first row of the Shortcuts pane.
///
/// `O` for **Open grid**, which is what the row and the menu item both say:
/// macOS convention leans on the verb (`⌘O` is Open), so the letter matches the
/// words on screen rather than the object. It sits beside the `U`/`I`/`J`/`K`
/// quarters cluster too, keeping every letter shortcut in one hand and region.
/// That it is also Orthant's initial is a free bonus, not the reason.
///
/// **Windows' set is provisional, and its milestone owns it.** On a layout
/// with AltGr, right Alt is Ctrl+Alt, so a Ctrl+Alt letter chord swallows a
/// character the user meant to type; Shift does not escape it, so the six
/// letter chords move to Win+Shift there ([altGr]), and the arrows and Enter,
/// which AltGr never combines with, stay. Every Windows chord here still holds
/// Alt, and a registered hotkey holding Alt has been measured leaving a WinUI
/// app (Notepad) typing nothing afterwards, so this table is expected to
/// change before Windows registers anything. macOS ignores [altGr].
///
/// Every platform but Windows gets the macOS set, which includes the test host
/// (Flutter reports Android there).
List<Binding> defaultBindings({
  required TargetPlatform platform,
  required bool altGr,
}) {
  final ctrlAlt = Modifiers.ctrl | Modifiers.alt;
  final letters = platform == TargetPlatform.windows && altGr
      ? Modifiers.meta | Modifiers.shift
      : ctrlAlt;
  Binding bind(ShortcutCommand command, PhysicalKeyboardKey key, Modifiers m) =>
      Binding(BuiltIn(command), KeyChord.us(key.usbHidUsage, m));
  return [
    bind(ShortcutCommand.showGrid, PhysicalKeyboardKey.keyO, letters),
    bind(ShortcutCommand.leftHalf, PhysicalKeyboardKey.arrowLeft, ctrlAlt),
    bind(ShortcutCommand.rightHalf, PhysicalKeyboardKey.arrowRight, ctrlAlt),
    bind(ShortcutCommand.topHalf, PhysicalKeyboardKey.arrowUp, ctrlAlt),
    bind(ShortcutCommand.bottomHalf, PhysicalKeyboardKey.arrowDown, ctrlAlt),
    bind(ShortcutCommand.topLeft, PhysicalKeyboardKey.keyU, letters),
    bind(ShortcutCommand.topRight, PhysicalKeyboardKey.keyI, letters),
    bind(ShortcutCommand.bottomLeft, PhysicalKeyboardKey.keyJ, letters),
    bind(ShortcutCommand.bottomRight, PhysicalKeyboardKey.keyK, letters),
    bind(ShortcutCommand.maximize, PhysicalKeyboardKey.enter, ctrlAlt),
    bind(ShortcutCommand.center, PhysicalKeyboardKey.keyC, letters),
  ];
}

/// [defaultBindings] for the platform this build runs on: what a first launch
/// starts from and what *Reset Shortcuts* returns to.
///
/// Whether a Windows layout has AltGr is not detected yet, so it is answered
/// as "no" until the Windows hotkey work asks the system.
List<Binding> runningDefaults() =>
    defaultBindings(platform: defaultTargetPlatform, altGr: false);

/// What [ref] is bound to once *Reset Shortcuts* has run.
///
/// A region is not among the defaults and so comes back unbound: regions
/// survive a reset, their combos do not. Stated once because two places need
/// it: `OrthantCoordinator.resetBindings`, which performs the reset, and the
/// pane's Undo, which has to know **which rows a reset actually changed** so it
/// can leave every other row alone. A coordinator test asserts the two agree.
Binding defaultBindingFor(CommandRef ref) => runningDefaults().firstWhere(
      (b) => b.command == ref,
      orElse: () => Binding.unbound(ref),
    );

/// Whether [a] and [b] are the same shortcut on the platform running now:
/// both unbound, or bound to chords that are one hotkey there
/// ([KeyChord.sameChordAs]).
///
/// Not `==`, which also compares the logical key and so tells apart two
/// recordings of one macOS hotkey made under different layouts. Ask this
/// wherever the question is "would pressing it do the same thing".
bool sameShortcut(Binding a, Binding b) {
  final x = a.chord;
  final y = b.chord;
  return x == null ? y == null : y != null && x.sameChordAs(y);
}

/// The command already using [candidate]'s combo, or null if it is free.
/// The command being rebound is ignored (keeping its own combo isn't a clash).
///
/// "The same combo" is the platform's own question ([KeyChord.sameChordAs]):
/// the same key position on macOS, whatever each chord's layout typed there.
CommandRef? conflictFor(List<Binding> bindings, Binding candidate) {
  final wanted = candidate.chord;
  if (wanted == null) return null;
  for (final b in bindings) {
    if (b.command == candidate.command) continue;
    final held = b.chord;
    if (held != null && held.sameChordAs(wanted)) return b.command;
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

/// A key's USB HID usage → how macOS displays that key in a shortcut.
///
/// Must cover every key `isBindableKey` accepts, or a rebound key shows up as
/// a raw `key:0x…`. Letters are uppercase because that is how macOS renders
/// shortcuts (⌘C, not ⌘c). Tab and Escape are labelled though neither can be
/// bound.
const Map<int, String> _keySymbols = {
  // Letters, in alphabetical order.
  0x00070004: 'A', 0x00070005: 'B', 0x00070006: 'C', 0x00070007: 'D',
  0x00070008: 'E', 0x00070009: 'F', 0x0007000A: 'G', 0x0007000B: 'H',
  0x0007000C: 'I', 0x0007000D: 'J', 0x0007000E: 'K', 0x0007000F: 'L',
  0x00070010: 'M', 0x00070011: 'N', 0x00070012: 'O', 0x00070013: 'P',
  0x00070014: 'Q', 0x00070015: 'R', 0x00070016: 'S', 0x00070017: 'T',
  0x00070018: 'U', 0x00070019: 'V', 0x0007001A: 'W', 0x0007001B: 'X',
  0x0007001C: 'Y', 0x0007001D: 'Z',
  // Digits 1…9, 0.
  0x0007001E: '1', 0x0007001F: '2', 0x00070020: '3', 0x00070021: '4',
  0x00070022: '5', 0x00070023: '6', 0x00070024: '7', 0x00070025: '8',
  0x00070026: '9', 0x00070027: '0',
  // Editing / navigation.
  0x00070050: '←', 0x0007004F: '→', 0x00070051: '↓', 0x00070052: '↑',
  0x00070028: '↩', 0x0007002C: '␣', 0x0007002B: '⇥', 0x0007002A: '⌫',
  0x00070029: '⎋', 0x0007004A: '↖', 0x0007004D: '↘', 0x0007004B: '⇞',
  0x0007004E: '⇟', 0x0007004C: '⌦',
  // ANSI fallbacks; the live input source supplies printable labels on macOS.
  0x0007002D: '-', 0x0007002E: '=', 0x0007002F: '[', 0x00070030: ']',
  0x00070031: '\\', 0x00070033: ';', 0x00070034: "'", 0x00070035: '`',
  0x00070036: ',', 0x00070037: '.', 0x00070038: '/', 0x00070064: '§',
  0x00070089: '¥', 0x00070087: '_',
  0x0007003A: 'F1', 0x0007003B: 'F2', 0x0007003C: 'F3', 0x0007003D: 'F4',
  0x0007003E: 'F5', 0x0007003F: 'F6', 0x00070040: 'F7', 0x00070041: 'F8',
  0x00070042: 'F9', 0x00070043: 'F10', 0x00070044: 'F11', 0x00070045: 'F12',
  0x00070068: 'F13', 0x00070069: 'F14', 0x0007006A: 'F15', 0x0007006B: 'F16',
  0x0007006C: 'F17', 0x0007006D: 'F18', 0x0007006E: 'F19', 0x0007006F: 'F20',
  0x00070053: '⌧', 0x00070058: '⌤', 0x00070054: 'Num /', 0x00070055: 'Num *',
  0x00070056: 'Num -', 0x00070057: 'Num +', 0x00070067: 'Num =',
  0x00070063: 'Num .', 0x00070085: 'Num ,',
  0x00070062: 'Num 0', 0x00070059: 'Num 1', 0x0007005A: 'Num 2',
  0x0007005B: 'Num 3', 0x0007005C: 'Num 4', 0x0007005D: 'Num 5',
  0x0007005E: 'Num 6', 0x0007005F: 'Num 7', 0x00070060: 'Num 8',
  0x00070061: 'Num 9',
};

/// The combo as individual symbols, in macOS order (⌃⌥⇧⌘ then the key), for
/// rendering one keycap per element. Empty when unbound.
///
/// [keyLabels] is the keyboard layout's own labels, keyed by USB HID usage
/// (`WindowController.keyboardLabels`); a key it does not name falls back to
/// the US glyph.
List<String> comboSymbols(KeyChord? chord, {
  Map<int, String> keyLabels = const {},
}) {
  if (chord == null) return const [];
  return [
    ...modifierSymbols(chord.modifiers),
    keyLabels[chord.physical] ??
        _keySymbols[chord.physical] ??
        'key:0x${chord.physical.toRadixString(16)}',
  ];
}

/// The modifier glyphs held, in macOS's canonical order.
///
/// Split out of [comboSymbols], which answers with **nothing at all** for an
/// unbound command, precisely the moment the recorder needs to draw: while
/// modifiers are down and no key has completed the combination yet. A field
/// that shows the same "Press keys…" whether or not ⌃⌥ is held reads as one
/// that is not listening.
List<String> modifierSymbols(Modifiers modifiers) => [
  if (modifiers.has(Modifiers.ctrl)) '⌃',
  if (modifiers.has(Modifiers.alt)) '⌥',
  if (modifiers.has(Modifiers.shift)) '⇧',
  if (modifiers.has(Modifiers.meta)) '⌘',
];

/// Human-readable combo, e.g. `⌃⌥←`.
String formatCombo(KeyChord chord, {
  Map<int, String> keyLabels = const {},
}) =>
    comboSymbols(chord, keyLabels: keyLabels).join();

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
  Map<int, String> keyLabels = const {},
}) {
  if (unavailable.contains(command)) return null;
  for (final b in bindings) {
    if (b.command != command) continue;
    final chord = b.chord;
    return chord == null ? null : formatCombo(chord, keyLabels: keyLabels);
  }
  return null;
}
