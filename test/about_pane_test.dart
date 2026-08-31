import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/about_pane.dart';
import 'package:orthant/settings/mac_theme.dart';

void main() {
  Widget host(AppVersion version, {VoidCallback? onCheckForUpdates}) =>
      MaterialApp(
        theme: macTheme(Brightness.light),
        home: Scaffold(
          body: AboutPane(
            version: version,
            onCheckForUpdates: onCheckForUpdates,
          ),
        ),
      );

  group('AboutPane', () {
    testWidgets('renders the version in the macOS form', (tester) async {
      await tester.pumpWidget(host(const AppVersion('1.0.0', '2')));

      // The rendered string is the deliverable, not the fact that a value was
      // passed. `Version 1.0.0 (2)` is what Finder's Get Info and Sparkle's own
      // update prompt both use, so the app and its updater agree.
      expect(find.text('Version 1.0.0 (2)'), findsOneWidget);
      expect(find.text('Orthant'), findsOneWidget);
    });

    testWidgets('shows the build number, not just the marketing version',
        (tester) async {
      // The whole reason both halves cross the seam. CFBundleShortVersionString
      // is three integers by Apple's rule, so it stays "1.0.0" across an entire
      // beta line and cannot distinguish beta.1 from beta.2. The build number
      // is the part that moves, and the part Sparkle compares.
      await tester.pumpWidget(host(const AppVersion('1.0.0', '7')));
      expect(find.text('Version 1.0.0 (7)'), findsOneWidget);

      await tester.pumpWidget(host(const AppVersion('1.0.0', '8')));
      expect(find.text('Version 1.0.0 (8)'), findsOneWidget);
    });

    testWidgets('a released build shows its release name, label and all',
        (tester) async {
      // What a bug report should be able to quote verbatim. The build number is
      // deliberately absent here: the release name already identifies the build
      // uniquely, and "(5)" was the part users could not interpret.
      await tester.pumpWidget(
        host(const AppVersion('1.0.0', '5', releaseName: '1.0.1-beta.2')),
      );
      expect(find.text('Version 1.0.1-beta.2'), findsOneWidget);
      expect(find.textContaining('(5)'), findsNothing);
    });

    testWidgets('a version the platform could not supply renders no version '
        'line, and does not throw', (tester) async {
      // This repo has shipped a build-time throw twice, and in Release that is
      // an ErrorWidget with no text — a featureless grey box, not a crash. The
      // pane must survive a missing value with the rest of it intact.
      await tester.pumpWidget(host(const AppVersion('', '')));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Version'), findsNothing);
      expect(find.text('Orthant'), findsOneWidget,
          reason: 'the rest of the pane still stands');
      expect(find.text('Check for Updates…'), findsOneWidget);
    });

    testWidgets('the update button calls back', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        host(const AppVersion('1.0.0', '2'), onCheckForUpdates: () => calls++),
      );

      await tester.tap(find.text('Check for Updates…'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('the pane scrolls, so a short window cannot strand the button',
        (tester) async {
      // The window is user-resizable down to a 500 pt content height and the
      // pane is vertically centred. Without a scroll view a short window would
      // clip the one action this pane offers — the exact failure the General
      // pane's pinned footer exists to prevent.
      tester.view.physicalSize = const Size(560, 260);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(const AppVersion('1.0.0', '2')));

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
