import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/ready_screen.dart';
import 'package:orthant/settings/key_capture.dart';
import 'package:orthant/settings/keycap.dart';
import 'package:orthant/settings/general_pane.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/recording_field.dart';
import 'package:orthant/settings/region_picker_sheet.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/shortcuts_screen.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// The settings window in each platform's words: its keycaps, the footer that
/// lists the modifiers a combination needs, the hint that teaches the grid's
/// save chord, the warning on a chord the OS refused, the recorder, the region
/// picker's hint and the ready screen's caption. macOS's are pinned byte for
/// byte, because they are what 1.0.x shows.
void main() {
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  const topLeft = BuiltIn(ShortcutCommand.topLeft);
  const showGrid = BuiltIn(ShortcutCommand.showGrid);

  /// The window's width unless a test says otherwise; tall enough that every
  /// row and the pinned footer are on screen.
  Future<void> pumpHost(WidgetTester tester, Widget child,
      {double width = 560}) async {
    await tester.binding.setSurfaceSize(Size(width + 40, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: orthantTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(width: width, height: 1050, child: child),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Widget shortcuts() => ShortcutsScreen(
        bindings: runningDefaults(),
        unavailable: {topLeft},
        onRebound: (_) {},
        onRegionSaved: (_) {},
        onRegionDeleted: (_) {},
      );

  String tooltipSaying(WidgetTester tester, String words) => tester
      .widget<Tooltip>(find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains(words)))
      .message!;

  Future<void> listen(WidgetTester tester) async {
    await tester.tap(find.text('Left half'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordingField), findsOneWidget);
  }

  Future<String> recorderHearing(
      WidgetTester tester, List<LogicalKeyboardKey> held) async {
    for (final key in held) {
      await tester.sendKeyDownEvent(key);
    }
    await tester.pump();
    final text = tester
        .widget<Text>(find.descendant(
            of: find.byType(RecordingField), matching: find.byType(Text)))
        .data!;
    for (final key in held.reversed) {
      await tester.sendKeyUpEvent(key);
    }
    await tester.pump();
    return text;
  }

  Widget general() => GeneralPane(
        settings: const Settings(),
        onSettingsChanged: (_) {},
        permissionGranted: true,
        loginStatus: LoginItemStatus.disabled,
        bindings: runningDefaults(),
        summonUnavailable: true,
      );

  Widget picker({bool withChord = false}) => RegionPickerSheet(
        initialChord: withChord
            ? runningDefaults()
                .firstWhere(
                    (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
                .chord
            : null,
        gridCols: 6,
        gridRows: 6,
        onSubmit: (_) {},
        onCancel: () {},
        isNew: true,
      );

  Widget ready({bool refused = true}) => ReadyScreen(
        bindings: runningDefaults(),
        unavailable: {if (refused) showGrid},
        onDone: () {},
        onOpenShortcuts: () {},
      );

  group('macOS says what 1.0.x says', () {
    testWidgets('the shortcuts pane, its footer and its hints',
        (tester) async {
      await pumpHost(tester, shortcuts());
      expect(find.text('⌃'), findsNWidgets(11));
      expect(find.text('⌥'), findsNWidgets(11));
      expect(find.text('↩'), findsOneWidget);
      expect(
          find.text('Click a shortcut to change it. '
              'Combinations need ⌃, ⌥, ⇧ or ⌘.'),
          findsOneWidget);
      expect(
          find.text("Bind a shape the built-ins don't cover. Draw it here, or "
              'select it in the grid and press ⌘S.'),
          findsOneWidget);
      expect(
          tooltipSaying(tester, 'another app'),
          'macOS or another app already uses this combination, so it never '
          'reaches Orthant.\nClick the shortcut to pick a different one.');
      await listen(tester);
      expect(find.text('Listening… press a combination, or esc to cancel.'),
          findsOneWidget);
      expect(
          await recorderHearing(tester,
              [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft]),
          '⌃ ⇧');
    }, variant: macOS);

    testWidgets('the General pane, the picker and the ready screen',
        (tester) async {
      await pumpHost(tester, general());
      expect(
          tooltipSaying(tester, 'another app'),
          'macOS or another app already uses this combination, so it never '
          'reaches Orthant.');
      await pumpHost(tester, picker());
      expect(find.text('Drag to draw · arrows to move, ⇧ to extend'),
          findsOneWidget);
      await pumpHost(tester, ready());
      expect(
          find.text('Opens the grid. Drag across it to pick any block: '
              'thirds, two-thirds, anything. Or use the arrow keys, ⇧ to '
              'extend, ↩ to place.'),
          findsOneWidget);
      expect(
          tooltipSaying(tester, 'another app'),
          'macOS or another app already uses this combination, so it never '
          'reaches Orthant.\nPick a different one below.');
    }, variant: macOS);
  });

  group('Windows speaks Windows', () {
    testWidgets('the shortcuts pane, its footer and its hints',
        (tester) async {
      await pumpHost(tester, shortcuts());
      for (final word in ['Win', 'Ctrl', 'Shift']) {
        expect(find.text(word), findsNWidgets(11), reason: word);
      }
      expect(find.text('Enter'), findsOneWidget, reason: 'Maximize');
      for (final glyph in ['⌃', '⌥', '⇧', '⌘', '↩']) {
        expect(find.textContaining(glyph), findsNothing, reason: glyph);
      }
      expect(
          find.text('Click a shortcut to change it. '
              'Combinations need Win, Ctrl, Alt or Shift.'),
          findsOneWidget);
      expect(
          find.text("Bind a shape the built-ins don't cover. Draw it here, or "
              'select it in the grid and press Ctrl+S.'),
          findsOneWidget);
      expect(
          tooltipSaying(tester, 'another app'),
          'Windows or another app already uses this combination, so it never '
          'reaches Orthant.\nClick the shortcut to pick a different one.');
      await listen(tester);
      expect(find.text('Listening… press a combination, or Esc to cancel.'),
          findsOneWidget);
      expect(
          await recorderHearing(tester,
              [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft]),
          'Ctrl+Shift');
      expect(
          await recorderHearing(tester, [
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.shiftLeft,
          ]),
          'Win+Ctrl+Shift');
    }, variant: windows);

    testWidgets('the picker draws and names a chord in Windows\' words',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHost(tester, picker(withChord: true));
      for (final cap in ['Win', 'Ctrl', 'Shift', '←']) {
        expect(find.text(cap), findsOneWidget, reason: cap);
      }
      expect(
          find.bySemanticsLabel(
              'Record shortcut, currently Win+Ctrl+Shift+←'),
          findsOneWidget);
      semantics.dispose();
    }, variant: windows);

    Future<void> chord(WidgetTester tester, List<LogicalKeyboardKey> held,
        LogicalKeyboardKey key) async {
      for (final k in held) {
        await tester.sendKeyDownEvent(k);
      }
      await tester.sendKeyEvent(key);
      for (final k in held.reversed) {
        await tester.sendKeyUpEvent(k);
      }
      await tester.pump();
    }

    const ctrl = [LogicalKeyboardKey.controlLeft];
    const winCtrlShift = [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ];

    /// Shown under the listening row, beside its recorder: not in the footer,
    /// where it would compete with a question or an Undo.
    void expectBesideRecorder(WidgetTester tester) {
      final field = tester.getRect(find.byType(RecordingField));
      final why = tester.getRect(find.text(keypadRefusal));
      expect(why.top - field.bottom, inInclusiveRange(0, 24),
          reason: 'directly under the field that refused it');
      // Where the sentence's own glyphs end: its box spans the row either way.
      final text =
          tester.renderObject<RenderParagraph>(find.text(keypadRefusal));
      final glyphs = text.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: keypadRefusal.length));
      final end = glyphs.map((b) => b.right).reduce(math.max);
      expect(text.localToGlobal(Offset(end, 0)).dx, closeTo(field.right, 16),
          reason: 'under the recorder, not the row\'s name');
    }

    testWidgets('the shortcuts pane says why a keypad digit is refused',
        (tester) async {
      await pumpHost(tester, shortcuts());
      await listen(tester);
      await chord(tester, ctrl, LogicalKeyboardKey.numpad1);
      expect(find.text(keypadRefusal), findsOneWidget);
      expectBesideRecorder(tester);
      expect(find.byType(RecordingField), findsOneWidget,
          reason: 'still listening for a combination it can use');
    }, variant: windows);

    testWidgets('a refusal stays beside the recorder, and the footer keeps '
        'its question and its Undo', (tester) async {
      // With a way back, so that a taken chord offers an Undo.
      await pumpHost(
          tester,
          ShortcutsScreen(
            bindings: runningDefaults(),
            onRebound: (_) {},
            onRestoreBindings: (_) {},
          ));
      await listen(tester);
      // Right half's chord on Left half: the footer asks.
      await chord(tester, winCtrlShift, LogicalKeyboardKey.arrowRight);
      expect(find.text('Use it here'), findsOneWidget);
      await chord(tester, ctrl, LogicalKeyboardKey.numpad1);
      expect(find.text('Use it here'), findsOneWidget,
          reason: 'the question, and its button, are still up');
      expect(find.text(keypadRefusal), findsOneWidget,
          reason: 'and the refusal is still seen, beside the recorder');
      expectBesideRecorder(tester);
      // Taken: the footer offers the way back, for ten seconds.
      await chord(tester, winCtrlShift, LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);
      await listen(tester);
      await chord(tester, ctrl, LogicalKeyboardKey.numpad1);
      expect(find.text('Undo'), findsOneWidget,
          reason: 'a multi-row change keeps its way back');
      expect(find.text(keypadRefusal), findsOneWidget);
      expectBesideRecorder(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 11));
    }, variant: windows);

    testWidgets('the refusal goes at the next usable chord, and with the '
        'recording', (tester) async {
      await pumpHost(tester, shortcuts());
      await listen(tester);
      await chord(tester, ctrl, LogicalKeyboardKey.numpad1);
      expect(find.text(keypadRefusal), findsOneWidget);
      // A chord it can use, though taken: the row goes on listening, and the
      // refusal no longer describes the last key pressed.
      await chord(tester, winCtrlShift, LogicalKeyboardKey.arrowRight);
      expect(find.text('Use it here'), findsOneWidget);
      expect(find.text(keypadRefusal), findsNothing);
      await chord(tester, ctrl, LogicalKeyboardKey.numpad1);
      expect(find.text(keypadRefusal), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(RecordingField), findsNothing);
      expect(find.text(keypadRefusal), findsNothing);
      // Nor does it follow the recording to another row.
      await listen(tester);
      await chord(tester, ctrl, LogicalKeyboardKey.numpad1);
      await tester.tap(find.text('Right half'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingField), findsOneWidget);
      expect(find.text(keypadRefusal), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await listen(tester);
      expect(find.text(keypadRefusal), findsNothing,
          reason: 'a new recording starts with nothing refused');
    }, variant: windows);

    testWidgets('a refusal leaves the recorder showing what is still held',
        (tester) async {
      await pumpHost(tester, shortcuts());
      await listen(tester);
      String hearing() => tester
          .widget<Text>(find.descendant(
              of: find.byType(RecordingField), matching: find.byType(Text)))
          .data!;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final held = hearing();
      // The keypad digit stays down too: the line appearing must not rebuild
      // the field, which would forget the Ctrl it is showing.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.numpad1);
      await tester.pump();
      expect(find.text(keypadRefusal), findsOneWidget);
      expect(hearing(), held, reason: 'Ctrl is still down');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.numpad1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }, variant: windows);

    testWidgets('a screen reader can find the refusal again', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHost(tester, shortcuts());
      await listen(tester);
      await chord(tester, ctrl, LogicalKeyboardKey.numpad1);
      // Its own node, not folded into the row's label, which is replaced.
      expect(find.bySemanticsLabel(keypadRefusal), findsOneWidget);
      semantics.dispose();
    }, variant: windows);

    testWidgets('the picker says why a keypad digit is refused',
        (tester) async {
      await pumpHost(tester, picker());
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingField), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.text(keypadRefusal), findsOneWidget);
      expect(find.byType(RecordingField), findsOneWidget);
      // A chord it can use ends the recording, and the refusal with it.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(RecordingField), findsNothing);
      expect(find.text(keypadRefusal), findsNothing);
    }, variant: windows);

    testWidgets('a row tells a screen reader its chord in Windows\' words',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHost(tester, shortcuts());
      expect(find.bySemanticsLabel('Left half, Win+Ctrl+Shift+←'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Maximize, Win+Ctrl+Shift+Enter'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel('Top-left quarter, Win+Ctrl+Shift+U, '
              'unavailable'),
          findsOneWidget);
      semantics.dispose();
    }, variant: windows);

    testWidgets('the General pane, the picker and the ready screen',
        (tester) async {
      await pumpHost(tester, general());
      expect(
          tooltipSaying(tester, 'another app'),
          'Windows or another app already uses this combination, so it never '
          'reaches Orthant.');
      expect(find.text('Win'), findsOneWidget, reason: 'the summon\'s keycaps');
      await pumpHost(tester, picker());
      expect(find.text('Drag to draw · arrows to move, Shift to extend'),
          findsOneWidget);
      // Wider than the window: flutter_test draws every character as a square
      // a font size wide, about half as wide again as Segoe UI, and Win, Ctrl
      // and Shift are words. The window's own width is the next test's.
      await pumpHost(tester, ready(), width: 760);
      expect(
          find.text('Opens the grid. Drag across it to pick any block: '
              'thirds, two-thirds, anything. Or use the arrow keys, Shift to '
              'extend, Enter to place.'),
          findsOneWidget);
      expect(
          tooltipSaying(tester, 'another app'),
          'Windows or another app already uses this combination, so it never '
          'reaches Orthant.\nPick a different one below.');
    }, variant: windows);
  });

  // The ready screen's second card shows two chords. On macOS they stay on one
  // line: side by side at full size while they fit (the default chords do),
  // and scaled down together when they are wider than the card (two rebound
  // to four modifiers each). Windows names its keys (Win, Ctrl and Shift are
  // words, not glyphs), so its default chords are wider than a card: the
  // second goes beneath the first, both at full size. The widths are not
  // special: in flutter_test's font (a square a font size wide per character)
  // Windows' two chords are wider than a card at each of them, as they would
  // be at the window's own 560.

  /// The second card, which holds the two chords.
  Rect cardAroundChords(WidgetTester tester) => tester.getRect(find
      .ancestor(
          of: find.byType(KeycapRow).at(1),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).border != null))
      .first);

  /// Both chords of the second card on one line, inside the card, centred in
  /// it and in the proportions they were laid out in, whatever the scale
  /// (which is returned: 1 when they fit). A rectangle is as drawn, scaling
  /// included; [WidgetTester.getSize] is the size laid out, which scaling
  /// leaves alone.
  double expectChordsOnOneLine(WidgetTester tester) {
    final keycaps = find.byType(KeycapRow);
    expect(keycaps, findsNWidgets(3),
        reason: 'the summon, then left and right');
    final card = cardAroundChords(tester);
    final left = tester.getRect(keycaps.at(1));
    final right = tester.getRect(keycaps.at(2));
    expect(left.center.dy, closeTo(right.center.dy, 0.01), reason: 'one line');
    expect(left.right, lessThan(right.left), reason: 'side by side');
    final inner = Rect.fromLTRB(
        card.left + 16, card.top, card.right - 16, card.bottom);
    final warnings = find.byIcon(Icons.warning_amber_rounded);
    final drawn = [
      left,
      right,
      for (var i = 0; i < warnings.evaluate().length; i++)
        tester.getRect(warnings.at(i)),
    ];
    for (final r in drawn) {
      expect(r.left, greaterThanOrEqualTo(inner.left - 0.01), reason: '$r');
      expect(r.right, lessThanOrEqualTo(inner.right + 0.01), reason: '$r');
      expect(r.top, greaterThanOrEqualTo(inner.top), reason: '$r');
      expect(r.bottom, lessThanOrEqualTo(inner.bottom), reason: '$r');
    }
    expect((left.left + right.right) / 2, closeTo(card.center.dx, 0.01),
        reason: 'centred in the card');
    final scale = left.width / tester.getSize(keycaps.at(1)).width;
    for (var i = 1; i <= 2; i++) {
      final natural = tester.getSize(keycaps.at(i));
      final r = tester.getRect(keycaps.at(i));
      expect(r.width, closeTo(natural.width * scale, 0.01),
          reason: 'chord $i, scaled together with the other');
      expect(r.height, closeTo(natural.height * scale, 0.01),
          reason: 'chord $i keeps its keycaps\' proportions');
    }
    return scale;
  }

  testWidgets('on macOS the two chords share a line at full size',
      (tester) async {
    await pumpHost(tester, ready(refused: false), width: 600);
    expect(expectChordsOnOneLine(tester), 1);
  }, variant: macOS);

  /// Both chords of the second card at full size, the second beneath the first
  /// with the wrap's 6 pt run spacing, each line centred in the card and
  /// inside it. A warning belongs to the line it is on.
  void expectChordsWrapped(WidgetTester tester) {
    final keycaps = find.byType(KeycapRow);
    expect(keycaps, findsNWidgets(3),
        reason: 'the summon, then left and right');
    final card = cardAroundChords(tester);
    final inner = Rect.fromLTRB(
        card.left + 16, card.top, card.right - 16, card.bottom);
    final warnings = find.byIcon(Icons.warning_amber_rounded);
    final first = tester.getRect(keycaps.at(1));
    final second = tester.getRect(keycaps.at(2));
    expect(second.top - first.bottom, closeTo(6, 0.01),
        reason: 'the wrap\'s run spacing, the second chord beneath the first');
    for (var i = 1; i <= 2; i++) {
      final keys = tester.getRect(keycaps.at(i));
      expect(keys.size, tester.getSize(keycaps.at(i)),
          reason: 'chord $i at full size, never scaled');
      // The line: the keycaps and any warning beside them.
      var line = keys;
      for (var w = 0; w < warnings.evaluate().length; w++) {
        final icon = tester.getRect(warnings.at(w));
        if ((icon.center.dy - keys.center.dy).abs() < 0.01) {
          line = line.expandToInclude(icon);
        }
      }
      expect(line.left, greaterThanOrEqualTo(inner.left - 0.01),
          reason: 'line $i inside the card');
      expect(line.right, lessThanOrEqualTo(inner.right + 0.01),
          reason: 'line $i inside the card');
      expect(line.center.dx, closeTo(card.center.dx, 0.01),
          reason: 'line $i centred in the card');
    }
  }

  testWidgets('on Windows the second chord goes beneath the first at full '
      'size, each line centred', (tester) async {
    await pumpHost(tester, ready(refused: false), width: 600);
    expectChordsWrapped(tester);
    // A refused right half puts a warning (14 wide, 5 before the keycaps) on
    // the second line only, so the lines differ in width and only centring
    // puts its keycaps 9.5 right of the first line's. 700 wide, a wider card
    // than above and still too narrow for two chords.
    await pumpHost(
        tester,
        ReadyScreen(
          bindings: runningDefaults(),
          unavailable: {const BuiltIn(ShortcutCommand.rightHalf)},
          onDone: () {},
          onOpenShortcuts: () {},
        ),
        width: 700);
    expectChordsWrapped(tester);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    final rows = find.byType(KeycapRow);
    expect(tester.getRect(rows.at(2)).left - tester.getRect(rows.at(1)).left,
        9.5);
  }, variant: windows);

  testWidgets('on Windows two chords that fit share a line at full size, '
      '8 apart', (tester) async {
    KeyChord ctrl(LogicalKeyboardKey key) => KeyChord(
          physical: usPhysicalFor(key.keyId)!,
          logical: key.keyId,
          modifiers: Modifiers.ctrl,
        );
    final rebound = withRebind(
        withRebind(
            runningDefaults(),
            Binding(const BuiltIn(ShortcutCommand.leftHalf),
                ctrl(LogicalKeyboardKey.keyA))),
        Binding(const BuiltIn(ShortcutCommand.rightHalf),
            ctrl(LogicalKeyboardKey.keyB)));
    await pumpHost(
        tester,
        ReadyScreen(
          bindings: rebound,
          unavailable: const {},
          onDone: () {},
          onOpenShortcuts: () {},
        ),
        width: 600);
    final keycaps = find.byType(KeycapRow);
    final left = tester.getRect(keycaps.at(1));
    final right = tester.getRect(keycaps.at(2));
    expect(left.center.dy, closeTo(right.center.dy, 0.01), reason: 'one line');
    expect(right.left - left.right, closeTo(8, 0.01));
    expect(left.size, tester.getSize(keycaps.at(1)), reason: 'full size');
    expect((left.left + right.right) / 2,
        closeTo(cardAroundChords(tester).center.dx, 0.01),
        reason: 'centred in the card');
  }, variant: windows);

  testWidgets('on Windows a chord wider than its card shrinks to fit it',
      (tester) async {
    // Every modifier and the longest key name: in the test font, which draws
    // each character a font size wide, far wider than a card at 560.
    final summon = Binding(
        const BuiltIn(ShortcutCommand.showGrid),
        KeyChord(
          physical: usPhysicalFor(LogicalKeyboardKey.backspace.keyId)!,
          logical: LogicalKeyboardKey.backspace.keyId,
          modifiers: Modifiers.ctrl |
              Modifiers.alt |
              Modifiers.shift |
              Modifiers.meta,
        ));
    await pumpHost(
        tester,
        ReadyScreen(
          bindings: withRebind(runningDefaults(), summon),
          unavailable: const {},
          onDone: () {},
          onOpenShortcuts: () {},
        ));
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final chord = tester.getRect(find.byType(KeycapRow).first);
    final card = tester.getRect(find
        .ancestor(
            of: find.byType(KeycapRow).first, matching: find.byType(Container))
        .first);
    expect(chord.left, greaterThanOrEqualTo(card.left));
    expect(chord.right, lessThanOrEqualTo(card.right));
    expect(chord.width, lessThan(tester.getSize(find.byType(KeycapRow).first).width),
        reason: 'scaled down, not clipped');
  }, variant: windows);

  testWidgets('on macOS two chords rebound to four modifiers share a line, '
      'scaled down, where the row before R1 ran past the card',
      (tester) async {
    KeyChord all(LogicalKeyboardKey key) => KeyChord(
          physical: usPhysicalFor(key.keyId)!,
          logical: key.keyId,
          modifiers: Modifiers.ctrl |
              Modifiers.alt |
              Modifiers.shift |
              Modifiers.meta,
        );
    final rebound = withRebind(
        withRebind(
            runningDefaults(),
            Binding(const BuiltIn(ShortcutCommand.leftHalf),
                all(LogicalKeyboardKey.arrowLeft))),
        Binding(const BuiltIn(ShortcutCommand.rightHalf),
            all(LogicalKeyboardKey.arrowRight)));
    await pumpHost(
        tester,
        ReadyScreen(
          bindings: rebound,
          unavailable: const {},
          onDone: () {},
          onOpenShortcuts: () {},
        ));
    expect(expectChordsOnOneLine(tester), lessThan(1));
  }, variant: macOS);

  // The same three keycap rows and two warnings, measured on macOS at the base
  // this milestone started from, before the card's row became a wrap: R1 must
  // lay the ready screen out exactly as 1.0.x did.
  for (final (width, refused, rows, icons) in [
    (560.0, false, [113.875, 321.75, 410.0], <double>[]),
    (560.0, true, [123.375, 312.25, 419.5], [104.375, 400.5]),
    (600.0, false, [123.875, 351.75, 440.0], <double>[]),
    (600.0, true, [133.375, 342.25, 449.5], [114.375, 430.5]),
  ]) {
    testWidgets('on macOS the ready screen lays out as 1.0.x did '
        '(${width.toInt()} wide${refused ? ', two chords refused' : ''})',
        (tester) async {
      await pumpHost(
          tester,
          ReadyScreen(
            bindings: runningDefaults(),
            unavailable: {
              if (refused) showGrid,
              if (refused) const BuiltIn(ShortcutCommand.rightHalf),
            },
            onDone: () {},
            onOpenShortcuts: () {},
          ),
          width: width);
      final top = width == 560 ? 483.0 : 491.5;
      final found = find.byType(KeycapRow);
      expect([for (var i = 0; i < 3; i++) tester.getRect(found.at(i))], [
        for (final left in rows) Rect.fromLTWH(left, top, 80.25, 21),
      ]);
      final warnings = find.byIcon(Icons.warning_amber_rounded);
      expect(
          [
            for (var i = 0; i < warnings.evaluate().length; i++)
              tester.getRect(warnings.at(i)),
          ],
          [for (final left in icons) Rect.fromLTWH(left, top + 3.5, 14, 14)]);
    }, variant: macOS);
  }
}
