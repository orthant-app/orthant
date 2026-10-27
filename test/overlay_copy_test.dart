import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/l10n/strings.dart';
import 'package:orthant/overlay/overlay_copy.dart';

import 'support/locales.dart';
import 'support/no_english.dart';

/// The overlay names three things that differ by platform: the key that
/// places, the chord that places and saves, and what a global coordinate is
/// counted in. macOS's words are pinned byte for byte, because they are what
/// 1.0.x speaks and shows; Windows' are the platform's own.
void main() {
  test('macOS keeps the words it has always used', () {
    final c = OverlayCopy.of(TargetPlatform.macOS);
    expect(c.saveHint, '⌘S  save this shape as a shortcut');
    expect(c.gridHint,
        'Arrow keys move. Shift and arrow keys extend. '
        'Return places the window. Escape cancels.');
    expect(c.opened('TextEdit', 6, 4),
        'Grid open for TextEdit. 6 columns, 4 rows. Arrow keys move, '
        'Shift and arrows extend, Return places, Escape cancels.');
    expect(c.unit, 'points');
  });

  test('Windows names its own keys, and counts in pixels', () {
    final c = OverlayCopy.of(TargetPlatform.windows);
    expect(c.saveHint, 'Ctrl+S  save this shape as a shortcut');
    expect(c.gridHint,
        'Arrow keys move. Shift and arrow keys extend. '
        'Enter places the window. Escape cancels.');
    expect(c.opened('Notepad', 6, 6),
        'Grid open for Notepad. 6 columns, 6 rows. Arrow keys move, '
        'Shift and arrows extend, Enter places, Escape cancels.');
    expect(c.unit, 'pixels');
  });

  test('every other platform reads as macOS, where the overlay began', () {
    for (final p in TargetPlatform.values) {
      if (p == TargetPlatform.windows) continue;
      expect(OverlayCopy.of(p), same(OverlayCopy.macOS), reason: '$p');
    }
  });

  test('an empty app name is the captured window, on both platforms', () {
    for (final p in [TargetPlatform.macOS, TargetPlatform.windows]) {
      expect(OverlayCopy.of(p).opened('', 2, 2),
          startsWith('Grid open for the captured window. 2 columns'));
    }
  });

  group('in Chinese', () {
    tearDown(() => setAppStrings(kEnglish));

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        test('${locale.toLanguageTag()} on $platform: all of it is Chinese, '
            'around the platform\'s own key words', () {
          setAppStrings(locale);
          final s = appStrings;
          final c = OverlayCopy.of(platform);
          // The key words are English in every language (they are printed
          // that way), so they are the only Latin left.
          expectNoEnglishIn([
            c.saveHint,
            c.gridHint,
            c.opened('記事本', 6, 4),
            c.opened('', 6, 4),
            c.unit,
          ]);
          expect(c.saveHint, startsWith(c.save));
          expect(c.gridHint, contains(c.place));
          expect(c.opened('記事本', 6, 4), contains(c.place));
          expect(c.opened('記事本', 6, 4), contains('記事本'));
          expect(c.opened('', 6, 4), contains(s.overlayCapturedWindow));
          expect(c.opened('', 6, 4),
              contains('${s.overlayColumns(6)}，${s.overlayRows(4)}'));
          expect(
              c.unit,
              platform == TargetPlatform.windows
                  ? s.overlayUnitPixels
                  : s.overlayUnitPoints);
        });
      }
    }

    test('the count is a plural message: one column, not "1 columns"', () {
      final en = lookupAppLocalizations(kEnglish);
      expect(en.overlayColumns(1), '1 column');
      expect(en.overlayColumns(6), '6 columns');
      expect(en.overlayRows(1), '1 row');
      expect(en.overlayRows(0), '0 rows');
      final zh = lookupAppLocalizations(kSimplified);
      expect(zh.overlayColumns(1), contains('1'));
      expect(zh.overlayColumns(6), contains('6'));
    });
  });
}
