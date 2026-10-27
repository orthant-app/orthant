import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/settings/shortcuts_screen.dart' as screen;
import 'package:orthant/shortcuts/command_labels.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

import 'support/locales.dart';
import 'support/no_english.dart';

/// The one place a command gets its name. The Shortcuts list, its notices, the
/// screen reader's row labels and the region picker's collision notice all ask
/// it, so a command is called one thing everywhere in a language.
void main() {
  AppLocalizations strings(Locale locale) => lookupAppLocalizations(locale);

  const generated = CustomRegion(
    id: 'g', name: 'Left ⅔', cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0,
  );
  const authored = CustomRegion(
    id: 'a', name: 'Reading pane', cols: 3, rows: 1, c0: 1, c1: 2, r0: 0, r1: 0,
  );

  /// What 1.0.x and 1.1.x call the eleven commands, character for character.
  const english = {
    ShortcutCommand.showGrid: 'Open grid',
    ShortcutCommand.leftHalf: 'Left half',
    ShortcutCommand.rightHalf: 'Right half',
    ShortcutCommand.topHalf: 'Top half',
    ShortcutCommand.bottomHalf: 'Bottom half',
    ShortcutCommand.topLeft: 'Top-left quarter',
    ShortcutCommand.topRight: 'Top-right quarter',
    ShortcutCommand.bottomLeft: 'Bottom-left quarter',
    ShortcutCommand.bottomRight: 'Bottom-right quarter',
    ShortcutCommand.maximize: 'Maximize',
    ShortcutCommand.center: 'Center',
  };

  test('English keeps the names it always had', () {
    for (final entry in english.entries) {
      expect(commandLabel(BuiltIn(entry.key), const [], strings(kEnglish)),
          entry.value);
    }
    expect(english.keys.toSet(), ShortcutCommand.values.toSet(),
        reason: 'a command added without a name here is a command added '
            'without one in English');
  });

  test('kCommandLabels is the English table, for the site\'s docs', () {
    expect(kCommandLabels, english);
    expect(screen.kCommandLabels, same(kCommandLabels),
        reason: 'site_docs_test reads it through the screen\'s own library');
  });

  for (final locale in [kSimplified, kTraditional, kHongKong]) {
    test('every built-in has its own name in ${locale.toLanguageTag()}', () {
      final names = [
        for (final c in ShortcutCommand.values)
          commandLabel(BuiltIn(c), const [], strings(locale)),
      ];
      expect(names.toSet(), hasLength(ShortcutCommand.values.length),
          reason: 'two commands with one name cannot be told apart in a list '
              'or a notice');
      expectNoEnglishIn(names);
      expect(names, isNot(contains('')));
    });
  }

  test('the Chinese names, pinned for the operator\'s review', () {
    String name(Locale l, ShortcutCommand c) =>
        commandLabel(BuiltIn(c), const [], strings(l));
    expect(name(kSimplified, ShortcutCommand.showGrid), '打开网格');
    expect(name(kSimplified, ShortcutCommand.leftHalf), '左半屏');
    expect(name(kSimplified, ShortcutCommand.topLeft), '左上四分之一');
    expect(name(kSimplified, ShortcutCommand.center), '居中');
    expect(name(kTraditional, ShortcutCommand.showGrid), '開啟格線');
    expect(name(kTraditional, ShortcutCommand.leftHalf), '左半部');
    expect(name(kTraditional, ShortcutCommand.topLeft), '左上四分之一');
    expect(name(kTraditional, ShortcutCommand.center), '置中');
  });

  group('a custom region', () {
    test('a generated name is shown in the language, an authored one as '
        'written', () {
      final regions = [generated, authored];
      expect(commandLabel(const Custom('g'), regions, strings(kEnglish)),
          'Left ⅔');
      expect(commandLabel(const Custom('g'), regions, strings(kSimplified)),
          '左 ⅔');
      expect(commandLabel(const Custom('g'), regions, strings(kTraditional)),
          '左 ⅔');
      for (final locale in [kEnglish, kSimplified, kTraditional]) {
        expect(commandLabel(const Custom('a'), regions, strings(locale)),
            'Reading pane',
            reason: 'the user named it; no language renames it');
      }
    });

    test('a region the list no longer holds still has a name', () {
      // The loader drops a binding whose region did not survive, so this is
      // unreachable by design, and a build-time throw in a Release build is a
      // featureless grey box rather than a message.
      expect(commandLabel(const Custom('gone'), const [], strings(kEnglish)),
          'Custom region');
      expect(commandLabel(const Custom('gone'), const [], strings(kSimplified)),
          '自定义区域');
      expect(commandLabel(const Custom('gone'), const [], strings(kTraditional)),
          '自訂區域');
    });
  });
}
