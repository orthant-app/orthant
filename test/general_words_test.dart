import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/general_pane.dart';
import 'package:orthant/settings/mac_stepper.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/shortcuts/bindings.dart';

/// The General pane in each platform's words: the permission it shows (macOS
/// has one, Windows none), where the OS keeps the startup entry, and what a
/// gap is counted in. macOS's are pinned byte for byte, as 1.0.x shows them.
void main() {
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  late int openedLoginItems;

  /// What a screen reader hears for the gap's stepper.
  String gapLabel(WidgetTester tester) => tester
      .widgetList<MacStepper>(find.byType(MacStepper))
      .map((s) => s.semanticLabel)
      .singleWhere((l) => l.startsWith('Size'));

  Future<void> pumpPane(WidgetTester tester, LoginItemStatus status,
      {bool granted = true}) async {
    openedLoginItems = 0;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: orthantTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          width: 560,
          height: 860,
          child: GeneralPane(
            settings: const Settings(),
            onSettingsChanged: (_) {},
            permissionGranted: granted,
            loginStatus: status,
            bindings: runningDefaults(),
            onOpenLoginItems: () => openedLoginItems++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('macOS, as 1.0.x', () {
    testWidgets('shows the Accessibility grant', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled);
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Granted'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(3));
      await pumpPane(tester, LoginItemStatus.disabled, granted: false);
      expect(find.text('Not granted. Shortcuts and the grid do nothing'),
          findsOneWidget);
    }, variant: macOS);

    testWidgets('names Login Items', (tester) async {
      await pumpPane(tester, LoginItemStatus.unavailable);
      expect(
          find.text('macOS reported a login-item state Orthant does not '
              'recognise. Switching this on may still work.'),
          findsOneWidget);
      await pumpPane(tester, LoginItemStatus.requiresApproval);
      expect(
          find.text('Turned off in System Settings ▸ General ▸ Login Items, '
              'so Orthant will not start automatically.'),
          findsOneWidget);
      await tester.tap(find.text('Open Login Items…'));
      expect(openedLoginItems, 1);
    }, variant: macOS);

    testWidgets('counts a gap in points', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled);
      expect(find.text('pt'), findsOneWidget);
      expect(gapLabel(tester), 'Size 8 pt');
    }, variant: macOS);
  });

  group('Windows', () {
    testWidgets('has no grant to show', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled);
      expect(find.text('Accessibility'), findsNothing);
      expect(find.text('Granted'), findsNothing);
      expect(find.byType(Divider), findsNWidgets(2),
          reason: 'its hairline goes with it');
      // Even if a caller passed false, there is nothing on Windows to grant.
      await pumpPane(tester, LoginItemStatus.disabled, granted: false);
      expect(find.textContaining('granted'), findsNothing);
      expect(find.text('Open Accessibility Settings…'), findsNothing);
    }, variant: windows);

    testWidgets('names Settings and its Startup apps page', (tester) async {
      await pumpPane(tester, LoginItemStatus.unavailable);
      expect(
          find.text('Windows reported a startup state Orthant does not '
              'recognise. Switching this on may still work.'),
          findsOneWidget);
      await pumpPane(tester, LoginItemStatus.requiresApproval);
      expect(
          find.text('Turned off in Settings ▸ Apps ▸ Startup, so Orthant '
              'will not start automatically.'),
          findsOneWidget);
      expect(find.textContaining('macOS'), findsNothing);
      expect(find.textContaining('Login Items'), findsNothing);
      await tester.tap(find.text('Open Startup Apps…'));
      expect(openedLoginItems, 1);
    }, variant: windows);

    testWidgets('counts a gap in pixels', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled);
      expect(find.text('px'), findsOneWidget);
      expect(find.text('pt'), findsNothing);
      expect(gapLabel(tester), 'Size 8 px');
    }, variant: windows);

    testWidgets('the startup checkbox is the same control', (tester) async {
      await pumpPane(tester, LoginItemStatus.enabled);
      expect(find.text('Launch at login'), findsOneWidget);
    }, variant: windows);
  });
}
