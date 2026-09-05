import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The site already guards its built output against the em dash
/// (`site/src/lib/dist-copy.test.ts`); this is the same rule for the app.
/// Every string the app shows lives in `lib/`, so scanning the code with
/// comments removed is a sufficient oracle: a `//` comment may say what it
/// likes, a string literal may not carry U+2014.
void main() {
  test('the app shows no em dash', () {
    final guilty = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThan(20),
        reason: 'the walk found nothing to check');
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].replaceFirst(RegExp(r'//.*$'), '');
        if (code.contains('—')) guilty.add('${file.path}:${i + 1}');
      }
    }
    expect(guilty, isEmpty, reason: 'em dash (U+2014) in a string: $guilty');
  });
}
