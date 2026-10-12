import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/ready_screen.dart';
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

  // The ready screen's second card shows two chords. macOS's glyphs fit side
  // by side; Windows' words do not, and the second goes beneath the first
  // rather than past the card's edge. 600 wide, not the window's 560: in
  // flutter_test's font even one of Windows' chords is wider than a card at
  // 560 (Segoe UI's is not, which the VM's screenshots show), and what is
  // tested here is that two chords wrap where one fits.
  double gapBetweenChordRows(WidgetTester tester) {
    final rows = find.byType(KeycapRow);
    expect(rows, findsNWidgets(3), reason: 'the summon, then left and right');
    return tester.getTopLeft(rows.at(2)).dy - tester.getTopLeft(rows.at(1)).dy;
  }

  testWidgets('on macOS the two chords share a line', (tester) async {
    await pumpHost(tester, ready(refused: false), width: 600);
    expect(gapBetweenChordRows(tester), 0);
  }, variant: macOS);

  testWidgets('on Windows the second chord goes beneath the first, centred',
      (tester) async {
    await pumpHost(tester, ready(refused: false), width: 600);
    expect(gapBetweenChordRows(tester), 21 + 6,
        reason: 'one keycap row, then the wrap\'s run spacing');
    // A refused right half puts a warning (14 wide, 5 before the keycaps) on
    // the second line only, so the lines differ in width and only centring
    // puts its keycaps 9.5 right of the first line's. 700 wide: in the test
    // font a refused chord alone is wider than a card at 600.
    await pumpHost(
        tester,
        ReadyScreen(
          bindings: runningDefaults(),
          unavailable: {const BuiltIn(ShortcutCommand.rightHalf)},
          onDone: () {},
          onOpenShortcuts: () {},
        ),
        width: 700);
    final rows = find.byType(KeycapRow);
    expect(tester.getRect(rows.at(2)).left - tester.getRect(rows.at(1)).left,
        9.5);
  }, variant: windows);

  testWidgets('on macOS two chords rebound to four modifiers wrap rather than '
      'run past the card, which the row before R1 did', (tester) async {
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
    expect(gapBetweenChordRows(tester), 21 + 6);
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
