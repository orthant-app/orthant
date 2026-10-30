import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/app_localizations.dart';

/// Dart cannot enumerate a class's getters, so a loop that asks every locale
/// for every message is not writable. What makes the proof possible anyway is
/// that gen-l10n overrides, in each locale's class, exactly the messages that
/// locale's file holds. `arb_test.dart` says every file holds every message;
/// the two probe messages below say each locale reaches its own class. Their
/// fixture translations are deliberately distinct per locale and ship unused.
void main() {
  const zhHant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  const zhHantHK = Locale.fromSubtags(
      languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK');

  test('each supported locale answers from its own file', () {
    String probe(Locale l) => lookupAppLocalizations(l).l10nProbeLocale;
    expect(probe(const Locale('en')), 'en');
    expect(probe(const Locale('zh')), 'zh');
    expect(probe(zhHant), 'zh_Hant');
    expect(probe(zhHantHK), 'zh_Hant_HK');
  });

  test('Hong Kong inherits Traditional, not Simplified, where it has no '
      'override', () {
    expect(lookupAppLocalizations(zhHantHK).l10nProbeScript, 'Hant');
  });

  test('supportedLocales is exactly the four', () {
    expect(AppLocalizations.supportedLocales.toSet(),
        <Locale>{const Locale('en'), const Locale('zh'), zhHant, zhHantHK});
    expect(AppLocalizations.supportedLocales, hasLength(4));
  });
}
