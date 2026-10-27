import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/windows_system_languages.dart';

// The real call: only Windows has kernel32's GetThreadPreferredUILanguages, so
// this is skipped elsewhere and runs on the Windows CI job and on the VM
// (`flutter test test/windows_system_languages_windows_test.dart`). The pure
// parsing is in windows_system_languages_test.dart.

void main() {
  final skip = Platform.isWindows ? null : 'asks Windows itself';

  test('the OS answers with at least one language, and the first is a language',
      () {
    final names = readPreferredLanguageNames();
    final locales = readSystemLocales();
    debugPrint('system languages: $names -> $locales');
    expect(names, isNotEmpty, reason: 'GetThreadPreferredUILanguages said nothing');
    expect(locales, isNotEmpty);
    expect(locales.first.languageCode, matches(RegExp(r'^[a-zA-Z]{2,3}$')),
        reason: 'the first name was ${names.first}');
  }, skip: skip);

  test('every name the OS gives is a locale, in the OS\'s order', () {
    final names = readPreferredLanguageNames();
    final locales = readSystemLocales();
    expect(locales, hasLength(names.length));
    for (var i = 0; i < names.length; i++) {
      expect(locales[i].languageCode, names[i].split('-').first,
          reason: names.join(', '));
    }
  }, skip: skip);

  test('it is asked afresh each time, and does not need the engine to have '
      'sent anything', () {
    expect(readSystemLocales(), readSystemLocales());
  }, skip: skip);
}
