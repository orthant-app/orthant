import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/l10n/strings.dart';

void main() {
  const zhHant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');

  tearDown(() => setAppStrings(const Locale('en')));

  test('appStrings starts English', () {
    expect(appStrings.l10nProbeLocale, 'en');
  });

  test('setAppStrings switches the strings code without a context uses', () {
    setAppStrings(zhHant);
    expect(appStrings.l10nProbeLocale, 'zh_Hant');
    setAppStrings(const Locale('zh'));
    expect(appStrings.l10nProbeLocale, 'zh');
  });

  testWidgets('context.l10n is the Localizations value when one is in scope',
      (tester) async {
    late AppLocalizations seen;
    await tester.pumpWidget(Localizations(
      locale: zhHant,
      delegates: AppLocalizations.localizationsDelegates,
      child: Builder(builder: (context) {
        seen = context.l10n;
        return const SizedBox();
      }),
    ));
    expect(seen.l10nProbeLocale, 'zh_Hant');
  });

  testWidgets('context.l10n falls back to appStrings with no delegates',
      (tester) async {
    late AppLocalizations seen;
    await tester.pumpWidget(Builder(builder: (context) {
      seen = context.l10n;
      return const SizedBox();
    }));
    expect(seen.l10nProbeLocale, 'en');

    setAppStrings(zhHant);
    await tester.pumpWidget(Builder(builder: (context) {
      seen = context.l10n;
      return const SizedBox();
    }));
    expect(seen.l10nProbeLocale, 'zh_Hant');
  });

  testWidgets('context.l10n falls back inside an app whose delegates lack ours',
      (tester) async {
    // The shape of most existing test hosts: a MaterialApp, so there is a
    // Localizations ancestor, just not one that carries AppLocalizations.
    late AppLocalizations seen;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      seen = context.l10n;
      return const SizedBox();
    })));
    expect(seen.l10nProbeLocale, 'en');
  });
}
