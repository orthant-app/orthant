
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/settings/key_capture.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/recording_field.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/core/key_chord.dart';

import 'support/carbon_terms.dart';
import 'support/locales.dart';
import 'support/localized_host.dart';
import 'support/no_english.dart';

void main() {
  Future<List<KeyChord>> pump(
    WidgetTester tester, {
    KeyChord? pending,
    VoidCallback? onCancel,
    List<String>? refusals,
  }) async {
    final combos = <KeyChord>[];
    await tester.pumpWidget(MaterialApp(
      theme: orthantTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: RecordingField(
            pending: pending,
            onCombo: combos.add,
            onCancel: onCancel ?? () {},
            onRefused: refusals?.add,
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

  testWidgets('and says so in the language of the app', (tester) async {
    for (final (locale, prompt) in [
      (kSimplified, '按下按键…'),
      (kTraditional, '按下按鍵…'),
      (kHongKong, '按下按鍵…'),
    ]) {
      await tester.pumpWidget(localizedApp(
        locale,
        Center(
          child: RecordingField(onCombo: (_) {}, onCancel: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsOneWidget);
      expectNoEnglish(tester);
    }
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

  testWidgets('on Windows a keypad digit held with a modifier says why',
      (tester) async {
    final refusals = <String>[];
    final combos = await pump(tester, refusals: refusals);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadDecimal);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(refusals, [keypadRefusal, keypadRefusal],
        reason: 'the digit and the decimal, not the operator, which records');
    expect(combos, hasLength(1));
    expect(find.byType(RecordingField), findsOneWidget,
        reason: 'still listening: a refusal is not a cancel');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a key Windows has no virtual key for says so, in other words',
      (tester) async {
    // The ISO key under its own name: no virtual key, and not the keypad.
    // Windows' engine names a key by what its virtual key types, so this name
    // may never arrive there (the test simulator has no Windows key code for
    // it): the sentence is the fallback for any key that does, and refusalFor
    // is asked directly.
    KeyDownEvent down(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
        KeyDownEvent(
            physicalKey: physical, logicalKey: logical, timeStamp: Duration.zero);
    final iso = down(
        PhysicalKeyboardKey.intlBackslash, LogicalKeyboardKey.intlBackslash);
    expect(refusalFor(iso), isNull, reason: 'no modifier held');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(refusalFor(iso), unregistrableRefusal);
    expect(
        refusalFor(
            down(PhysicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad1)),
        keypadRefusal);
    expect(refusalFor(down(PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA)),
        isNull, reason: 'a key Windows can register is not refused');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('the refusal is spoken, for someone who cannot see the footer',
      (tester) async {
    final spoken = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility, (message) async {
      final m = message as Map;
      if (m['type'] == 'announce') {
        spoken.add((m['data'] as Map)['message'] as String);
      }
      return null;
    });
    addTearDown(() => messenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility, null));
    await pump(tester, refusals: []);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(spoken, [keypadRefusal]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a key pressed with no modifier is never refused aloud',
      (tester) async {
    // The footer already says a combination needs a modifier.
    final refusals = <String>[];
    await pump(tester, refusals: refusals);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(refusals, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('on macOS a keypad digit records, as it always has',
      (tester) async {
    final refusals = <String>[];
    final combos = await pump(tester, refusals: refusals);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(refusals, isEmpty);
    expect(combos.single.logical, LogicalKeyboardKey.numpad1.keyId);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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
    expect(fill(),
        orthantTheme(Brightness.light).extension<PlatformTokens>()!.warning);
  });

  group('a refused key, in the language of the app', () {
    // The two sentences a Windows user hears when a key cannot be part of a
    // shortcut, read by the recorder in the Shortcuts list and in the region
    // picker alike. They are messages like any other: English is exactly what
    // 1.1.x said, and Chinese is a whole sentence of its own.
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    KeyDownEvent iso() => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        logicalKey: LogicalKeyboardKey.intlBackslash,
        timeStamp: Duration.zero);
    KeyDownEvent keypad() => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.numpad1,
        logicalKey: LogicalKeyboardKey.numpad1,
        timeStamp: Duration.zero);

    test('English is word for word what it was', () {
      expect(keypadRefusal,
          "Windows can't use the keypad's digits, decimal point or = in a "
          'shortcut.');
      expect(unregistrableRefusal, "Windows can't use that key in a shortcut.");
    });

    testWidgets('refusalFor takes the language it is asked for',
        (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final zh = lookupAppLocalizations(kSimplified);
      final hant = lookupAppLocalizations(kTraditional);
      expect(refusalFor(keypad(), zh),
          'Windows 无法在快捷键中使用小键盘的数字、小数点或 =。');
      expect(refusalFor(iso(), zh), 'Windows 无法在快捷键中使用该按键。');
      expect(refusalFor(keypad(), hant),
          'Windows 無法在快速鍵中使用數字鍵盤的數字、小數點或 =。');
      expect(refusalFor(iso(), hant), 'Windows 無法在快速鍵中使用該按鍵。');
      expect(refusalFor(keypad()), keypadRefusal,
          reason: 'with no language given it is the app\'s own, English here');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }, variant: windows);

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      testWidgets('the recorder says it in ${locale.toLanguageTag()}, and '
          'speaks it', (tester) async {
        final spoken = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, (message) async {
          final m = message as Map;
          if (m['type'] == 'announce') {
            spoken.add((m['data'] as Map)['message'] as String);
          }
          return null;
        });
        addTearDown(() => messenger.setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, null));

        final refusals = <String>[];
        // No `setAppStrings`: the recorder reads the language from the tree,
        // as every other widget does, not from the global the tray uses.
        await tester.pumpWidget(localizedApp(
          locale,
          Center(
            child: RecordingField(
              onCombo: (_) {},
              onCancel: () {},
              onRefused: refusals.add,
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
        // The simulator has no Windows key code for the ISO key, so it is sent
        // as another platform's key press; the refusal depends only on the
        // key's two identities and on the platform the app is running as.
        await tester.sendKeyEvent(LogicalKeyboardKey.intlBackslash,
            platform: 'macos', physicalKey: PhysicalKeyboardKey.intlBackslash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        final zh = locale == kSimplified;
        final expected = [
          zh
              ? 'Windows 无法在快捷键中使用小键盘的数字、小数点或 =。'
              : 'Windows 無法在快速鍵中使用數字鍵盤的數字、小數點或 =。',
          zh
              ? 'Windows 无法在快捷键中使用该按键。'
              : 'Windows 無法在快速鍵中使用該按鍵。',
        ];
        expect(refusals, expected);
        expect(spoken, expected);
        expectNoEnglishIn(refusals);
      }, variant: windows);
    }
  });
}
