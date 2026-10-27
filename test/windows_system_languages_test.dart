import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller_windows.dart';
import 'package:orthant/core/windows_system_languages.dart';
import 'package:orthant/l10n/languages.dart';

import 'support/locales.dart';

// The pure half of reading the OS's languages on Windows: what
// GetThreadPreferredUILanguages writes and how the embedder reads it
// (system_utils.cc), so that Orthant's first read agrees with the list the
// dispatcher holds later. The call itself is in
// windows_system_languages_windows_test.dart, which only Windows runs.

void main() {
  group('the multi-string Windows writes', () {
    test('several languages in order, ended by an empty one', () {
      expect(splitMultiString('zh-TW\u0000zh-Hant\u0000en-US\u0000\u0000'),
          ['zh-TW', 'zh-Hant', 'en-US']);
    });

    test('one language', () {
      expect(splitMultiString('en-US\u0000\u0000'), ['en-US']);
    });

    test('nothing at all, or only the end', () {
      expect(splitMultiString(''), isEmpty);
      expect(splitMultiString('\u0000\u0000'), isEmpty);
      expect(splitMultiString('\u0000'), isEmpty);
    });

    test('whatever follows the empty string is not a language', () {
      expect(splitMultiString('en-US\u0000\u0000zh-CN\u0000\u0000'), ['en-US']);
    });

    test('a last language cut short of its NUL is kept, not dropped', () {
      expect(splitMultiString('zh-CN\u0000en-US'), ['zh-CN', 'en-US']);
    });
  });

  group('a language name, as the embedder splits it', () {
    Locale? parse(String name) => parsePreferredLanguage(name);

    test('Windows\' bare Chinese: language and region, no script', () {
      expect(parse('zh-TW'), const Locale('zh', 'TW'));
      expect(parse('zh-CN'), const Locale('zh', 'CN'));
      expect(parse('zh-HK'), const Locale('zh', 'HK'));
      expect(parse('zh-TW')!.scriptCode, isNull);
    });

    test('language, script and region', () {
      expect(
          parse('zh-Hant-TW'),
          const Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'));
      expect(parse('zh-Hans-CN'),
          const Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'));
      expect(parse('sr-Latn-RS'),
          const Locale.fromSubtags(
              languageCode: 'sr', scriptCode: 'Latn', countryCode: 'RS'));
    });

    test('a second part of four letters is a script, anything else a region',
        () {
      expect(parse('zh-Hant'), kTraditional);
      expect(parse('zh-Hans'),
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'));
      expect(parse('en-US'), const Locale('en', 'US'));
      expect(parse('es-419'), const Locale('es', '419'));
    });

    test('a language alone', () {
      expect(parse('en'), const Locale('en'));
      expect(parse('fil'), const Locale('fil'));
    });

    test('private use is dropped, and so is what a fourth part would be', () {
      expect(parse('en-US-x-foo'), const Locale('en', 'US'));
      expect(parse('zh-Hant-x-private'), kTraditional);
      // Four parts and no x: the embedder keeps the language alone.
      expect(parse('de-DE-1996-u'), const Locale('de'));
    });

    test('a name with no language is no locale', () {
      expect(parse(''), isNull);
      expect(parse('x-foo'), isNull);
      expect(parse('-US'), isNull);
    });

    test('the list keeps the order and skips what names nothing', () {
      expect(parsePreferredLanguages(['zh-TW', '', 'en-US']),
          [const Locale('zh', 'TW'), const Locale('en', 'US')]);
    });
  });

  group('what Orthant makes of them', () {
    List<Locale> read(String multiString) =>
        parsePreferredLanguages(splitMultiString(multiString));

    test('bare zh-TW is Traditional, and WinSparkle is told zh-TW', () {
      final system = read('zh-TW\u0000en-US\u0000\u0000');
      expect(system.first, const Locale('zh', 'TW'));
      expect(resolveAppLocale(system), kTraditional);
      expect(updaterLanguage(system, null), 'zh-TW');
    });

    test('bare zh-CN is Simplified, and WinSparkle is told zh-CN', () {
      final system = read('zh-CN\u0000en-US\u0000\u0000');
      expect(resolveAppLocale(system), kSimplified);
      expect(updaterLanguage(system, null), 'zh-CN');
    });

    test('zh-Hant-TW is Traditional too', () {
      final system = read('zh-Hant-TW\u0000\u0000');
      expect(resolveAppLocale(system), kTraditional);
      expect(updaterLanguage(system, null), 'zh-TW');
    });

    test('Hong Kong is Hong Kong Traditional, and zh-TW for WinSparkle', () {
      final system = read('zh-HK\u0000zh-Hant\u0000en-US\u0000\u0000');
      expect(resolveAppLocale(system), kHongKong);
      expect(updaterLanguage(system, null), 'zh-TW');
    });

    test('en-US is English', () {
      final system = read('en-US\u0000\u0000');
      expect(resolveAppLocale(system), kEnglish);
      expect(updaterLanguage(system, null), 'en');
    });

    test('a Japanese Windows with English after it is English, in order', () {
      final system = read('ja-JP\u0000en-US\u0000zh-TW\u0000\u0000');
      expect(resolveAppLocale(system), kEnglish);
      expect(updaterLanguage(system, null), 'en');
    });
  });
}
