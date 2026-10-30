import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/core/key_words.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/l10n/app_localizations_en.dart';
import 'package:orthant/l10n/strings.dart';
import 'package:orthant/overlay/overlay_copy.dart';
import 'package:orthant/shortcuts/bindings.dart';

import 'support/locales.dart';
import 'support/no_english.dart';
import 'support/strg_strings.dart';

/// [actual] holds exactly the words [expected] does, field by field.
///
/// `KeyWords.windows` and `KeyWords.macOS` are built from the strings on every
/// read, so two reads are two objects and `same` would fail on a correct
/// answer. `KeyWords` has no `==` of its own, because nothing in the app
/// compares two of them; what these tests mean by "this platform's words, not
/// the other's" is every field agreeing, and every field is a value (strings, a
/// list of records, a map) that `equals` compares deeply.
void expectSameWords(KeyWords actual, KeyWords expected) {
  expect(actual.modifiers, expected.modifiers);
  expect(actual.joiner, expected.joiner);
  expect(actual.spacedJoiner, expected.spacedJoiner);
  expect(actual.menuGap, expected.menuGap);
  expect(actual.escape, expected.escape);
  expect(actual.system, expected.system);
  expect(actual.named, expected.named);
}

/// English with every key legend replaced by its own message name, so a
/// legend wired to the wrong message shows up as the wrong name.
class _Tagged extends AppLocalizationsEn {
  @override
  String get keyWin => '<keyWin>';
  @override
  String get keyCtrl => '<keyCtrl>';
  @override
  String get keyAlt => '<keyAlt>';
  @override
  String get keyShift => '<keyShift>';
  @override
  String get keyEnter => '<keyEnter>';
  @override
  String get keySpace => '<keySpace>';
  @override
  String get keyTab => '<keyTab>';
  @override
  String get keyBackspace => '<keyBackspace>';
  @override
  String get keyEsc => '<keyEsc>';
  @override
  String get keyHome => '<keyHome>';
  @override
  String get keyEnd => '<keyEnd>';
  @override
  String get keyPageUp => '<keyPageUp>';
  @override
  String get keyPageDown => '<keyPageDown>';
  @override
  String get keyDelete => '<keyDelete>';
  @override
  String get keyNumLock => '<keyNumLock>';
  @override
  String get keyNumEnter => '<keyNumEnter>';
  @override
  String get keyMacEscape => '<keyMacEscape>';
  @override
  String get keyMacReturn => '<keyMacReturn>';
}

