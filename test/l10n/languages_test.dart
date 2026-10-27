import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/l10n/languages.dart';

/// The four locales Orthant ships, as `AppLocalizations.supportedLocales`
/// spells them. The resolver hands back one of these exactly as given (never
/// the normalized form), because the main engine sends `toLanguageTag()` of
/// the result to the overlay engine and the wire tags are `zh` and `zh-Hant`.
const kEnglish = Locale('en');
const kSimplified = Locale('zh');
const kTraditional = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
const kHongKong = Locale.fromSubtags(
    languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK');

Locale _p(String tag) => parseLanguageTag(tag);

List<Locale> _prefs(List<String> tags) => tags.map(_p).toList();

void main() {
  test('the test constants are the real supported locales', () {
    expect(AppLocalizations.supportedLocales,
        <Locale>[kEnglish, kSimplified, kTraditional, kHongKong]);
  });

  group('parseLanguageTag', () {
    test('splits language, script and region, with - or _', () {
      final p = _p('zh-Hant-TW');
      expect(p.languageCode, 'zh');
      expect(p.scriptCode, 'Hant');
      expect(p.countryCode, 'TW');
      expect(_p('zh_Hant_TW'), _p('zh-Hant-TW'));
    });

    test('a 4-letter subtag is the script, a 2-letter or 3-digit one the '
        'region', () {
      expect(_p('zh-Hant'), kTraditional);
      expect(_p('zh-HK').scriptCode, isNull);
      expect(_p('zh-HK').countryCode, 'HK');
      expect(_p('es-419').countryCode, '419');
      expect(_p('en'), kEnglish);
      expect(_p('zh'), kSimplified);
    });

    test('is lenient about case', () {
      expect(_p('ZH-hant-hk'), kHongKong);
      expect(_p('EN'), kEnglish);
    });

    test('never throws on junk, and the result matches nothing', () {
      for (final junk in <String>[
        '',
        '!!',
        ' ',
        '-',
        '_',
        '--',
        'zh-',
        '-zh',
        'zh--Hant',
        'zh-!!',
        '12',
        'x',
        'zh-Hant-TW-!!',
        '中文',
      ]) {
        late Locale parsed;
        expect(() => parsed = _p(junk), returnsNormally, reason: 'for "$junk"');
        expect(
            resolveAppLocale(<Locale>[], choice: junk), kEnglish,
            reason: 'for "$junk"');
        expect(parsed.languageCode, 'und', reason: 'for "$junk"');
      }
    });
  });

  group('normalizeLocale', () {
    test('a script-less zh gets Hant for TW, HK and MO, Hans otherwise', () {
      Locale n(String tag) => normalizeLocale(_p(tag));
      expect(n('zh-TW').scriptCode, 'Hant');
      expect(n('zh-HK').scriptCode, 'Hant');
      expect(n('zh-MO').scriptCode, 'Hant');
      expect(n('zh-CN').scriptCode, 'Hans');
      expect(n('zh-SG').scriptCode, 'Hans');
      expect(n('zh').scriptCode, 'Hans');
      expect(n('zh-HK').countryCode, 'HK', reason: 'the region is kept');
    });

    test('an explicit script is kept, whatever the region', () {
      expect(normalizeLocale(_p('zh-Hans-HK')), _p('zh-Hans-HK'));
      expect(normalizeLocale(_p('zh-Hant-CN')), _p('zh-Hant-CN'));
      expect(normalizeLocale(_p('zh-Latn')), _p('zh-Latn'));
    });

    test('every other locale is returned as is', () {
      for (final tag in <String>['en', 'en-US', 'ja-JP', 'fr', 'pt-BR']) {
        expect(normalizeLocale(_p(tag)), _p(tag), reason: tag);
      }
    });

    test('supported locales normalize the same way', () {
      expect(normalizeLocale(kSimplified), _p('zh-Hans'));
      expect(normalizeLocale(kTraditional), _p('zh-Hant'));
      expect(normalizeLocale(kHongKong), _p('zh-Hant-HK'));
    });
  });

  group('resolveAppLocale with no choice', () {
    final table = <List<Object>>[
      [<String>[], kEnglish],
      [<String>['en-US'], kEnglish],
      [<String>['en-GB', 'zh-CN'], kEnglish],
      [<String>['zh-Hans-CN'], kSimplified],
      [<String>['zh-CN'], kSimplified],
      [<String>['zh'], kSimplified],
      [<String>['zh-SG'], kSimplified],
      [<String>['zh-Hant-TW'], kTraditional],
      [<String>['zh-TW'], kTraditional],
      [<String>['zh-MO'], kTraditional],
      [<String>['zh-Hant-MO'], kTraditional],
      [<String>['zh-Hant'], kTraditional],
      [<String>['zh-Hant-HK'], kHongKong],
      [<String>['zh-HK'], kHongKong],
      // Script beats region: a Simplified reader in Hong Kong.
      [<String>['zh-Hans-HK'], kSimplified],
      // Strict order: the English above it outranks the Chinese below it.
      [<String>['ja-JP', 'en-US', 'zh-TW'], kEnglish],
      [<String>['ja-JP', 'zh-TW'], kTraditional],
      [<String>['fr-FR'], kEnglish],
      [<String>['zh-Latn'], kEnglish],
    ];
    for (final row in table) {
      final tags = row[0] as List<String>;
      final want = row[1] as Locale;
      test('$tags -> ${want.toLanguageTag()}', () {
        expect(resolveAppLocale(_prefs(tags)), want);
      });
    }

    test('hands back the element of supported as given, not the normalized '
        'form', () {
      // Simplified is Locale('zh'), not zh-Hans: the overlay engine is sent
      // toLanguageTag() of this, and its tests expect these three tags.
      expect(resolveAppLocale(_prefs(['zh-CN'])).toLanguageTag(), 'zh');
      expect(resolveAppLocale(_prefs(['zh-TW'])).toLanguageTag(), 'zh-Hant');
      expect(
          resolveAppLocale(_prefs(['zh-HK'])).toLanguageTag(), 'zh-Hant-HK');
      expect(resolveAppLocale(_prefs(['en-GB'])).toLanguageTag(), 'en');
    });

    test('a supported locale with no script covers every script of its '
        'language', () {
      expect(
          resolveAppLocale(_prefs(['en-Latn']), fallback: kSimplified),
          kEnglish);
      expect(
          resolveAppLocale(_prefs(['fr-FR']), fallback: kSimplified),
          kSimplified);
    });

    test('returns the fallback when nothing matches, whatever it is', () {
      expect(
          resolveAppLocale(_prefs(['fr-FR']), fallback: kSimplified),
          kSimplified);
    });
  });

  group('resolveAppLocale with a choice', () {
    Locale r(String choice, List<String> prefs) =>
        resolveAppLocale(_prefs(prefs), choice: choice);

    test('the choice outranks the system languages', () {
      expect(r('en', ['zh-TW']), kEnglish);
      expect(r('zh-Hant', ['en-US']), kTraditional);
      expect(r('zh-Hans', ['en-US', 'zh-TW']), kSimplified);
    });

    test('a null choice is System', () {
      expect(resolveAppLocale(_prefs(['zh-TW']), choice: null), kTraditional);
    });

    test('a Hong Kong choice on an English Mac keeps its region', () {
      expect(r('zh-Hant-HK', ['en-US']), kHongKong);
      expect(r('zh-HK', ['en-US']), kHongKong);
    });

    test('a region-less choice takes the region a system locale of the same '
        'language and script supplies (the Hong Kong fold)', () {
      expect(r('zh-Hant', ['en-US', 'zh-Hant-HK']), kHongKong);
      expect(r('zh-Hant', ['zh-HK']), kHongKong);
      // The first preferred locale has no variant, a later one does.
      expect(r('zh-Hant', ['zh-TW', 'zh-HK']), kHongKong);
    });

    test('the fold needs the same script: script beats region', () {
      expect(r('zh-Hans', ['zh-HK']), kSimplified);
      expect(r('zh-Hans', ['zh-Hant-HK']), kSimplified);
    });

    test('the fold never crosses languages', () {
      const supported = <Locale>[
        kEnglish,
        Locale('de'),
        Locale('de', 'AT'),
        Locale('en', 'GB'),
      ];
      expect(
          resolveAppLocale(_prefs(['de-AT']), choice: 'en', supported: supported),
          kEnglish);
      expect(
          resolveAppLocale(_prefs(['de-AT', 'en-GB']),
              choice: 'en', supported: supported),
          const Locale('en', 'GB'),
          reason: 'but a later locale of the choice\'s own language still does');
    });

    test('the fold needs a region Orthant has a variant for', () {
      expect(r('zh-Hant', ['zh-TW']), kTraditional);
      expect(r('zh-Hant', ['en-US']), kTraditional);
      expect(r('en', ['en-GB']), kEnglish);
    });

    test('a choice with a region other than Hong Kong gets the region-less '
        'Traditional, even beside a Hong Kong system locale', () {
      expect(r('zh-Hant-TW', ['zh-HK']), kTraditional);
    });

    test('a choice Orthant has no match for behaves as System', () {
      expect(r('ja', ['zh-TW']), kTraditional);
      expect(r('ja', []), kEnglish);
      expect(r('', ['zh-TW']), kTraditional);
      expect(r('!!', ['zh-TW']), kTraditional);
      expect(r('!!', ['ja-JP', 'en-US', 'zh-TW']), kEnglish);
    });

    test('an old stored tag still finds its language', () {
      expect(r('zh-CN', ['en-US']), kSimplified);
      expect(r('zh-TW', ['en-US']), kTraditional);
      expect(r('en-GB', ['zh-TW']), kEnglish);
    });
  });

  group('languageOptions', () {
    test('lists one option per language and script, in the template '
        'language first', () {
      final options = languageOptions();
      expect(options.map((o) => o.tag).toList(),
          <String>['en', 'zh-Hans', 'zh-Hant']);
      expect(options.map((o) => o.name).toList(),
          <String>['English', '简体中文', '繁體中文']);
    });

    test('Hong Kong has no entry of its own', () {
      expect(languageOptions().where((o) => o.tag.contains('HK')), isEmpty);
    });

    test('puts the template language first even when supported does not', () {
      final options = languageOptions(
          supported: <Locale>[kSimplified, kTraditional, kHongKong, kEnglish],
          nativeName: (l) => l.toLanguageTag());
      expect(options.map((o) => o.tag).toList(),
          <String>['en', 'zh-Hans', 'zh-Hant']);
    });

    test('names a group by its region-less locale, not by a variant of it', () {
      final asked = <Locale>[];
      languageOptions(
          supported: <Locale>[kEnglish, kHongKong, kTraditional],
          nativeName: (l) {
            asked.add(l);
            return l.toLanguageTag();
          });
      expect(asked, <Locale>[kEnglish, kTraditional]);
    });

    test('LanguageOption compares by value', () {
      expect(const LanguageOption('en', 'English'),
          const LanguageOption('en', 'English'));
      expect(const LanguageOption('en', 'English'),
          isNot(const LanguageOption('en', 'Anglais')));
      expect(const LanguageOption('en', 'English').hashCode,
          const LanguageOption('en', 'English').hashCode);
    });
  });

  group('optionTagFor', () {
    final options = languageOptions();
    test('a stored choice belongs to the option of its language and script',
        () {
      expect(optionTagFor('zh-Hant-HK', options), 'zh-Hant');
      expect(optionTagFor('zh-TW', options), 'zh-Hant');
      expect(optionTagFor('zh-Hant', options), 'zh-Hant');
      expect(optionTagFor('zh-CN', options), 'zh-Hans');
      expect(optionTagFor('zh-Hans', options), 'zh-Hans');
      expect(optionTagFor('zh', options), 'zh-Hans');
      expect(optionTagFor('en-GB', options), 'en');
      expect(optionTagFor('en', options), 'en');
    });

    test('null, or a choice no option matches, is System (null)', () {
      expect(optionTagFor('ja', options), isNull);
      expect(optionTagFor(null, options), isNull);
      expect(optionTagFor('', options), isNull);
      expect(optionTagFor('!!', options), isNull);
      expect(optionTagFor('zh-Latn', options), isNull);
    });
  });

  group('a next language needs no resolver change', () {
    // Japanese exists only in this fixture. Nothing in lib/l10n/languages.dart
    // names it: shipping an app_ja.arb is what would make it selectable.
    const ja = Locale('ja');
    const supported = <Locale>[kEnglish, ja, kSimplified, kTraditional, kHongKong];
    String nativeName(Locale l) =>
        l.languageCode == 'ja' ? '日本語' : defaultNativeName(l);

    test('it appears in the picker, after English', () {
      final options = languageOptions(supported: supported, nativeName: nativeName);
      expect(options, contains(const LanguageOption('ja', '日本語')));
      expect(options.map((o) => o.tag).toList(),
          <String>['en', 'ja', 'zh-Hans', 'zh-Hant']);
    });

    test('a Japanese system language resolves to it', () {
      expect(resolveAppLocale(_prefs(['ja-JP']), supported: supported), ja);
      expect(
          resolveAppLocale(_prefs(['ja-JP', 'en-US', 'zh-TW']),
              supported: supported),
          ja);
    });

    test('a Japanese choice resolves to it', () {
      expect(
          resolveAppLocale(_prefs(['en-US']), choice: 'ja', supported: supported),
          ja);
    });

    test('and the Chinese rules are unchanged beside it', () {
      expect(resolveAppLocale(_prefs(['zh-HK']), supported: supported),
          kHongKong);
      expect(resolveAppLocale(_prefs(['fr-FR']), supported: supported),
          kEnglish);
    });

    test('optionTagFor knows it', () {
      final options = languageOptions(supported: supported, nativeName: nativeName);
      expect(optionTagFor('ja-JP', options), 'ja');
    });
  });

  group('winSparkleLanguage', () {
    test('Chinese by script, whatever the region', () {
      expect(winSparkleLanguage(kSimplified), 'zh-CN');
      expect(winSparkleLanguage(kTraditional), 'zh-TW');
      expect(winSparkleLanguage(kHongKong), 'zh-TW');
      expect(winSparkleLanguage(_p('zh-Hans-HK')), 'zh-CN');
    });

    test('every other language is its own tag', () {
      expect(winSparkleLanguage(kEnglish), 'en');
      expect(winSparkleLanguage(const Locale('ja')), 'ja');
      expect(winSparkleLanguage(_p('pt-BR')), 'pt-BR');
    });
  });

  test('defaultNativeName reads languageNativeName from the language\'s own '
      'file', () {
    expect(defaultNativeName(kEnglish), 'English');
    expect(defaultNativeName(kSimplified), '简体中文');
    expect(defaultNativeName(kTraditional), '繁體中文');
    expect(defaultNativeName(kHongKong), '繁體中文');
  });
}
