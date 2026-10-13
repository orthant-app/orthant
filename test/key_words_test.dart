import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/core/key_words.dart';
import 'package:orthant/overlay/overlay_copy.dart';

/// What each platform calls the keys of a shortcut. macOS's words are pinned
/// byte for byte, because they are what 1.0.x shows; Windows' are its own.
void main() {
  final all = Modifiers.ctrl | Modifiers.alt | Modifiers.shift | Modifiers.meta;

  test('macOS keeps the glyphs and the order it has always used', () {
    const w = KeyWords.macOS;
    expect(w.modifierNames(all), ['⌃', '⌥', '⇧', '⌘']);
    expect(w.modifierNames(Modifiers.meta | Modifiers.ctrl), ['⌃', '⌘']);
    expect(w.modifierNames(Modifiers.none), isEmpty);
    expect(w.join(['⌃', '⌥', '←']), '⌃⌥←');
    expect(w.joinSpaced(['⌃', '⌥', '←']), '⌃ ⌥ ←');
    expect(w.anyModifier, '⌃, ⌥, ⇧ or ⌘');
    expect(w.shiftName, '⇧');
    expect(w.escape, 'esc');
    expect(w.system, 'macOS');
    expect(w.menuItem('Open Grid', '⌃⌥O'), 'Open Grid   ⌃⌥O');
  });

  test('macOS names no key of its own: every glyph is the shared table\'s', () {
    for (final usage in [0x00070028, 0x0007002C, 0x00070029, 0x00070050]) {
      expect(KeyWords.macOS.keyName(usage), isNull, reason: '0x${usage.toRadixString(16)}');
    }
  });

  test('Windows names its modifiers, Win first, and joins them with +', () {
    const w = KeyWords.windows;
    expect(w.modifierNames(all), ['Win', 'Ctrl', 'Alt', 'Shift']);
    expect(w.modifierNames(Modifiers.shift | Modifiers.ctrl), ['Ctrl', 'Shift']);
    expect(w.join(['Win', 'Ctrl', 'Shift', '←']), 'Win+Ctrl+Shift+←');
    expect(w.joinSpaced(['Ctrl', 'Shift']), 'Ctrl+Shift');
    expect(w.anyModifier, 'Win, Ctrl, Alt or Shift');
    expect(w.shiftName, 'Shift');
    expect(w.escape, 'Esc');
    expect(w.system, 'Windows');
    // A tab is where a native menu puts its right-aligned accelerators.
    expect(w.menuItem('Open Grid', 'Win+Ctrl+Shift+O'),
        'Open Grid\tWin+Ctrl+Shift+O');
  });

  test('Windows calls its named keys by name, and keeps the arrows', () {
    const w = KeyWords.windows;
    expect(
      {
        for (final usage in [
          0x00070028, 0x0007002C, 0x0007002B, 0x0007002A, 0x00070029,
          0x0007004A, 0x0007004D, 0x0007004B, 0x0007004E, 0x0007004C,
          0x00070053, 0x00070058,
        ])
          usage: w.keyName(usage),
      },
      {
        0x00070028: 'Enter', 0x0007002C: 'Space', 0x0007002B: 'Tab',
        0x0007002A: 'Backspace', 0x00070029: 'Esc', 0x0007004A: 'Home',
        0x0007004D: 'End', 0x0007004B: 'PgUp', 0x0007004E: 'PgDn',
        0x0007004C: 'Del', 0x00070053: 'Num Lock', 0x00070058: 'Num Enter',
      },
    );
    for (final arrow in [0x00070050, 0x0007004F, 0x00070051, 0x00070052]) {
      expect(w.keyName(arrow), isNull, reason: 'Windows draws arrows too');
    }
    expect(w.keyName(0x00070004), isNull, reason: 'a letter is the same');
    expect(w.keyName(null), isNull);
  });

  test('every other platform reads as macOS, where the app began', () {
    for (final p in TargetPlatform.values) {
      if (p == TargetPlatform.windows) continue;
      expect(KeyWords.of(p), same(KeyWords.macOS), reason: '$p');
    }
    expect(KeyWords.of(TargetPlatform.windows), same(KeyWords.windows));
  });

  test('current follows the platform the app runs on', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(KeyWords.current, same(KeyWords.windows));
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(KeyWords.current, same(KeyWords.macOS));
  });

  test('the settings window and the overlay name the same keys', () {
    // The overlay's words are OverlayCopy's; the settings window draws its
    // keys from here and teaches the overlay's save chord in its own copy.
    // Held equal, so the chord the pane teaches is the one the grid shows.
    for (final (words, copy, primary) in [
      (KeyWords.macOS, OverlayCopy.macOS, Modifiers.meta),
      (KeyWords.windows, OverlayCopy.windows, Modifiers.ctrl),
    ]) {
      expect(words.join([...words.modifierNames(primary), 'S']), copy.save);
    }
    expect(KeyWords.windows.keyName(0x00070028), OverlayCopy.windows.place);
  });
}
