import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

import 'support/carbon_terms.dart';

/// Orthant 1.0.3's glyph table, verbatim, keyed by Carbon code as it was.
/// The labels test below holds today's labels to it.
const Map<int, String> _labels103 = {
  0: 'A', 11: 'B', 8: 'C', 2: 'D', 14: 'E', 3: 'F', 5: 'G', 4: 'H',
  34: 'I', 38: 'J', 40: 'K', 37: 'L', 46: 'M', 45: 'N', 31: 'O', 35: 'P',
  12: 'Q', 15: 'R', 1: 'S', 17: 'T', 32: 'U', 9: 'V', 13: 'W', 7: 'X',
  16: 'Y', 6: 'Z',
  18: '1', 19: '2', 20: '3', 21: '4', 23: '5',
  22: '6', 26: '7', 28: '8', 25: '9', 29: '0',
  123: '←', 124: '→', 125: '↓', 126: '↑',
  36: '↩', 49: '␣', 48: '⇥', 51: '⌫', 53: '⎋',
  115: '↖', 119: '↘', 116: '⇞', 121: '⇟', 117: '⌦',
  27: '-', 24: '=', 33: '[', 30: ']', 42: '\\', 41: ';', 39: "'",
  50: '`', 43: ',', 47: '.', 44: '/', 10: '§', 93: '¥', 94: '_',
  122: 'F1', 120: 'F2', 99: 'F3', 118: 'F4', 96: 'F5', 97: 'F6',
  98: 'F7', 100: 'F8', 101: 'F9', 109: 'F10', 103: 'F11', 111: 'F12',
  105: 'F13', 107: 'F14', 113: 'F15', 106: 'F16', 64: 'F17',
  79: 'F18', 80: 'F19', 90: 'F20',
  71: '⌧', 76: '⌤', 75: 'Num /', 67: 'Num *', 78: 'Num -',
  69: 'Num +', 81: 'Num =', 65: 'Num .', 95: 'Num ,',
  82: 'Num 0', 83: 'Num 1', 84: 'Num 2', 85: 'Num 3', 86: 'Num 4',
  87: 'Num 5', 88: 'Num 6', 89: 'Num 7', 91: 'Num 8', 92: 'Num 9',
};

/// How 1.0.3 printed a combo, with [layout] keyed by Carbon code as its
/// keyboard labels were.
String _combo103(int keyCode, int mask, [Map<int, String> layout = const {}]) =>
    '${mask & kControlKey != 0 ? '⌃' : ''}'
    '${mask & kOptionKey != 0 ? '⌥' : ''}'
    '${mask & kShiftKey != 0 ? '⇧' : ''}'
    '${mask & kCmdKey != 0 ? '⌘' : ''}'
    '${layout[keyCode] ?? _labels103[keyCode] ?? 'key:$keyCode'}';

final _ctrlAlt = Modifiers.ctrl | Modifiers.alt;