/// What each platform calls the keys of a shortcut. macOS's words are pinned
/// byte for byte, because they are what 1.0.x shows; Windows' are its own.
void main() {
  final all = Modifiers.ctrl | Modifiers.alt | Modifiers.shift | Modifiers.meta;

  test('macOS keeps the glyphs and the order it has always used', () {
    final w = KeyWords.macOS;
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
    final w = KeyWords.windows;
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
    final w = KeyWords.windows;
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
      expectSameWords(KeyWords.of(p), KeyWords.macOS);
    }
    expectSameWords(KeyWords.of(TargetPlatform.windows), KeyWords.windows);
  });

  test('current follows the platform the app runs on', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expectSameWords(KeyWords.current, KeyWords.windows);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expectSameWords(KeyWords.current, KeyWords.macOS);
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

  group('the key words are strings', () {
    tearDown(() => setAppStrings(kEnglish));

    test('Windows reads its legends from appStrings on every read', () {
      final english = KeyWords.windows;
      appStrings = StrgStrings();
      final w = KeyWords.windows;
      expect(w.modifierNames(all), ['Win', 'STRG', 'Alt', 'Shift']);
      expect(w.keyName(0x00070028), 'Eingabe');
      expect(w.keyName(0x0007004C), 'Entf');
      expect(w.anyModifier, 'Win, STRG, Alt oder Shift');
      expect(w.join(w.modifierNames(Modifiers.meta | Modifiers.ctrl)),
          'Win+STRG');
      // Words read before the language changed are what they were: it is the
      // next read that follows the strings.
      expect(english.modifierNames(all), ['Win', 'Ctrl', 'Alt', 'Shift']);
      setAppStrings(kEnglish);
      expect(KeyWords.windows.modifierNames(all),
          ['Win', 'Ctrl', 'Alt', 'Shift']);
    });

    test('macOS keeps its glyphs in any language; its esc and its list follow '
        'the strings', () {
      appStrings = StrgStrings();
      final w = KeyWords.macOS;
      expect(w.modifierNames(all), ['⌃', '⌥', '⇧', '⌘']);
      expect(w.join(['⌃', '⌥', '←']), '⌃⌥←');
      expect(w.escape, 'Abbruch');
      expect(w.anyModifier, '⌃, ⌥, ⇧ oder ⌘');
      // And back: the next read follows the language again.
      setAppStrings(kEnglish);
      expect(KeyWords.macOS.escape, 'esc');
    });

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      test('${locale.toLanguageTag()}: the legends stay the English ones, '
          'the list of modifiers is Chinese', () {
        final english = KeyWords.windows;
        setAppStrings(locale);
        final w = KeyWords.windows;
        // The legends are printed on the keyboards, in English everywhere,
        // except the space bar, which prints none and which both operating
        // systems name in Simplified Chinese.
        expect(w.modifiers, english.modifiers);
        expect(w.named, {
          ...english.named,
          if (locale == kSimplified) 0x0007002C: '空格键',
        });
        expect(w.escape, english.escape);
        // macOS's two words are English in Chinese too.
        expect(KeyWords.macOS.escape, 'esc');
        expect(OverlayCopy.macOS.place, 'Return');
        // The one thing with a word in it is the list a sentence makes.
        expect(w.anyModifier, contains('或'));
        expect(w.anyModifier, contains('、'));
        expectNoEnglishIn([w.anyModifier, KeyWords.macOS.anyModifier]);
        expect(KeyWords.macOS.anyModifier, contains('或'));
      });
    }

    test('every legend comes from its own message', () {
      appStrings = _Tagged();
      final w = KeyWords.windows;
      expect([for (final m in w.modifiers) m.name],
          ['<keyWin>', '<keyCtrl>', '<keyAlt>', '<keyShift>']);
      expect(w.escape, '<keyEsc>');
      expect(w.named, {
        0x00070028: '<keyEnter>', 0x0007002C: '<keySpace>',
        0x0007002B: '<keyTab>', 0x0007002A: '<keyBackspace>',
        0x00070029: '<keyEsc>', 0x0007004A: '<keyHome>',
        0x0007004D: '<keyEnd>', 0x0007004B: '<keyPageUp>',
        0x0007004E: '<keyPageDown>', 0x0007004C: '<keyDelete>',
        0x00070053: '<keyNumLock>', 0x00070058: '<keyNumEnter>',
      });
    });

    test('macOS\'s two words come from their own messages', () {
      appStrings = _Tagged();
      expect(KeyWords.macOS.escape, '<keyMacEscape>');
      expect(OverlayCopy.macOS.place, '<keyMacReturn>');
      // Not Windows' words: each platform reads its own.
      expect(KeyWords.windows.escape, '<keyEsc>');
      expect(OverlayCopy.windows.place, '<keyEnter>');
    });

    test('the strings carry every legend the English words had', () {
      // The words object and the ARB are two spellings of one set; if a legend
      // is renamed on one side only, this is where it shows.
      final s = lookupAppLocalizations(kEnglish);
      expect(
        [
          s.keyWin, s.keyCtrl, s.keyAlt, s.keyShift, s.keyEnter, s.keySpace,
          s.keyTab, s.keyBackspace, s.keyEsc, s.keyHome, s.keyEnd, s.keyPageUp,
          s.keyPageDown, s.keyDelete, s.keyNumLock, s.keyNumEnter,
        ],
        [
          'Win', 'Ctrl', 'Alt', 'Shift', 'Enter', 'Space', 'Tab', 'Backspace',
          'Esc', 'Home', 'End', 'PgUp', 'PgDn', 'Del', 'Num Lock', 'Num Enter',
        ],
      );
      expect([s.keyMacEscape, s.keyMacReturn], ['esc', 'Return']);
      expect(s.keyNumpad('/'), 'Num /');
      expect(s.keyListAnyModifier('a', 'b', 'c', 'd'), 'a, b, c or d');
    });

    test('a numpad key reads "Num" in every language, on both platforms', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final locale in [kEnglish, kSimplified, kTraditional, kHongKong]) {
        setAppStrings(locale);
        for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
          debugDefaultTargetPlatformOverride = platform;
          expect(keySymbol(0x00070054), 'Num /',
              reason: '${locale.toLanguageTag()} on $platform');
          expect(keySymbol(0x00070062), 'Num 0');
        }
      }
    });
  });
}
