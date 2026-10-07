import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/key_chord.dart';

final _ctrlAlt = Modifiers.ctrl | Modifiers.alt;

/// A chord with an explicit logical key, the way a recording under a layout
/// other than US produces one. Built by a function rather than a `const`, so
/// equality is tested on two separate instances (Dart canonicalises const
/// ones, which would let an equality test pass with `==` deleted).
KeyChord _chord(PhysicalKeyboardKey key, LogicalKeyboardKey typed,
        [Modifiers? modifiers]) =>
    KeyChord(
      physical: key.usbHidUsage,
      logical: typed.keyId,
      modifiers: modifiers ?? _ctrlAlt,
    );

void main() {
  test('modifiers combine, and answer for each flag', () {
    final held = Modifiers.ctrl | Modifiers.shift;
    expect(held.has(Modifiers.ctrl), isTrue);
    expect(held.has(Modifiers.shift), isTrue);
    expect(held.has(Modifiers.alt), isFalse);
    expect(held.has(Modifiers.ctrl | Modifiers.alt), isFalse,
        reason: 'has() asks for every flag, not any');
    expect(Modifiers.none.isEmpty, isTrue);
    expect(held.isEmpty, isFalse);
  });

  test('the US logical key of every bindable key is Flutter\'s of the same name',
      () {
    // The rule the table is written by, checked mechanically: a pair typed
    // against the wrong constant shows up here as two different names.
    for (final physical in bindableKeys) {
      final chord = KeyChord.us(physical, _ctrlAlt)!;
      expect(
        LogicalKeyboardKey.findKeyByKeyId(chord.logical)?.debugName,
        PhysicalKeyboardKey.findKeyByCode(physical)!.debugName,
        reason: 'physical 0x${physical.toRadixString(16)}',
      );
    }
  });

  test('KeyChord.us refuses a key a shortcut may not use', () {
    expect(KeyChord.us(PhysicalKeyboardKey.tab.usbHidUsage, _ctrlAlt), isNull);
    expect(KeyChord.us(PhysicalKeyboardKey.escape.usbHidUsage, _ctrlAlt), isNull);
    expect(KeyChord.us(0x00070032, _ctrlAlt), isNull);
  });

  test('chords are equal by value, and every field counts', () {
    final o = _chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO);
    expect(o, _chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO));
    expect(o.hashCode,
        _chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO).hashCode);
    expect(o, isNot(_chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyR)));
    expect(o, isNot(_chord(PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyO)));
    expect(o, isNot(_chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO,
        Modifiers.ctrl)));
  });

  test('a chord round-trips through its stored form', () {
    final chord = _chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyR,
        Modifiers.meta | Modifiers.ctrl);
    expect(chord.toJson(), {
      'physical': PhysicalKeyboardKey.keyO.usbHidUsage,
      'logical': LogicalKeyboardKey.keyR.keyId,
      'modifiers': ['ctrl', 'meta'],
    }, reason: 'modifiers are named, in the order their glyphs are drawn');
    expect(KeyChord.tryFromJson(chord.toJson()), chord);
  });

  group('sameChordAs', () {
    // Dvorak puts R where US has O. Recorded there, the O position carries the
    // logical key R.
    final usO = _chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO);
    final dvorakR = _chord(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyR);
    final usR = _chord(PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    test('on macOS a chord is its position', () {
      expect(usO.sameChordAs(dvorakR), isTrue);
      expect(usR.sameChordAs(dvorakR), isFalse);
      expect(
          usO.sameChordAs(_chord(PhysicalKeyboardKey.keyO,
              LogicalKeyboardKey.keyO, Modifiers.ctrl)),
          isFalse,
          reason: 'different modifiers are a different chord');
    });

    test('on Windows a chord is its meaning', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(usO.sameChordAs(dvorakR), isFalse);
      expect(usR.sameChordAs(dvorakR), isTrue);
    });
  });
}
