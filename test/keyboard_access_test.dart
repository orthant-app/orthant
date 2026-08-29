import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/grid_config.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/settings_window.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// The window's controls were bare `GestureDetector`s: unreachable by Tab,
/// unusable by Space or Return, with no focus ring and nothing for VoiceOver to
/// announce. On an app whose whole subject is keyboard shortcuts, the pane for
/// configuring them was the one part that could not be driven from a keyboard.
///
/// These drive it the way a person does — Tab until the thing you want has
/// focus, then press Space — rather than reaching in to request focus on a node.
/// That is the behaviour under test, and it is also the only version that would
/// fail if traversal broke.
void main() {
  Widget host({
    Settings settings = const Settings(),
    List<Binding> bindings = kDefaultBindings,
    bool permissionGranted = true,
    LoginItemStatus loginStatus = LoginItemStatus.disabled,
    void Function(Settings)? onSettingsChanged,
    void Function(Binding)? onRebound,
    VoidCallback? onResetBindings,
    VoidCallback? onOpenAccessibility,
    SettingsTab initialTab = SettingsTab.general,
  }) => MaterialApp(
    theme: macTheme(Brightness.light),
    home: SettingsWindow(
      initialTab: initialTab,
      onOpenAccessibility: onOpenAccessibility,
      settings: settings,
      bindings: bindings,
      permissionGranted: permissionGranted,
      loginStatus: loginStatus,
      onSettingsChanged: onSettingsChanged ?? (_) {},
      onRebound: onRebound ?? (_) {},
      onResetBindings: onResetBindings,
    ),
  );

  /// The semantic label of whatever has focus — which is also what a screen
  /// reader would read, so one helper covers reachability and announcement.
  String? focusedLabel(WidgetTester tester) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    var node = tester.getSemantics(find.byElementPredicate((e) => e == ctx));
    // A control named by its own text — a push button, say — carries that name
    // on the *merging* node above the focusable one, which is the single node
    // the platform is handed. The focusable node's own label is empty.
    var label = node.getSemanticsData().label;
    while (label.isEmpty && node.parent != null) {
      node = node.parent!;
      label = node.getSemanticsData().label;
    }
    return label.isEmpty ? null : label;
  }

  /// Tab until the focused control's label satisfies [match]. Returns whether it
  /// was reached — a false here means the control is not keyboard-reachable at
  /// all, which is the defect this suite exists for.
  Future<bool> tabTo(
    WidgetTester tester,
    bool Function(String label) match, {
    int limit = 30,
  }) async {
    for (var i = 0; i < limit; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final label = focusedLabel(tester);
      if (label != null && match(label)) return true;
    }
    return false;
  }

  /// Whether a row's clear button is **shown**, as distinct from present.
  ///
  /// It is resident in the tree for every bound row so a screen reader can
  /// always reach it; only its opacity tracks hover and focus. `find.byIcon`
  /// therefore answers the wrong question now — it finds all eleven.
  bool clearShown(WidgetTester tester, ShortcutCommand cmd) => tester
      .widget<Visibility>(find.byKey(ValueKey('clear-${cmd.name}')))
      .visible;

  /// Every label Tab visits, in one pass around the pane.
  Future<Set<String>> walk(WidgetTester tester, {int steps = 30}) async {
    final seen = <String>{};
    for (var i = 0; i < steps; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final l = focusedLabel(tester);
      if (l != null) seen.add(l);
    }
    return seen;
  }

  group('every control can be reached', () {
    testWidgets('Tab reaches each General control', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final seen = await walk(tester);
      expect(seen, isNotEmpty, reason: 'nothing took focus at all');
      for (final want in ['Columns', 'Rows', 'Leave gaps', 'Launch at login']) {
        expect(seen.any((l) => l.contains(want)), isTrue,
            reason: '$want was unreachable; visited: $seen');
      }
      handle.dispose();
    });

    testWidgets('Tab reaches each shortcut row', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
      await tester.pumpAndSettle();

      final seen = await walk(tester, steps: 40);
      for (final want in ['Open grid', 'Left half', 'Maximize', 'Center']) {
        expect(seen.any((l) => l.startsWith(want)), isTrue,
            reason: '$want was unreachable');
      }
      handle.dispose();
    });

    testWidgets('a disabled control is skipped, not focused', (tester) async {
      // The gap-size stepper is inert while gaps are off. Tabbing onto something
      // that does nothing is worse than skipping it: it reads as a dead end.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(settings: const Settings(gaps: false)));
      await tester.pumpAndSettle();

      final seen = await walk(tester);
      expect(seen.any((l) => l.startsWith('Size')), isFalse);
      handle.dispose();
    });
  });

  group('every control can be used', () {
    testWidgets('Space raises a stepper', (tester) async {
      // Reachable is not usable: ActivateIntent has to land on the same callback
      // a tap does, or the control is focusable and inert.
      final handle = tester.ensureSemantics();
      final changes = <Settings>[];
      await tester.pumpWidget(host(onSettingsChanged: changes.add));
      await tester.pumpAndSettle();

      expect(
        await tabTo(tester, (l) => l.startsWith('Columns') && l.endsWith('increase')),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(changes.single.gridCols, kDefaultGridCols + 1);
      handle.dispose();
    });

    testWidgets('Return works as well as Space', (tester) async {
      final handle = tester.ensureSemantics();
      final changes = <Settings>[];
      await tester.pumpWidget(host(onSettingsChanged: changes.add));
      await tester.pumpAndSettle();

      expect(
        await tabTo(tester, (l) => l.startsWith('Rows') && l.endsWith('decrease')),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(changes.single.gridRows, kDefaultGridRows - 1);
      handle.dispose();
    });

    testWidgets('a checkbox toggles', (tester) async {
      final handle = tester.ensureSemantics();
      final changes = <Settings>[];
      await tester.pumpWidget(host(onSettingsChanged: changes.add));
      await tester.pumpAndSettle();

      expect(await tabTo(tester, (l) => l.startsWith('Leave gaps')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(changes.single.gaps, isTrue);
      handle.dispose();
    });

    testWidgets('a push button fires', (tester) async {
      final handle = tester.ensureSemantics();
      final changes = <Settings>[];
      await tester.pumpWidget(host(
        settings: const Settings(gridCols: 9),
        onSettingsChanged: changes.add,
      ));
      await tester.pumpAndSettle();

      expect(await tabTo(tester, (l) => l.contains('Reset Grid & Gaps')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(changes.single, const Settings());
      handle.dispose();
    });

    testWidgets('a shortcut row starts recording', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
      await tester.pumpAndSettle();

      expect(await tabTo(tester, (l) => l.startsWith('Maximize'), limit: 40),
          isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Press keys…'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the tab bar switches panes', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(await tabTo(tester, (l) => l.startsWith('Shortcuts tab')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Left half'), findsOneWidget);
      handle.dispose();
    });
  });

  group('focus reveals what hover reveals', () {
    testWidgets('focusing a shortcut row exposes its clear button',
        (tester) async {
      // The clear affordance appeared on hover only, so a keyboard user could
      // not remove a binding at all — in the pane about the keyboard.
      final handle = tester.ensureSemantics();
      final changes = <Binding>[];
      await tester.pumpWidget(host(
        initialTab: SettingsTab.shortcuts,
        onRebound: changes.add,
      ));
      await tester.pumpAndSettle();
      expect(clearShown(tester, ShortcutCommand.maximize), isFalse);

      expect(await tabTo(tester, (l) => l.startsWith('Maximize'), limit: 40),
          isTrue);
      expect(clearShown(tester, ShortcutCommand.maximize), isTrue,
          reason: 'focus must reveal it exactly as hover does');

      await tester.tap(find.bySemanticsLabel('Remove Maximize shortcut'));
      await tester.pumpAndSettle();
      expect(changes.single.command, const BuiltIn(ShortcutCommand.maximize));
      expect(changes.single.isBound, isFalse);
      handle.dispose();
    });
  });

  group('what a screen reader hears', () {
    testWidgets('a shortcut row names its command and its combo',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Left half, ⌃⌥←'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an unbound command says so rather than reading blank',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        initialTab: SettingsTab.shortcuts,
        bindings: withRebind(
            kDefaultBindings, Binding.unbound(BuiltIn(ShortcutCommand.center))),
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Center, no shortcut'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a refused combo is announced as unavailable', (tester) async {
      // It is stored, displayed and never delivered. The row shows a warning
      // icon; an icon is not something a screen reader can convey.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: macTheme(Brightness.light),
        home: SettingsWindow(
          initialTab: SettingsTab.shortcuts,
          settings: const Settings(),
          bindings: kDefaultBindings,
          unavailable: {const BuiltIn(ShortcutCommand.leftHalf)},
          onSettingsChanged: (_) {},
          onRebound: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Left half, ⌃⌥←, unavailable'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('a checkbox announces itself exactly once', (tester) async {
      // The nested Material Checkbox is excluded from semantics, or VoiceOver
      // would read the state twice. The state itself is a flag, not part of the
      // name — see the operability group below.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(settings: const Settings(gaps: true)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Leave gaps'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the selected tab says it is selected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('General tab'), findsOneWidget);
      handle.dispose();
    });
  });

  /// Hearing a control is not using it. These assert **actions and flags**,
  /// which is the half a label test cannot see: `excludeSemantics` dropped the
  /// child `GestureDetector`'s tap action along with its text, and the node
  /// left behind announced itself as a button that nothing could press. Tab and
  /// Space still worked, so every keyboard test above passed while VoiceOver
  /// could read the whole window and operate none of it.
  group('the accessibility tree is operable, not only readable', () {
    SemanticsData data(WidgetTester tester, String label) =>
        tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

    testWidgets('a checkbox can be activated, and carries its state as a flag',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final d = data(tester, 'Leave gaps');
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: 'a screen reader activates by sending tap');
      // A checkbox is a role, not a button with the state glued into its name:
      // VoiceOver says "checkbox, unchecked" itself, and a manual ", off" made
      // it say so twice.
      expect(d.flagsCollection.isChecked, CheckedState.isFalse,
          reason: 'a check state at all, and reading unchecked');
      expect(d.flagsCollection.isButton, isFalse);
      handle.dispose();
    });

    testWidgets('a checked checkbox reads as checked', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(settings: const Settings(gaps: true)));
      await tester.pumpAndSettle();
      expect(data(tester, 'Leave gaps').flagsCollection.isChecked,
          CheckedState.isTrue);
      handle.dispose();
    });

    testWidgets('a tab carries the selected flag, and the tab role',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(data(tester, 'General tab').flagsCollection.isSelected,
          Tristate.isTrue);
      expect(data(tester, 'Shortcuts tab').flagsCollection.isSelected,
          Tristate.isFalse);
      expect(data(tester, 'Shortcuts tab').hasAction(SemanticsAction.tap), isTrue);
      // "Selected button" is not a tab. The role is what tells a screen reader
      // this is one of a set and lets it say which.
      expect(data(tester, 'General tab').role, SemanticsRole.tab);
      expect(data(tester, 'General tab').flagsCollection.isButton, isFalse);
      handle.dispose();
    });

    testWidgets('a tab sits inside a node that announces as a tab bar',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      // Asserted as an *ancestor* of the tab rather than as some node somewhere
      // in the tree: what a screen reader needs is the containment, which is
      // what lets it say "1 of 2".
      var node = find.semantics.byLabel('General tab').evaluate().single.parent;
      var inTabBar = false;
      while (node != null && !inTabBar) {
        inTabBar = node.getSemanticsData().role == SemanticsRole.tabBar;
        node = node.parent;
      }
      expect(inTabBar, isTrue);
      handle.dispose();
    });

    testWidgets('the clear button is reachable with nothing focused at all',
        (tester) async {
      // Its existence used to depend on the row being hovered or
      // keyboard-focused. A screen reader's cursor is neither, so a reader user
      // met a row whose only destructive control had never been built.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
      await tester.pumpAndSettle();

      expect(clearShown(tester, ShortcutCommand.leftHalf), isFalse,
          reason: 'nothing is pointing at it, so nothing is drawn');
      expect(find.bySemanticsLabel('Remove Left half shortcut'), findsOneWidget,
          reason: 'but a reader can still find it');
      expect(data(tester, 'Remove Left half shortcut')
          .hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('the reader can move from a row onto its clear button',
        (tester) async {
      // The exact handoff, and the reason reveal-on-focus could not work:
      // Flutter's macOS bridge dispatches `didLoseAccessibilityFocus` to the
      // row *before* it records the newly focused node
      // (`AccessibilityBridge::SetLastFocusedId`). A button whose existence
      // followed the row's reader focus was therefore deleted on the way to it.
      // The previous version of this test asserted that removal — documenting
      // the defect rather than catching it.
      final handle = tester.ensureSemantics();
      final changes = <Binding>[];
      await tester.pumpWidget(host(
        initialTab: SettingsTab.shortcuts,
        onRebound: changes.add,
      ));
      await tester.pumpAndSettle();
      final row = find.semantics.byLabel('Left half, ⌃⌥←');

      tester.semantics.performAction(row, SemanticsAction.didGainAccessibilityFocus);
      await tester.pumpAndSettle();
      expect(clearShown(tester, ShortcutCommand.leftHalf), isTrue);

      // The cursor leaves the row for the button. A frame lands in between,
      // which is precisely what used to remove it.
      tester.semantics.performAction(row, SemanticsAction.didLoseAccessibilityFocus);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Remove Left half shortcut'), findsOneWidget,
          reason: 'the cursor is arriving at it, not leaving the row empty');
      tester.semantics.performAction(
          find.semantics.byLabel('Remove Left half shortcut'), SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(changes.single.command, const BuiltIn(ShortcutCommand.leftHalf));
      expect(changes.single.isBound, isFalse);
      handle.dispose();
    });

    testWidgets('each clear button names the shortcut it removes',
        (tester) async {
      // Eleven of them are resident, so "Remove shortcut" alone identifies one
      // only for someone who happened to hear the row first.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Remove Maximize shortcut'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove Center shortcut'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a shortcut row can be activated', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
      await tester.pumpAndSettle();
      expect(data(tester, 'Left half, ⌃⌥←').hasAction(SemanticsAction.tap),
          isTrue);
      handle.dispose();
    });

    testWidgets('the clear button survives its labelled parent row',
        (tester) async {
      // A separate mechanism from residency, and a separate regression: the
      // row's label describes the row, and excluding the child's semantics to
      // stop it being read twice deleted the only control that removes a
      // binding. `containsControl` is the opt-out — a nested control is not
      // decoration.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
      await tester.pumpAndSettle();
      expect(await tabTo(tester, (l) => l.startsWith('Maximize'), limit: 40),
          isTrue);
      expect(find.bySemanticsLabel('Remove Maximize shortcut'), findsOneWidget);
      expect(data(tester, 'Remove Maximize shortcut')
          .hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('a push button can be activated', (tester) async {
      // Space reaching this control is a different claim from a screen reader
      // being able to send it a tap, and the keyboard tests cannot stand in:
      // this exact control passed every one of them while its name and its
      // action sat on different nodes.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        permissionGranted: false,
        onOpenAccessibility: () {},
      ));
      await tester.pumpAndSettle();
      expect(
          data(tester, 'Open Accessibility Settings…')
              .hasAction(SemanticsAction.tap),
          isTrue);
      handle.dispose();
    });

    testWidgets('an unbound row has no clear button to reach', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        initialTab: SettingsTab.shortcuts,
        bindings: withRebind(
            kDefaultBindings, Binding.unbound(BuiltIn(ShortcutCommand.center))),
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Remove Center shortcut'), findsNothing);
      handle.dispose();
    });
  });
}
