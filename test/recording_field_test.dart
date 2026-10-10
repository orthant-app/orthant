import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/recording_field.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/core/key_chord.dart';

import 'support/carbon_terms.dart';

void main() {
  Future<List<KeyChord>> pump(
    WidgetTester tester, {
    KeyChord? pending,
    VoidCallback? onCancel,
  }) async {
    final combos = <KeyChord>[];
    await tester.pumpWidget(MaterialApp(
      theme: macTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: RecordingField(
            pending: pending,
            onCombo: combos.add,
            onCancel: onCancel ?? () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return combos;
  }

  testWidgets('says nothing is held until something is', (tester) async {
    await pump(tester);
    expect(find.text('Press keys…'), findsOneWidget);
  });

  testWidgets('draws the modifiers as they are held', (tester) async {
    // The field used to show the same "Press keys…" whatever the user did, so
    // holding ⌃⌥ produced no response at all — which reads as a field that is
    // not listening rather than one waiting for a key.
    await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('⌃'), findsOneWidget);
    expect(find.text('Press keys…'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.text('⌃ ⌥'), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.text('⌃'), findsOneWidget,
        reason: 'a released modifier has to disappear again');

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Press keys…'), findsOneWidget);
  });

  testWidgets('reports a combination once, not on every repeat',
      (tester) async {
    // Load-bearing beyond the obvious. The shortcuts pane confirms taking an
    // occupied combination by pressing it a **second time**, so a field that
    // re-reported while a chord was merely held down would take it the instant
    // auto-repeat began — a confirmation nobody could avoid giving.
    final combos = await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(combos, [carbon(123, kControlOption)]);
  });

  testWidgets('keeps what the key typed, from the same event', (tester) async {
    // AZERTY puts Q where US has A. The chord holds the position (what macOS
    // registers) and the meaning (what Windows registers) from one key event:
    // neither can be worked out from the other once that layout is gone.
    final combos = await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ,
        physicalKey: PhysicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ,
        physicalKey: PhysicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(combos, [
      KeyChord(
        physical: PhysicalKeyboardKey.keyA.usbHidUsage,
        logical: LogicalKeyboardKey.keyQ.keyId,
        modifiers: Modifiers.ctrl,
      ),
    ]);
  });

  testWidgets('on Windows a keypad digit is not a combination', (tester) async {
    // A keypad digit is a different virtual key in each NumLock state, so no
    // registration fires in both: recording one would make a shortcut that
    // cannot fire. A keypad operator is one key either way, and records.
    final combos = await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(combos.map((c) => c.logical),
        [LogicalKeyboardKey.numpadAdd.keyId]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a bare key is not a combination', (tester) async {
    final combos = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(combos, isEmpty, reason: 'a global hotkey needs a modifier');
  });

  testWidgets('Tab is not a combination either', (tester) async {
    // ⌃⇥ and ⌘⇥ switch tabs and apps everywhere; a global hotkey on either
    // would take it from every app without a word.
    final combos = await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(combos, isEmpty);
  });

  for (final entry in <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.semicolon: 41,
    LogicalKeyboardKey.bracketLeft: 33,
    LogicalKeyboardKey.quote: 39,
    LogicalKeyboardKey.backquote: 50,
    LogicalKeyboardKey.f1: 122,
    // F13-F20 are mapped too, but flutter_test's key simulator stops at F12.
    LogicalKeyboardKey.f12: 111,
    LogicalKeyboardKey.home: 115,
    LogicalKeyboardKey.end: 119,
    LogicalKeyboardKey.pageUp: 116,
    LogicalKeyboardKey.pageDown: 121,
    LogicalKeyboardKey.delete: 117,
    LogicalKeyboardKey.backspace: 51,
    LogicalKeyboardKey.numpadEnter: 76,
    LogicalKeyboardKey.numpadDecimal: 65,
    LogicalKeyboardKey.numpad1: 83,
  }.entries) {
    testWidgets('records modified ${entry.key.keyLabel}', (tester) async {
      final combos = await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(entry.key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(combos, [carbon(entry.value, kControlKey)]);
      expect(formatCombo(carbon(entry.value, kControlKey)),
          isNot(contains('key:')),
          reason: 'every accepted key needs a usable fallback label');
    });
  }

  testWidgets('esc cancels rather than being recorded', (tester) async {
    var cancels = 0;
    final combos = await pump(tester, onCancel: () => cancels++);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(combos, isEmpty);
  });

  testWidgets('a pending combination replaces the live preview',
      (tester) async {
    // What the shortcuts pane shows on the row its footer is asking about, so
    // the question has a visible subject.
    await pump(tester, pending: carbon(123, kControlOption));
    expect(find.text('⌃ ⌥ ←'), findsOneWidget);

    // And it holds, rather than being overwritten by whatever is held now.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('⌃ ⌥ ←'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('a pending combination is drawn in the warning colour',
      (tester) async {
    Color fill() => (tester
            .widget<Container>(find.descendant(
                of: find.byType(RecordingField), matching: find.byType(Container)))
            .decoration! as BoxDecoration)
        .color!;

    await pump(tester);
    final listening = fill();

    await pump(tester, pending: carbon(123, kControlOption));
    expect(fill(), isNot(listening),
        reason: 'the row carrying the question looks like every other row');
    expect(fill(), macTheme(Brightness.light).extension<MacTokens>()!.warning);
  });
}
