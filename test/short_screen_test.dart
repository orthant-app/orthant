import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/ready_screen.dart';
import 'package:orthant/settings/mac_control.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/region_picker_sheet.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/settings_window.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// A 768-pixel screen at 200 % leaves the settings window about 300 DIP of
/// client: 384 DIP of screen, less the taskbar (48) and the title bar (32).
/// On Windows the window's 500 DIP floor gives way to a work area that short,
/// so every screen it shows must scroll, with every control in reach, in its
/// ordinary state and with a question or a refusal showing.
void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  const short = Size(560, 300);
  const leftHalf = BuiltIn(ShortcutCommand.leftHalf);

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = short;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: orthantTheme(Brightness.light),
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  /// Wheels the scroll view [one] is in, from the middle of what shows of it,
  /// until [one] would take a tap, as a user with a mouse reaches it, or the
  /// wheel has had forty turns. A control in no scroll view is left as it is.
  Future<void> wheelTo(WidgetTester tester, Finder one) async {
    final view = find.ancestor(of: one, matching: find.byType(Scrollable));
    if (view.evaluate().isEmpty) return;
    final shown =
        tester.getRect(view.first).intersect(Offset.zero & short);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(shown.center));
    for (var i = 0; i < 40 && one.hitTestable().evaluate().isEmpty; i++) {
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
      await tester.pumpAndSettle();
    }
  }

  /// Every control on screen, wheeled to, then hit by a tap at its centre:
  /// inside the window and under nothing else.
  Future<void> expectEveryControlReachable(WidgetTester tester) async {
    final controls = find.byWidgetPredicate((w) =>
        w is MacControl ||
        w is ButtonStyleButton ||
        w is Checkbox ||
        w is EditableText ||
        w.key == const ValueKey('region-grid'));
    final n = controls.evaluate().length;
    expect(n, greaterThan(0));
    for (var i = 0; i < n; i++) {
      final one = controls.at(i);
      await wheelTo(tester, one);
      final rect = tester.getRect(one);
      expect(rect.center.dy, inInclusiveRange(0, short.height),
          reason: '${tester.widget(one)} at $rect');
      expect(one.hitTestable(), findsOneWidget,
          reason: '${tester.widget(one)} at $rect is covered');
    }
  }

  Future<void> chord(WidgetTester tester, List<LogicalKeyboardKey> held,
      LogicalKeyboardKey key) async {
    for (final k in held) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(key);
    for (final k in held.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pumpAndSettle();
  }

  const winCtrlShift = [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.shiftLeft,
  ];

  SettingsWindow settings(SettingsTab tab) => SettingsWindow(
        settings: const Settings(gaps: true),
        bindings: runningDefaults(),
        onSettingsChanged: (_) {},
        onRebound: (_) {},
        onRestoreBindings: (_) {},
        onRegionSaved: (_) {},
        onRegionDeleted: (_) {},
        onResetBindings: () {},
        loginStatus: LoginItemStatus.requiresApproval,
        onSetLoginItem: (_) {},
        onOpenLoginItems: () {},
        initialTab: tab,
        version: const AppVersion('1.0.3', '7'),
        onCheckForUpdates: () {},
        onAutomaticChecksChanged: (_) {},
      );

  RegionPickerSheet picker({bool editing = false, bool taken = false}) =>
      RegionPickerSheet(
        initial: editing
            ? const CustomRegion(
                id: 'r1',
                name: 'Left ⅔',
                cols: 3,
                rows: 1,
                c0: 0,
                c1: 1,
                r0: 0,
                r1: 0,
              )
            : null,
        initialChord: taken
            ? runningDefaults().firstWhere((b) => b.command == leftHalf).chord
            : null,
        gridCols: 6,
        gridRows: 6,
        onSubmit: (_) {},
        onCancel: () {},
        onDelete: editing ? () {} : null,
        conflictName: (_) => 'Left half',
      );

  for (final tab in SettingsTab.values) {
    testWidgets('the settings window\'s ${tab.name} pane', (tester) async {
      await pump(tester, settings(tab));
      await expectEveryControlReachable(tester);
    }, variant: windows);
  }

  testWidgets('the shortcuts pane asking about a taken chord', (tester) async {
    await pump(tester, settings(SettingsTab.shortcuts));
    await tester.tap(find.text('Left half'));
    await tester.pumpAndSettle();
    await chord(tester, winCtrlShift, LogicalKeyboardKey.arrowRight);
    expect(find.text('Use it here'), findsOneWidget);
    await expectEveryControlReachable(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }, variant: windows);

  testWidgets('the shortcuts pane refusing a keypad digit', (tester) async {
    await pump(tester, settings(SettingsTab.shortcuts));
    await tester.tap(find.text('Left half'));
    await tester.pumpAndSettle();
    await chord(tester, [LogicalKeyboardKey.controlLeft],
        LogicalKeyboardKey.numpad1);
    expect(find.textContaining('keypad'), findsOneWidget);
    await expectEveryControlReachable(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }, variant: windows);

  testWidgets('the region picker, new', (tester) async {
    await pump(tester, Scaffold(body: picker()));
    await expectEveryControlReachable(tester);
  }, variant: windows);

  testWidgets('the region picker, editing', (tester) async {
    await pump(tester, Scaffold(body: picker(editing: true)));
    await expectEveryControlReachable(tester);
  }, variant: windows);

  testWidgets('the region picker asking about a taken chord', (tester) async {
    await pump(tester, Scaffold(body: picker(taken: true)));
    expect(find.text('Use it here'), findsOneWidget);
    await expectEveryControlReachable(tester);
  }, variant: windows);

  testWidgets('the region picker refusing a keypad digit', (tester) async {
    await pump(tester, Scaffold(body: picker()));
    await tester.ensureVisible(find.byKey(const ValueKey('region-record')));
    await tester.tap(find.byKey(const ValueKey('region-record')));
    await tester.pumpAndSettle();
    await chord(tester, [LogicalKeyboardKey.controlLeft],
        LogicalKeyboardKey.numpad1);
    expect(find.textContaining('keypad'), findsOneWidget);
    await expectEveryControlReachable(tester);
  }, variant: windows);

  /// The sheet's scroll view, and where it is scrolled to.
  double sheetScrolled(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
              of: find.byType(RegionPickerSheet),
              matching: find.byType(Scrollable))
          .first)
      .position
      .pixels;

  // A drag on the grid draws, whatever makes it: a finger or a pen moving in
  // small steps, as they do, would otherwise be taken by the sheet's scroll
  // view once the window is too short for the sheet.
  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
  ]) {
    testWidgets('in a short window a ${kind.name} drag down the grid draws, '
        'and the sheet stays put', (tester) async {
      RegionDraft? drawn;
      await pump(
          tester,
          Scaffold(
            body: RegionPickerSheet(
              gridCols: 6,
              gridRows: 6,
              onSubmit: (d) => drawn = d,
              onCancel: () {},
            ),
          ));
      // Scrolled partway first, so a drag the sheet took would show: down
      // the grid, it would scroll the sheet back up.
      final mouse = TestPointer(9, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(short.center(Offset.zero)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 30)));
      await tester.pumpAndSettle();
      final scrolled = sheetScrolled(tester);
      expect(scrolled, greaterThan(0));
      final grid = tester.getRect(find.byKey(const ValueKey('region-grid')));
      final cell = Size(grid.width / 6, grid.height / 6);
      final drag = await tester.startGesture(
          grid.topLeft + Offset(cell.width * 1.5, cell.height * 0.5),
          kind: kind);
      for (var i = 0; i < 14; i++) {
        await drag.moveBy(Offset(0, cell.height * 2 / 14));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(sheetScrolled(tester), scrolled);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(drawn, isNotNull);
      final r = drawn!.region;
      expect((r.c0, r.c1, r.r0, r.r1), (1, 1, 0, 2),
          reason: 'one column, three rows: the drag, not a single cell');
    }, variant: windows);
  }

  testWidgets('in a short window a trackpad\'s two-finger scroll over the '
      'grid scrolls the sheet', (tester) async {
    await pump(
        tester,
        Scaffold(
          body: RegionPickerSheet(
            gridCols: 6,
            gridRows: 6,
            onSubmit: (_) {},
            onCancel: () {},
          ),
        ));
    final grid = tester.getRect(find.byKey(const ValueKey('region-grid')));
    final swipe =
        await tester.startGesture(grid.center, kind: PointerDeviceKind.trackpad);
    for (var i = 0; i < 10; i++) {
      await swipe.moveBy(const Offset(0, -8));
      await tester.pump();
    }
    await swipe.up();
    await tester.pumpAndSettle();
    expect(sheetScrolled(tester), greaterThan(0));
  }, variant: windows);

  testWidgets('the ready screen', (tester) async {
    await pump(
        tester,
        ReadyScreen(
          bindings: runningDefaults(),
          onDone: () {},
          onOpenShortcuts: () {},
        ));
    await expectEveryControlReachable(tester);
  }, variant: windows);
}