void main() {
  test('layout labels change the displayed key, never the physical binding', () {
    final binding =
        Binding(const BuiltIn(ShortcutCommand.showGrid), carbon(31, kControlOption));
    // Dvorak's R occupies the physical US O key. The binding still holds O.
    final dvorak = labelsByCarbon(const {31: 'R'});
    expect(formatCombo(binding.chord!, keyLabels: dvorak), '⌃⌥R');
    expect(comboSymbols(carbon(31, kControlOption), keyLabels: dvorak),
        ['⌃', '⌥', 'R']);
    expect(binding.chord!.physical, PhysicalKeyboardKey.keyO.usbHidUsage);
    expect(comboLabelFor([binding], binding.command, keyLabels: dvorak), '⌃⌥R');
    expect(formatCombo(carbon(123, kControlOption), keyLabels: dvorak), '⌃⌥←');
    expect(formatCombo(carbon(31, kControlOption)), '⌃⌥O');
  });

  test('every combo prints exactly what 1.0.3 printed', () {
    // The labels half of "macOS behaves exactly as before": every key a
    // shortcut can use, under every modifier set, with and without a layout's
    // own labels, against 1.0.3's table and formatting copied above.
    final layout = {for (final code in _labels103.keys) code: 'L$code'};
    final rekeyed = {
      for (final e in layout.entries)
        if (physicalFromCarbon(e.key) != null) physicalFromCarbon(e.key)!: e.value,
    };
    for (var code = 0; code < 128; code++) {
      if (physicalFromCarbon(code) == null) continue;
      for (final mask in [
        kControlOption,
        kControlKey | kShiftKey,
        kCmdKey,
        kControlKey | kOptionKey | kShiftKey | kCmdKey,
      ]) {
        expect(formatCombo(carbon(code, mask)), _combo103(code, mask),
            reason: 'Carbon $code / $mask');
        expect(formatCombo(carbon(code, mask), keyLabels: rekeyed),
            _combo103(code, mask, layout),
            reason: 'Carbon $code / $mask with a layout');
      }
    }
  });

  test('a rebind for a command absent from the list is added, not dropped', () {
    // The list is rendered from the commands that exist, not from whatever
    // preferences hold, so a row can be on screen with no entry behind it.
    // Rebuilding the list from its existing entries silently dropped such an
    // update: the row went on showing "Not set" and pressing a combo appeared
    // to do nothing at all, forever.
    final without = macDefaults
        .where((b) => b.command != const BuiltIn(ShortcutCommand.leftHalf))
        .toList();
    final wanted =
        Binding(const BuiltIn(ShortcutCommand.leftHalf), carbon(123, kControlOption));

    final result = withRebind(without, wanted);

    expect(result.where((b) => b.command == wanted.command), hasLength(1));
    expect(result.firstWhere((b) => b.command == wanted.command), wanted);
    expect(result, hasLength(without.length + 1));
  });

  group('defaults', () {
    test('macOS: every command on ⌃⌥, the keys 1.0.3 shipped', () {
      expect(macDefaults.map((b) => b.command).toList(),
          [for (final c in ShortcutCommand.values) BuiltIn(c)]);
      expect(
        [for (final b in macDefaults) (b.keyCode, b.modifiers)],
        [
          (31, kControlOption), (123, kControlOption), (124, kControlOption),
          (126, kControlOption), (125, kControlOption), (32, kControlOption),
          (34, kControlOption), (38, kControlOption), (40, kControlOption),
          (36, kControlOption), (8, kControlOption),
        ],
      );
    });

    test('carry the US logical key, so Windows has one to register', () {
      final grid = macDefaults.first.chord!;
      expect(grid.physical, PhysicalKeyboardKey.keyO.usbHidUsage);
      expect(grid.logical, LogicalKeyboardKey.keyO.keyId);
    });

    test('macOS ignores AltGr, which is a Windows notion', () {
      expect(defaultBindings(platform: TargetPlatform.macOS, altGr: true),
          macDefaults);
    });

    test('Windows without AltGr: the same keys on Ctrl+Alt', () {
      expect(defaultBindings(platform: TargetPlatform.windows, altGr: false),
          macDefaults);
    });

    test('Windows with AltGr: the six letter chords move to Win+Shift', () {
      final winShift = Modifiers.meta | Modifiers.shift;
      final moved = {
        ShortcutCommand.showGrid, ShortcutCommand.topLeft,
        ShortcutCommand.topRight, ShortcutCommand.bottomLeft,
        ShortcutCommand.bottomRight, ShortcutCommand.center,
      };
      final altGr = defaultBindings(platform: TargetPlatform.windows, altGr: true);
      final mac = macDefaults;
      for (var i = 0; i < altGr.length; i++) {
        final command = (altGr[i].command as BuiltIn).command;
        expect(altGr[i].chord!.physical, mac[i].chord!.physical,
            reason: '$command keeps its key');
        expect(altGr[i].chord!.modifiers,
            moved.contains(command) ? winShift : _ctrlAlt,
            reason: '$command');
      }
    });

    test('runningDefaults is the macOS set on the test host', () {
      // Flutter reports Android under `flutter test`; every platform but
      // Windows gets the macOS set, so the whole suite keeps testing macOS.
      expect(runningDefaults(), macDefaults);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(runningDefaults(),
          defaultBindings(platform: TargetPlatform.windows, altGr: false));
    });
  });

  test('conflictFor finds a different command already using the combo', () {
    // ⌃⌥→ is rightHalf by default; binding it to leftHalf collides.
    expect(
      conflictFor(macDefaults,
          Binding(const BuiltIn(ShortcutCommand.leftHalf), carbon(124, kControlOption))),
      const BuiltIn(ShortcutCommand.rightHalf),
    );
  });

  test('conflictFor ignores the command being rebound and free combos', () {
    // Rebinding a command to the combo it already has is not a conflict.
    expect(
      conflictFor(macDefaults,
          Binding(const BuiltIn(ShortcutCommand.leftHalf), carbon(123, kControlOption))),
      isNull,
    );
    // An unused combo (⌃⌥⇧←) is free.
    expect(
      conflictFor(macDefaults,
          Binding(const BuiltIn(ShortcutCommand.leftHalf),
              carbon(123, kControlOption | kShiftKey))),
      isNull,
    );
    // An unbound candidate collides with nothing.
    expect(
      conflictFor(macDefaults,
          const Binding.unbound(BuiltIn(ShortcutCommand.leftHalf))),
      isNull,
    );
  });

  test('on macOS a chord recorded under another layout still collides by position',
      () {
    // Dvorak types G at the US U position. Recorded there, ⌃⌥ on that key
    // holds the logical key G, while the default it lands on holds the US
    // placeholder U. macOS registers by position, so it is the same hotkey,
    // and the clash must be found or both would be registered.
    final dvorakU = KeyChord(
      physical: PhysicalKeyboardKey.keyU.usbHidUsage,
      logical: LogicalKeyboardKey.keyG.keyId,
      modifiers: _ctrlAlt,
    );
    expect(
      conflictFor(macDefaults, Binding(const BuiltIn(ShortcutCommand.center), dvorakU)),
      const BuiltIn(ShortcutCommand.topLeft),
    );
  });

  test('on Windows the same chord is a different key, and collides by meaning',
      () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final dvorakU = KeyChord(
      physical: PhysicalKeyboardKey.keyU.usbHidUsage,
      logical: LogicalKeyboardKey.keyG.keyId,
      modifiers: _ctrlAlt,
    );
    final defaults = runningDefaults();
    expect(conflictFor(defaults, Binding(const BuiltIn(ShortcutCommand.center), dvorakU)),
        isNull, reason: 'the key that types G holds no default');
    final dvorakC = KeyChord(
      physical: PhysicalKeyboardKey.keyI.usbHidUsage,
      logical: LogicalKeyboardKey.keyC.keyId,
      modifiers: _ctrlAlt,
    );
    expect(
      conflictFor(defaults, Binding(const BuiltIn(ShortcutCommand.topLeft), dvorakC)),
      const BuiltIn(ShortcutCommand.center),
      reason: 'Center is "the key that types C" wherever that key sits',
    );
  });

  test('sameShortcut asks the platform, where == compares every field', () {
    // Dvorak types J at the US C position: ⌃⌥ recorded there is the default
    // Center hotkey on macOS, though the two bindings are not equal.
    final center = macDefaults.last;
    final dvorak = Binding(
      center.command,
      KeyChord(
        physical: PhysicalKeyboardKey.keyC.usbHidUsage,
        logical: LogicalKeyboardKey.keyJ.keyId,
        modifiers: _ctrlAlt,
      ),
    );
    const unbound = Binding.unbound(BuiltIn(ShortcutCommand.center));
    expect(dvorak, isNot(center));
    expect(sameShortcut(dvorak, center), isTrue);
    expect(sameShortcut(unbound, const Binding.unbound(BuiltIn(ShortcutCommand.center))),
        isTrue);
    expect(sameShortcut(unbound, center), isFalse);
    expect(sameShortcut(center, unbound), isFalse);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(sameShortcut(dvorak, center), isFalse,
        reason: 'on Windows the key that types J is a different hotkey');
  });

  test('a binding can be unbound, and defaults are all bound', () {
    const b = Binding.unbound(BuiltIn(ShortcutCommand.center));
    expect(b.isBound, isFalse);
    expect(macDefaults.every((b) => b.isBound), isTrue);
  });

  test('bindings are equal by value', () {
    // Built by function, not const: Dart canonicalises const instances, so a
    // const equality test passes with `==` deleted.
    Binding make() => Binding(
        const BuiltIn(ShortcutCommand.center), carbon(8, kControlOption));
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(make(),
        isNot(Binding(const BuiltIn(ShortcutCommand.center), carbon(8, kCmdKey))));
    expect(make(), isNot(const Binding.unbound(BuiltIn(ShortcutCommand.center))));
  });

  test('rebinding steals the combo and unbinds the previous owner', () {
    // Give leftHalf the combo rightHalf currently owns (⌃⌥→).
    final next = withRebind(macDefaults,
        Binding(const BuiltIn(ShortcutCommand.leftHalf), carbon(124, kControlOption)));

    Binding of(ShortcutCommand c) =>
        next.firstWhere((b) => b.command == BuiltIn(c));
    expect(of(ShortcutCommand.leftHalf).keyCode, 124);
    expect(of(ShortcutCommand.rightHalf).isBound, isFalse,
        reason: 'the displaced command must become unset, not silently shadowed');
    // Every command still present, order preserved.
    expect(next.map((b) => b.command), macDefaults.map((b) => b.command));
  });

  test('withRebind leaves other bindings untouched when there is no clash', () {
    final next = withRebind(macDefaults,
        Binding(const BuiltIn(ShortcutCommand.leftHalf),
            carbon(123, kControlOption | kShiftKey)));
    expect(next.where((b) => !b.isBound), isEmpty);
    expect(next.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.leftHalf)).modifiers,
        kControlOption | kShiftKey);
  });

  test('comboSymbols splits a combo into individual keycaps', () {
    expect(comboSymbols(carbon(123, kControlOption)), ['⌃', '⌥', '←']);
    expect(comboSymbols(carbon(36, kControlOption | kShiftKey)),
        ['⌃', '⌥', '⇧', '↩']);
    expect(comboSymbols(null), isEmpty);
  });

  test('modifierSymbols says what is held before a key completes the combo',
      () {
    // Split out of comboSymbols precisely because that one answers with
    // *nothing at all* while no key has landed, which is the whole window the
    // recorder needs to draw in.
    expect(comboSymbols(null), isEmpty);
    expect(modifierSymbols(_ctrlAlt), ['⌃', '⌥']);

    expect(modifierSymbols(Modifiers.none), isEmpty);
    expect(
        modifierSymbols(
            Modifiers.ctrl | Modifiers.alt | Modifiers.shift | Modifiers.meta),
        ['⌃', '⌥', '⇧', '⌘']);
    // macOS's canonical order, which is not the order the flags were added in.
    expect(modifierSymbols(Modifiers.meta | Modifiers.ctrl), ['⌃', '⌘']);
  });

  test('every bindable key has a display symbol: no raw key:<code> leaks', () {
    for (var code = 0; code < 128; code++) {
      if (physicalFromCarbon(code) == null) continue;
      expect(formatCombo(carbon(code, kControlOption)), isNot(contains('key:')),
          reason: 'Carbon key code $code renders as a raw code');
    }
  });

  test('letters render uppercase, as macOS renders shortcuts', () {
    expect(formatCombo(carbon(12, kControlOption)), '⌃⌥Q');
    expect(formatCombo(carbon(0, kControlOption)), '⌃⌥A');
    expect(formatCombo(carbon(29, kControlOption)), '⌃⌥0');
    expect(formatCombo(carbon(49, kControlOption)), '⌃⌥␣');
  });

  test('formatCombo renders modifier symbols + key', () {
    expect(formatCombo(carbon(123, kControlOption)), '⌃⌥←');
    expect(formatCombo(carbon(32, kControlOption)), '⌃⌥U');
    expect(formatCombo(carbon(36, kControlOption)), '⌃⌥↩');
  });
}
