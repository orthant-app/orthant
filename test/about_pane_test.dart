import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/about_pane.dart';
import 'package:orthant/settings/platform_theme.dart';

import 'support/locales.dart';
import 'support/localized_host.dart';
import 'support/no_english.dart';

void main() {
  Widget host(
    AppVersion version, {
    VoidCallback? onCheckForUpdates,
    String? availableUpdate,
    bool automaticChecks = true,
    void Function(bool)? onAutomaticChecksChanged,
  }) =>
      MaterialApp(
        theme: orthantTheme(Brightness.light),
        home: Scaffold(
          body: AboutPane(
            version: version,
            onCheckForUpdates: onCheckForUpdates,
            availableUpdate: availableUpdate,
            automaticChecks: automaticChecks,
            onAutomaticChecksChanged: onAutomaticChecksChanged,
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


    testWidgets('an update a check found is named, with a button that opens '
        'the updater as Check for Updates does; with none, neither shows',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(const AppVersion('1.0.3', '7'),
          onCheckForUpdates: () => calls++, availableUpdate: '1.0.4'));
      expect(find.text('Orthant 1.0.4 is available.'), findsOneWidget);
      await tester.tap(find.text('Update…'));
      await tester.pump();
      expect(calls, 1);

      await tester.pumpWidget(host(const AppVersion('1.0.3', '7'),
          onCheckForUpdates: () => calls++));
      expect(find.textContaining('is available'), findsNothing);
      expect(find.text('Update…'), findsNothing);
      expect(find.text('Check for Updates…'), findsOneWidget);
    });

    testWidgets('the automatic-check state is offered, and reflects what it is '
        'given', (tester) async {
      const label = 'Check for updates automatically';
      await tester.pumpWidget(
        host(const AppVersion('1.0.0', '4'), automaticChecks: true),
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.pumpWidget(
        host(const AppVersion('1.0.0', '4'), automaticChecks: false),
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('toggling asks for the opposite of what is shown',
        (tester) async {
      final asked = <bool>[];
      await tester.pumpWidget(host(
        const AppVersion('1.0.0', '4'),
        automaticChecks: true,
        onAutomaticChecksChanged: asked.add,
      ));
      await tester.tap(find.text('Check for updates automatically'));
      await tester.pump();
      expect(asked, [false]);
    });

    testWidgets('the checkbox shows the updater, not the click', (tester) async {
      // The property that matters and the reason nothing here calls setState:
      // the pane renders `automaticChecks` as given. If the updater refuses the
      // change, the prop comes back unchanged and the box must stay where it
      // was rather than following the click. A locally-toggled checkbox would
      // claim a state the updater never entered.
      var accepted = true;
      await tester.pumpWidget(host(
        const AppVersion('1.0.0', '4'),
        automaticChecks: accepted,
        onAutomaticChecksChanged: (_) {}, // refuses: never changes `accepted`
      ));
      await tester.tap(find.text('Check for updates automatically'));
      await tester.pump();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).value,
        isTrue,
        reason: 'still on, because the updater never said otherwise',
      );
      expect(accepted, isTrue);
    });

    testWidgets('a null callback makes the checkbox read-only', (tester) async {
      await tester.pumpWidget(host(const AppVersion('1.0.0', '4')));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
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

  group('AboutPane in Chinese', () {
    const words = {
      'zh': (
        version: '版本 1.0.0 (2)',
        available: '有可用的新版本 Orthant 1.0.4。',
        update: '更新…',
        check: '检查更新…',
        automatic: '自动检查更新',
        tagline: '基于网格的窗口管理工具。',
      ),
      'zh-Hant': (
        version: '版本 1.0.0 (2)',
        available: '有可用的新版本 Orthant 1.0.4。',
        update: '更新…',
        check: '檢查更新…',
        automatic: '自動檢查更新',
        tagline: '以格線為基礎的視窗管理工具。',
      ),
    };

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      final w = words[locale == kSimplified ? 'zh' : 'zh-Hant']!;

      testWidgets('${locale.toLanguageTag()}: every line is in the language, '
          'with an update offered', (tester) async {
        await tester.pumpWidget(localizedApp(
          locale,
          AboutPane(
            version: const AppVersion('1.0.0', '2'),
            onCheckForUpdates: () {},
            availableUpdate: '1.0.4',
          ),
        ));
        expect(find.text('Orthant'), findsOneWidget);
        expect(find.text(w.version), findsOneWidget);
        expect(find.text(w.available), findsOneWidget);
        expect(find.text(w.update), findsOneWidget);
        expect(find.text(w.check), findsOneWidget);
        expect(find.text(w.automatic), findsOneWidget);
        expect(find.text(w.tagline), findsOneWidget);
        expectNoEnglish(tester);
      },
          variant: const TargetPlatformVariant({
            TargetPlatform.macOS,
            TargetPlatform.windows,
          }));
    }

    testWidgets('the buttons still work in Chinese', (tester) async {
      var calls = 0;
      await tester.pumpWidget(localizedApp(
        kSimplified,
        AboutPane(
          version: const AppVersion('1.0.0', '2'),
          onCheckForUpdates: () => calls++,
          availableUpdate: '1.0.4',
        ),
      ));
      await tester.tap(find.text('更新…'));
      await tester.tap(find.text('检查更新…'));
      expect(calls, 2);
    });
  });
}
