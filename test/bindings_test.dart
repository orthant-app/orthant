import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

void main() {
  test('a rebind for a command absent from the list is added, not dropped', () {
    // The list is rendered from the commands that exist, not from whatever
    // preferences hold, so a row can be on screen with no entry behind it.
    // Rebuilding the list from its existing entries silently dropped such an
    // update: the row went on showing "Not set" and pressing a combo appeared
    // to do nothing at all, forever.
    final without = kDefaultBindings
        .where((b) => b.command != const BuiltIn(ShortcutCommand.leftHalf))
        .toList();
    const wanted =
        Binding(BuiltIn(ShortcutCommand.leftHalf), 123, kControlOption);

    final result = withRebind(without, wanted);

    expect(result.where((b) => b.command == wanted.command), hasLength(1));
    expect(result.firstWhere((b) => b.command == wanted.command), wanted);
    expect(result, hasLength(without.length + 1));
  });

  test('defaults cover every command on ⌃⌥', () {
    expect(kDefaultBindings.map((b) => b.command).toSet(),
        {for (final c in ShortcutCommand.values) BuiltIn(c)});
    expect(kDefaultBindings.every((b) => b.modifiers == kControlOption), isTrue);
  });

  test('json round-trips', () {
    const b = Binding(BuiltIn(ShortcutCommand.topRight), 34, kControlOption);
    expect(Binding.tryFromJson(b.toJson()), b);
  });

  test('conflictFor finds a different command already using the combo', () {
    // ⌃⌥→ is rightHalf by default; binding it to leftHalf collides.
    expect(
      conflictFor(kDefaultBindings,
          const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption)),
      const BuiltIn(ShortcutCommand.rightHalf),
    );
  });

  test('conflictFor ignores the command being rebound and free combos', () {
    // Rebinding a command to the combo it already has is not a conflict.
    expect(
      conflictFor(kDefaultBindings,
          const Binding(BuiltIn(ShortcutCommand.leftHalf), 123, kControlOption)),
      isNull,
    );
    // An unused combo (⌃⌥⇧←) is free.
    expect(
      conflictFor(kDefaultBindings,
          const Binding(BuiltIn(ShortcutCommand.leftHalf), 123, kControlOption | kShiftKey)),
      isNull,
    );
  });

  test('a binding can be unbound, and defaults are all bound', () {
    const b = Binding(BuiltIn(ShortcutCommand.center), kUnboundKey, 0);
    expect(b.isBound, isFalse);
    expect(kDefaultBindings.every((b) => b.isBound), isTrue);
  });

  test('rebinding steals the combo and unbinds the previous owner', () {
    // Give leftHalf the combo rightHalf currently owns (⌃⌥→).
    final next = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption));

    Binding of(ShortcutCommand c) =>
        next.firstWhere((b) => b.command == BuiltIn(c));
    expect(of(ShortcutCommand.leftHalf).keyCode, 124);
    expect(of(ShortcutCommand.rightHalf).isBound, isFalse,
        reason: 'the displaced command must become unset, not silently shadowed');
    // Every command still present, order preserved.
    expect(next.map((b) => b.command), kDefaultBindings.map((b) => b.command));
  });

  test('withRebind leaves other bindings untouched when there is no clash', () {
    final next = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 123, kControlOption | kShiftKey));
    expect(next.where((b) => !b.isBound), isEmpty);
    expect(next.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.leftHalf)).modifiers,
        kControlOption | kShiftKey);
  });

  test('comboSymbols splits a combo into individual keycaps', () {
    expect(comboSymbols(123, kControlOption), ['⌃', '⌥', '←']);
    expect(comboSymbols(36, kControlOption | kShiftKey), ['⌃', '⌥', '⇧', '↩']);
    expect(comboSymbols(kUnboundKey, 0), isEmpty);
  });

  test('modifierSymbols says what is held before a key completes the combo',
      () {
    // Split out of comboSymbols precisely because that one answers with
    // *nothing at all* while no key has landed — which is the whole window the
    // recorder needs to draw in.
    expect(comboSymbols(kUnboundKey, kControlOption), isEmpty);
    expect(modifierSymbols(kControlOption), ['⌃', '⌥']);

    expect(modifierSymbols(0), isEmpty);
    expect(modifierSymbols(kControlKey | kOptionKey | kShiftKey | kCmdKey),
        ['⌃', '⌥', '⇧', '⌘']);
    // macOS's canonical order, which is not the order the bits arrive in.
    expect(modifierSymbols(kCmdKey | kControlKey), ['⌃', '⌘']);
  });

  test('every bindable key has a display symbol — no raw key:<code> leaks', () {
    // The capture map (settings/key_capture.dart) accepts A–Z, 0–9, arrows,
    // Return and Space, so all of them must render as something readable.
    const bindableCarbonCodes = <int>[
      0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, // A..M
      45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6, // N..Z
      18, 19, 20, 21, 23, 22, 26, 28, 25, 29, // 1..9,0
      123, 124, 125, 126, 36, 49, // arrows, return, space
    ];
    for (final code in bindableCarbonCodes) {
      expect(formatCombo(code, kControlOption), isNot(contains('key:')),
          reason: 'Carbon key code $code renders as a raw code');
    }
  });

  test('letters render uppercase, as macOS renders shortcuts', () {
    expect(formatCombo(12, kControlOption), '⌃⌥Q');
    expect(formatCombo(0, kControlOption), '⌃⌥A');
    expect(formatCombo(29, kControlOption), '⌃⌥0');
    expect(formatCombo(49, kControlOption), '⌃⌥␣');
  });

  test('formatCombo renders modifier symbols + key', () {
    expect(formatCombo(123, kControlOption), '⌃⌥←');
    expect(formatCombo(32, kControlOption), '⌃⌥U');
    expect(formatCombo(36, kControlOption), '⌃⌥↩');
  });
}
