import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/region_picker_sheet.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/settings_window.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';
import 'package:orthant/shortcuts/command_ref.dart';

void main() {
  Widget host({
    Settings settings = const Settings(),
    List<Binding> bindings = kDefaultBindings,
    LoginItemStatus loginStatus = LoginItemStatus.disabled,
    bool permissionGranted = true,
    void Function(Settings)? onSettingsChanged,
    void Function(bool)? onSetLoginItem,
    VoidCallback? onResetBindings,
    Set<CommandRef> unavailable = const {},
    SettingsTab initialTab = SettingsTab.general,
    CustomRegion? pendingRegion,
    VoidCallback? onPendingConsumed,
    void Function(RegionDraft)? onRegionSaved,
  }) =>
      MaterialApp(
        theme: macTheme(Brightness.light),
        home: SettingsWindow(
          initialTab: initialTab,
          settings: settings,
          bindings: bindings,
          loginStatus: loginStatus,
          permissionGranted: permissionGranted,
          onSettingsChanged: onSettingsChanged ?? (_) {},
          onRebound: (_) {},
          onSetLoginItem: onSetLoginItem,
          unavailable: unavailable,
          onResetBindings: onResetBindings,
          pendingRegion: pendingRegion,
          onPendingConsumed: onPendingConsumed,
          onRegionSaved: onRegionSaved,
        ),
      );

  testWidgets('opens on General and can switch to Shortcuts', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Launch at login'), findsOneWidget);
    expect(find.text('Left half'), findsNothing);

    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();

    expect(find.text('Launch at login'), findsNothing);
    expect(find.text('Left half'), findsOneWidget);
    // The summon is a shortcut like any other, so it belongs in this list.
    expect(find.text('Open grid'), findsOneWidget);
  });

  testWidgets('the Shortcuts list survives a binding it cannot find',
      (tester) async {
    // This rendered a **blank grey pane** in Release. `_bindingFor` used a bare
    // firstWhere, which throws StateError when the list has no entry for a
    // command — and a build-time throw in a release build is an ErrorWidget
    // with no text, i.e. an empty box. The two panes that do the same lookup
    // with an orElse (General, Ready) degraded to "Not set" instead, which is
    // why only this one looked broken.
    await tester.pumpWidget(host(bindings: const [], initialTab: SettingsTab.shortcuts));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Left half'), findsOneWidget, reason: 'the rows still render');
    expect(find.text('Click to set'), findsWidgets, reason: 'each simply has no combo');
  });

  testWidgets('the Shortcuts list says why nothing will fire, when nothing will',
      (tester) async {
    // A list of eleven ordinary-looking shortcuts, none of which work, is the
    // exact silence the `unavailable` warnings exist to break — and this tab is
    // where someone stares when pressing a key does nothing. General carries
    // the same warning, but nobody reads the other tab to explain this one.
    await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
    await tester.pumpAndSettle();
    expect(find.textContaining('Accessibility'), findsNothing);

    await tester.pumpWidget(host(
        initialTab: SettingsTab.shortcuts, permissionGranted: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('until Orthant has Accessibility'), findsOneWidget);
    expect(find.text('Open Accessibility Settings…'), findsOneWidget);
  });

  testWidgets('opens on the tab it was asked for', (tester) async {
    // The ready screen's "Change these shortcuts…" named a list and then
    // landed on General, one click short of it. The window still *defaults* to
    // General — the tray's plain "Settings…" has no particular tab in mind.
    await tester.pumpWidget(host(initialTab: SettingsTab.shortcuts));
    await tester.pumpAndSettle();
    expect(find.text('Left half'), findsOneWidget);
    expect(find.text('Launch at login'), findsNothing);
  });

  testWidgets('a pending region moves an already-open window to Shortcuts',
      (tester) async {
    // ⌘S on the grid with Settings already open on General: the coordinator
    // asks for the Shortcuts tab, but `initialTab` is — deliberately — read
    // once, so the mounted window ignored the request. The picker then waited
    // behind the General pane, and a deliberate save looked like it did
    // nothing. A *new* pending region is the one prop change that may move the
    // tab; anything else moving it would fight the user's own tab choice.
    var consumed = 0;
    final region = CustomRegion(
        id: 'r1', name: 'Left ⅔', cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0);

    await tester.pumpWidget(host(onRegionSaved: (_) {}));
    expect(find.text('Launch at login'), findsOneWidget, reason: 'on General');

    await tester.pumpWidget(host(
      onRegionSaved: (_) {},
      pendingRegion: region,
      onPendingConsumed: () => consumed++,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Left half'), findsOneWidget,
        reason: 'the window switched itself to Shortcuts');
    expect(find.text('Launch at login'), findsNothing);
    expect(find.byType(RegionPickerSheet), findsOneWidget,
        reason: 'the picker opened on the shape instead of waiting unseen');
    expect(consumed, 1);

    // The region is consumed and the rebuild hands the window a null — which
    // must not yank the tab anywhere.
    await tester.pumpWidget(host(onRegionSaved: (_) {}));
    await tester.pump();
    expect(find.byType(RegionPickerSheet), findsOneWidget,
        reason: 'consumption does not close the sheet');
  });

  testWidgets('has no Quit affordance', (tester) async {
    // Divvy puts Quit in its settings window. Quitting is a tray/app-menu
    // action; a settings window that can terminate the app is a category error.
    await tester.pumpWidget(host());
    expect(find.textContaining('Quit'), findsNothing);
  });

  group('a window too short for its pane loses nothing', () {
    // Nothing sizes the window to its pane any more: the user drags it, macOS
    // remembers it, and a pane gets whatever height that leaves. Shorter than
    // the content is therefore the ordinary case rather than the edge one — the
    // Shortcuts pane already exceeded two of this machine's three displays — so
    // a pane must degrade to scrolling rather than putting its own action out of
    // reach, which is what a footer inside the scroll area did.
    Widget short(SettingsTab tab, {bool permissionGranted = false}) =>
        MaterialApp(
          theme: macTheme(Brightness.light),
          home: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 560,
              height: 360, // a laptop with the Dock and menu bar taking their cut
              child: SettingsWindow(
                initialTab: tab,
                settings: const Settings(),
                bindings: kDefaultBindings,
                permissionGranted: permissionGranted,
                onSettingsChanged: (_) {},
                onRebound: (_) {},
                onResetBindings: () {},
              ),
            ),
          ),
        );

    testWidgets('General keeps its footer button reachable', (tester) async {
      await tester.pumpWidget(short(SettingsTab.general));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Reset Grid & Gaps'), findsOneWidget);
      // Pinned, not merely present: it must be inside the visible window.
      final button = tester.getRect(find.text('Reset Grid & Gaps'));
      expect(button.bottom, lessThanOrEqualTo(360));
    });

    testWidgets('Shortcuts keeps its footer button reachable', (tester) async {
      await tester.pumpWidget(short(SettingsTab.shortcuts));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.text('Reset Shortcuts'));
      expect(button.bottom, lessThanOrEqualTo(360));
    });

    testWidgets('and the warning is never the thing that scrolls away',
        (tester) async {
      // It sits above the scroll area for exactly this reason.
      await tester.pumpWidget(short(SettingsTab.shortcuts));
      await tester.pumpAndSettle();
      final notice =
          tester.getRect(find.textContaining('until Orthant has Accessibility'));
      expect(notice.bottom, lessThanOrEqualTo(360));
    });

    testWidgets('switching tabs leaves the footer inside the window',
        (tester) async {
      // Was expressed through the height the window settled at. There is no
      // settling now: the window is a fixed size and the pane scrolls inside it,
      // so the assertion is against the viewport — which is what the sizing
      // arithmetic used to subtract, and the thing that actually has to contain
      // the footer.
      await tester.pumpWidget(short(SettingsTab.shortcuts));
      await tester.pumpAndSettle();

      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.text('Reset Grid & Gaps'));
      expect(button.bottom, lessThanOrEqualTo(360),
          reason: 'the footer must be inside the window, not below it');
    });
  });

  testWidgets('permission status is always visible, and actionable when absent',
      (tester) async {
    // Always, unlike the tray row. A menu has no room for a permanently green
    // line, but this is a settings pane, and "does Orthant actually have
    // permission?" is the first thing anyone debugging it wants to see. Spec §6
    // lists permission status as an M7 deliverable in its own right.
    await tester.pumpWidget(host());
    expect(find.text('Granted'), findsOneWidget);
    expect(find.text('Open Accessibility Settings…'), findsNothing);

    await tester.pumpWidget(host(permissionGranted: false));
    expect(find.text('Granted'), findsNothing);
    expect(find.textContaining('Not granted'), findsOneWidget);
    expect(find.text('Open Accessibility Settings…'), findsOneWidget);
  });

  testWidgets('General mirrors the summon and routes to where it is edited',
      (tester) async {
    // "The global binding" is what people come to a General tab looking for —
    // this is where the pane was first searched and the setting was not found.
    // Read-only, so the Shortcuts list stays the single collision domain.
    await tester.pumpWidget(host());
    expect(find.text('Open grid'), findsOneWidget);
    expect(find.text('O'), findsOneWidget, reason: 'the live combo, as keycaps');

    await tester.tap(find.text('Change…'));
    await tester.pumpAndSettle();
    expect(find.text('Left half'), findsOneWidget,
        reason: 'Change… lands on the Shortcuts tab');
  });

  testWidgets('a refused summon chord is marked in General too', (tester) async {
    await tester.pumpWidget(host(unavailable: {const BuiltIn(ShortcutCommand.showGrid)}));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('requiresApproval explains itself rather than reading as off',
      (tester) async {
    // Registration succeeded but the item is switched off in System Settings,
    // so the app will not launch. A bare unchecked box would say "off" and
    // hide the fact that the remedy lives outside this app.
    await tester
        .pumpWidget(host(loginStatus: LoginItemStatus.requiresApproval));
    expect(find.textContaining('System Settings'), findsOneWidget);
    expect(find.text('Open Login Items…'), findsOneWidget);

    await tester.pumpWidget(host(loginStatus: LoginItemStatus.enabled));
    expect(find.textContaining('System Settings'), findsNothing);
  });

  testWidgets('an unavailable login item explains itself but stays usable',
      (tester) async {
    // "The OS would not say" must not become "you may not try". This row was
    // once disabled for any status we could not name, and .notFound — which is
    // simply "not registered yet" — landed there, so a fresh install could
    // never switch launch-at-login on at all. setLoginItem returns the status
    // *after* the attempt, so letting it through costs nothing: a refusal just
    // leaves the box unticked.
    var attempts = 0;
    await tester.pumpWidget(host(
      loginStatus: LoginItemStatus.unavailable,
      onSetLoginItem: (_) => attempts++,
    ));

    final box = tester.widget<Checkbox>(find.descendant(
      of: find
          .ancestor(
              of: find.text('Launch at login'), matching: find.byType(Row))
          .first,
      matching: find.byType(Checkbox),
    ));
    expect(box.value, isFalse, reason: 'must never render as on');
    expect(find.textContaining('does not recognise'), findsOneWidget);

    await tester.tap(find.text('Launch at login'));
    await tester.pumpAndSettle();
    expect(attempts, 1, reason: 'the user must be able to try');
  });

  testWidgets('a working login item shows no warning', (tester) async {
    await tester.pumpWidget(host(loginStatus: LoginItemStatus.enabled));
    expect(find.textContaining('does not recognise'), findsNothing);
    expect(find.textContaining('System Settings'), findsNothing);
  });

  testWidgets('each tab resets only what it shows', (tester) async {
    // "Reset to Defaults" at the foot of General read as "everything" while
    // touching neither the shortcuts nor launch-at-login. Two buttons, each
    // named for its own tab, and neither reaches across.
    final changes = <Settings>[];
    var bindingResets = 0;
    await tester.pumpWidget(host(
      settings: const Settings(gridCols: 10, gridRows: 4, gaps: true),
      onSettingsChanged: changes.add,
      onResetBindings: () => bindingResets++,
    ));

    expect(find.text('Reset to Defaults'), findsNothing);
    await tester.tap(find.text('Reset Grid & Gaps'));
    await tester.pumpAndSettle();
    expect(changes.single, const Settings());
    expect(bindingResets, 0, reason: 'General must not touch the shortcuts');

    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Shortcuts'));
    await tester.pumpAndSettle();
    expect(bindingResets, 1);
    expect(changes.length, 1, reason: 'Shortcuts must not touch the settings');
  });

  testWidgets('Reset Shortcuts stays hidden while a combo is being recorded',
      (tester) async {
    // Otherwise the click meant for a row could land on a button that throws
    // away every binding — with the hotkeys already unregistered for capture.
    await tester.pumpWidget(host(onResetBindings: () {}));
    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('Reset Shortcuts'), findsOneWidget);

    await tester.tap(find.text('Left half'));
    await tester.pumpAndSettle();
    expect(find.text('Reset Shortcuts'), findsNothing);
  });
}
