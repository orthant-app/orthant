import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Latin words a Chinese screen is still allowed to show: the app's own name,
/// the two operating systems, and the key legends, which stay English in every
/// language (the keys are printed that way), plus the units.
const Set<String> kAllowedLatin = {
  'Orthant',
  'macOS',
  'Windows',
  'Win',
  'Ctrl',
  'Alt',
  'Shift',
  'Enter',
  'Esc',
  'esc',
  'Return',
  'Space',
  'Tab',
  'Backspace',
  'Home',
  'End',
  'PgUp',
  'PgDn',
  'Del',
  'Num',
  'Lock',
  'pt',
  'px',
};

/// A "word" for this check: two or more ASCII letters in a row. A single
/// letter is a key cap (`U`, `I`, `J`, `K`) or a variable, never a sentence.
final RegExp _word = RegExp(r'[A-Za-z]{2,}');

/// Fails if anything the widget tree shows or announces holds an English word.
///
/// Reads every [Text], [RichText] and [EditableText], and, with semantics
/// switched on for the duration, every semantics node's label, value, hint and
/// tooltip, because a control can be fully Chinese on screen and still be read
/// out in English. Words in [kAllowedLatin] or [allow] pass. The failure lists
/// each offending word.
void expectNoEnglish(WidgetTester tester, {Set<String> allow = const {}}) {
  final handle = tester.ensureSemantics();
  try {
    // A tree that was built while semantics were off has no nodes until the
    // next frame; build them now rather than make this helper async.
    tester.binding.rootPipelineOwner.flushSemantics();
    final strings = <String>[];

    for (final element in find.byType(Text).evaluate()) {
      final text = element.widget as Text;
      strings.add(text.data ?? text.textSpan?.toPlainText() ?? '');
    }
    for (final element in find.byType(RichText).evaluate()) {
      strings.add((element.widget as RichText).text.toPlainText());
    }
    for (final element in find.byType(EditableText).evaluate()) {
      strings.add((element.widget as EditableText).controller.text);
    }
    for (final node
        in find.semantics.byPredicate((_) => true).evaluate()) {
      strings
        ..add(node.label)
        ..add(node.value)
        ..add(node.hint)
        ..add(node.tooltip);
    }

    expectNoEnglishIn(strings, allow: allow);
  } finally {
    handle.dispose();
  }
}

/// [expectNoEnglish] for strings that never reach the widget tree, such as an
/// announcement a screen reader is sent.
void expectNoEnglishIn(Iterable<String> strings,
    {Set<String> allow = const {}}) {
  final permitted = {...kAllowedLatin, ...allow};
  final offenders = <String>{};
  for (final s in strings) {
    for (final match in _word.allMatches(s)) {
      final word = match.group(0)!;
      if (!permitted.contains(word)) offenders.add(word);
    }
  }
  if (offenders.isNotEmpty) {
    fail('English left on a Chinese screen: ${offenders.toList()..sort()}');
  }
}
