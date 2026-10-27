import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/merge_hk.dart';

Map<String, dynamic> _readJson(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

/// The messages of an ARB: every key that is neither `@@locale` nor an `@key`
/// metadata entry.
Set<String> _messages(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final template = _readJson('app_en.arb');
  const others = <String>[
    'app_zh.arb',
    'app_zh_Hant.arb',
    'app_zh_Hant_HK.arb',
  ];

  test('every ARB has every message of the template, Hong Kong included', () {
    final want = _messages(template);
    expect(want, isNotEmpty);
    for (final name in others) {
      final have = _messages(_readJson(name));
      expect(want.difference(have), isEmpty,
          reason: '$name lacks messages the template has');
      expect(have.difference(want), isEmpty,
          reason: '$name has messages the template does not');
    }
  });

  test('every template message has an @description', () {
    for (final key in _messages(template)) {
      final meta = template['@$key'];
      expect(meta, isA<Map<String, dynamic>>(),
          reason: '$key has no @$key entry');
      final description = (meta as Map<String, dynamic>)['description'];
      expect(description, isA<String>(), reason: '$key has no description');
      expect((description as String).trim(), isNotEmpty,
          reason: '$key has an empty description');
    }
  });

  test('app_zh_Hant_HK.arb is exactly zh_Hant merged with the overrides', () {
    expect(
        _readJson('app_zh_Hant_HK.arb'),
        mergeHongKong(
            _readJson('app_zh_Hant.arb'), _readJson('zh_Hant_HK.overrides.json')));
  });

  test('every override key exists in zh_Hant', () {
    final zhHant = _messages(_readJson('app_zh_Hant.arb'));
    final overrides = _readJson('zh_Hant_HK.overrides.json');
    expect(zhHant.containsAll(overrides.keys), isTrue,
        reason: 'overrides name keys zh_Hant lacks: '
            '${overrides.keys.toSet().difference(zhHant)}');
  });
}
