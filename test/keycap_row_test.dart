import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/keycap.dart';

import 'support/locales.dart';
import 'support/localized_host.dart';

void main() {
  testWidgets('a row with no chord says "not set" in the language it is shown '
      'in, with no label passed', (tester) async {
    for (final (locale, words) in [
      (kEnglish, 'Not set'),
      (kSimplified, '未设置'),
    ]) {
      await tester.pumpWidget(
          localizedApp(locale, const KeycapRow(chord: null)));
      expect(find.text(words), findsOneWidget, reason: locale.toLanguageTag());
    }
    expect(find.text('Not set'), findsNothing,
        reason: 'the last locale shown was Chinese');
  });

  testWidgets('a label passed in wins', (tester) async {
    await tester.pumpWidget(localizedApp(
        kSimplified, const KeycapRow(chord: null, unsetLabel: '没有快捷键')));
    expect(find.text('没有快捷键'), findsOneWidget);
    expect(find.text('未设置'), findsNothing);
  });
}
