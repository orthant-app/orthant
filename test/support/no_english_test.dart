import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'no_english.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Chinese text passes', (tester) async {
    await tester.pumpWidget(_host(const Text('打开网格')));
    expectNoEnglish(tester);
  });

  testWidgets('key legends and the app name pass', (tester) async {
    await tester.pumpWidget(_host(const Text('Ctrl + Shift + Orthant 打开')));
    expectNoEnglish(tester);
  });

  testWidgets('English mixed into Chinese fails, naming the word',
      (tester) async {
    await tester.pumpWidget(_host(const Text('Open 网格')));
    expect(
      () => expectNoEnglish(tester),
      throwsA(isA<TestFailure>().having(
          (e) => e.message, 'message', allOf(contains('Open'),
              isNot(contains('网格'))))),
    );
  });

  // Both of the next two run with the harness's own semantics switched off,
  // so they show the helper turning semantics on for itself.
  testWidgets('English only in the semantics tree fails', (tester) async {
    await tester.pumpWidget(_host(
        Semantics(label: 'Move left', child: const Text('向左'))));
    expect(
      () => expectNoEnglish(tester),
      throwsA(isA<TestFailure>().having((e) => e.message, 'message',
          allOf(contains('Move'), contains('left')))),
    );
  }, semanticsEnabled: false);

  testWidgets('English in a hint, value or tooltip fails', (tester) async {
    await tester.pumpWidget(_host(Column(children: [
      Semantics(hint: 'Double tap', child: const Text('一')),
      Semantics(value: 'Enabled', child: const Text('二')),
      const Tooltip(message: 'Close window', child: Text('三')),
    ])));
    expect(
      () => expectNoEnglish(tester),
      throwsA(isA<TestFailure>().having((e) => e.message, 'message',
          allOf(contains('Double'), contains('Enabled'), contains('Close')))),
    );
  });

  testWidgets('English text that semantics leave out is still found',
      (tester) async {
    await tester.pumpWidget(_host(const ExcludeSemantics(child: Text('Open'))));
    expect(
      () => expectNoEnglish(tester),
      throwsA(isA<TestFailure>()
          .having((e) => e.message, 'message', contains('Open'))),
    );
    await tester.pumpWidget(_host(const ExcludeSemantics(
        child: Text.rich(TextSpan(children: [TextSpan(text: 'Close')])))));
    expect(
      () => expectNoEnglish(tester),
      throwsA(isA<TestFailure>()
          .having((e) => e.message, 'message', contains('Close'))),
    );
  });

  testWidgets('English typed into a text field fails', (tester) async {
    await tester.pumpWidget(_host(ExcludeSemantics(
        child: TextField(controller: TextEditingController(text: 'Left')))));
    expect(
      () => expectNoEnglish(tester),
      throwsA(isA<TestFailure>()
          .having((e) => e.message, 'message', contains('Left'))),
    );
  });

  testWidgets('allow lets a named word through', (tester) async {
    await tester.pumpWidget(_host(const Text('Open 网格')));
    expectNoEnglish(tester, allow: {'Open'});
  });

  testWidgets('semantics are switched back off afterwards', (tester) async {
    await tester.pumpWidget(_host(const Text('打开网格')));
    expect(tester.binding.semanticsEnabled, isFalse);
    expectNoEnglish(tester);
    expect(tester.binding.semanticsEnabled, isFalse);
    // Even when it fails.
    await tester.pumpWidget(_host(const Text('Open')));
    expect(() => expectNoEnglish(tester), throwsA(isA<TestFailure>()));
    expect(tester.binding.semanticsEnabled, isFalse);
  }, semanticsEnabled: false);

  test('expectNoEnglishIn checks plain strings and lists every word', () {
    expectNoEnglishIn(['已打开网格', 'Ctrl+Enter']);
    expect(
      () => expectNoEnglishIn(['Grid opened', '网格已打开', 'Moved left']),
      throwsA(isA<TestFailure>().having((e) => e.message, 'message',
          allOf(contains('Grid'), contains('opened'), contains('Moved'),
              contains('left')))),
    );
    expectNoEnglishIn(['Grid 打开'], allow: {'Grid'});
  });
}
