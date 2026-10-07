import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/carbon_keys.dart';
import 'package:orthant/core/key_chord.dart';

/// Every Carbon mask a recorded shortcut can carry: each non-empty subset of
/// the four modifiers.
final _masks = [
  for (var bits = 1; bits < 16; bits++)
    (bits & 1 != 0 ? kControlKey : 0) |
        (bits & 2 != 0 ? kOptionKey : 0) |
        (bits & 4 != 0 ? kShiftKey : 0) |
        (bits & 8 != 0 ? kCmdKey : 0),
];

/// Every Carbon key code the table knows, found by asking rather than by
/// reading the table, so a test cannot share a mistake with it.
final _codes = [
  for (var code = 0; code < 128; code++)
    if (physicalFromCarbon(code) != null) code,
];

void main() {
  test('the table is one-to-one over the 101 keys a shortcut may use', () {
    expect(_codes, hasLength(101));
    expect(bindableKeys, hasLength(101));
    for (final physical in bindableKeys) {
      final code = carbonKeyCode(physical);
      expect(code, isNotNull, reason: 'bindable 0x${physical.toRadixString(16)} has no Carbon code');
      expect(physicalFromCarbon(code!), physical);
    }
  });

  test('a Carbon code names the key Flutter reports for it on macOS', () {
    // kMacOsToPhysicalKey is the engine's own table: the physical key a macOS
    // key event with that code arrives as. A migrated shortcut therefore holds
    // exactly the key the recorder would hold had it been recorded today.
    for (final code in _codes) {
      expect(physicalFromCarbon(code), kMacOsToPhysicalKey[code]!.usbHidUsage,
          reason: 'Carbon $code');
    }
  });

  test('no key Flutter can report has a Carbon code unless it is bindable', () {
    for (final key in PhysicalKeyboardKey.knownPhysicalKeys) {
      if (carbonKeyCode(key.usbHidUsage) != null) {
        expect(isBindableKey(key.usbHidUsage), isTrue, reason: '$key');
      }
    }
    // The ISO "non-US #" usage the table once also sent to 42. Flutter knows no
    // key with it, so nothing could ever have been recorded on it.
    expect(PhysicalKeyboardKey.findKeyByCode(0x00070032), isNull);
    expect(carbonKeyCode(0x00070032), isNull);
    expect(physicalFromCarbon(42), PhysicalKeyboardKey.backslash.usbHidUsage);
  });

  test('every mask the recorder can write converts both ways unchanged', () {
    for (final mask in _masks) {
      expect(carbonModifiers(modifiersFromCarbon(mask)!), mask, reason: 'mask $mask');
    }
    expect(modifiersFromCarbon(0), Modifiers.none);
  });

  test('a mask holding any other bit is refused, not trimmed', () {
    // Trimming would register a different chord from the one stored.
    for (final mask in [kControlOption | 1, kControlOption | 1024, -1, 0x1FFFF]) {
      expect(modifiersFromCarbon(mask), isNull, reason: 'mask $mask');
    }
  });

  test('every shortcut an earlier version could store comes back unchanged', () {
    // The whole of "macOS behaves exactly as before" at the unit level: a
    // stored key code and mask, through the migration and back out to the
    // registration, is the same key code and mask. 101 keys x 15 masks.
    for (final code in _codes) {
      for (final mask in _masks) {
        final chord = chordFromCarbon(code, mask);
        expect(chord, isNotNull, reason: 'Carbon $code / $mask');
        expect(carbonKeyCode(chord!.physical), code);
        expect(carbonModifiers(chord.modifiers), mask);
      }
    }
  });

  test('chordFromCarbon refuses what could never have been registered', () {
    expect(chordFromCarbon(kUnboundKey, 0), isNull);
    expect(chordFromCarbon(31, 0), isNull, reason: 'a bare key');
    expect(chordFromCarbon(0x80, kControlOption), isNull);
    expect(chordFromCarbon(48, kControlOption), isNull, reason: 'Tab');
    expect(chordFromCarbon(31, kControlOption | 1), isNull);
  });

  test('a migrated chord carries the US placeholder for its logical key', () {
    final chord = chordFromCarbon(31, kControlOption)!;
    expect(chord.physical, PhysicalKeyboardKey.keyO.usbHidUsage);
    expect(chord.logical, LogicalKeyboardKey.keyO.keyId);
    expect(chord.modifiers, Modifiers.ctrl | Modifiers.alt);
  });
}
