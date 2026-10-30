import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/l10n/strings.dart';
import 'package:orthant/settings/general_pane.dart';
import 'package:orthant/settings/mac_stepper.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/shortcuts/bindings.dart';

import 'support/locales.dart';
import 'support/localized_host.dart';
import 'support/no_english.dart';

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

  /// [loginItemsHasExtensions] is pinned false: the sentences asserted below
  /// were written against macOS 13 and 14's "Login Items", which they keep.
  Future<void> pumpPane(WidgetTester tester, LoginItemStatus status,
      {bool granted = true,
      Settings settings = const Settings(),
      bool loginItemsHasExtensions = false,
      bool summonUnavailable = false,
      Locale? locale}) async {
    openedLoginItems = 0;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pane = SizedBox(
      width: 560,
      height: 860,
      child: GeneralPane(
        settings: settings,
        onSettingsChanged: (_) {},
        permissionGranted: granted,
        loginStatus: status,
        loginItemsHasExtensions: loginItemsHasExtensions,
        summonUnavailable: summonUnavailable,
        bindings: runningDefaults(),
        onOpenLoginItems: () => openedLoginItems++,
      ),
    );
    await tester.pumpWidget(locale != null
        ? localizedApp(locale, pane)
        : MaterialApp(
            theme: orthantTheme(Brightness.light),
            home: Scaffold(body: pane),
          ));
    await tester.pumpAndSettle();
  }

  group('macOS, as 1.0.x', () {
    testWidgets('shows the Accessibility grant', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled);
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Granted'), findsOneWidget);
      // Five groups with a hairline between each pair; the Language group
      // is the fifth, and made it four.
      expect(find.byType(Divider), findsNWidgets(4));
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

    testWidgets('the preview counts its gaps in points', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled,
          settings: const Settings(gaps: true));
      expect(find.text('6 × 6 · up to 8 pt gaps'), findsOneWidget);
    }, variant: macOS);
  });

  group('Windows', () {
    testWidgets('has no grant to show', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled);
      expect(find.text('Accessibility'), findsNothing);
      expect(find.text('Granted'), findsNothing);
      expect(find.byType(Divider), findsNWidgets(3),
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

    testWidgets('the preview counts its gaps in pixels too', (tester) async {
      await pumpPane(tester, LoginItemStatus.disabled,
          settings: const Settings(gaps: true));
      expect(find.text('6 × 6 · up to 8 px gaps'), findsOneWidget);
      // find.text('pt') matches whole strings only; this sees "pt" inside any
      // caption or label in the pane.
      expect(find.textContaining(RegExp(r'\bpt\b')), findsNothing);
    }, variant: windows);

    testWidgets('the startup checkbox is the same control', (tester) async {
      await pumpPane(tester, LoginItemStatus.enabled);
      expect(find.text('Launch at login'), findsOneWidget);
    }, variant: windows);
  });

  group('macOS 15 and later: Login Items & Extensions', () {
    testWidgets('the requires-approval text and button name the new pane',
        (tester) async {
      await pumpPane(tester, LoginItemStatus.requiresApproval,
          loginItemsHasExtensions: true);
      expect(
          find.text('Turned off in System Settings ▸ General ▸ Login Items & '
              'Extensions, so Orthant will not start automatically.'),
          findsOneWidget);
      expect(find.text('Open Login Items…'), findsNothing);
      await tester.tap(find.text('Open Login Items & Extensions…'));
      expect(openedLoginItems, 1);
    }, variant: macOS);

    testWidgets('a pane built without the flag assumes the newer macOS',
        (tester) async {
      // The default is what a build that cannot read its macOS version gets.
      await tester.pumpWidget(MaterialApp(
        theme: orthantTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 560,
            height: 860,
            child: GeneralPane(
              settings: const Settings(),
              onSettingsChanged: (_) {},
              permissionGranted: true,
              loginStatus: LoginItemStatus.requiresApproval,
              bindings: runningDefaults(),
            ),
          ),
        ),
      ));
      expect(find.text('Open Login Items & Extensions…'), findsOneWidget);
    }, variant: macOS);

    testWidgets('Windows does not care which macOS it is not running',
        (tester) async {
      for (final flag in [true, false]) {
        await pumpPane(tester, LoginItemStatus.requiresApproval,
            loginItemsHasExtensions: flag);
        expect(find.text('Open Startup Apps…'), findsOneWidget);
        expect(find.textContaining('Login Items'), findsNothing);
      }
    }, variant: windows);
  });

  group('in Chinese', () {
    tearDown(() => setAppStrings(kEnglish));

    // The sentence that names an OS screen is one whole message per platform
    // and per macOS version, in the OS's own Chinese names (Apple's: research
    // Part B 5.2; Windows' are drafts, confirmed on the VM in Task 15).
    final turnedOff = {
      (kSimplified, TargetPlatform.macOS, false):
          ('已在“系统设置 ▸ 通用 ▸ 登录项”中关闭，因此 Orthant 不会自动启动。', '打开登录项…'),
      (kSimplified, TargetPlatform.macOS, true):
          ('已在“系统设置 ▸ 通用 ▸ 登录项与扩展”中关闭，因此 Orthant 不会自动启动。', '打开登录项与扩展…'),
      (kSimplified, TargetPlatform.windows, true):
          ('已在“设置 ▸ 应用 ▸ 启动”中关闭，因此 Orthant 不会自动启动。', '打开启动应用…'),
      (kTraditional, TargetPlatform.macOS, false):
          ('已在「系統設定 ▸ 一般 ▸ 登入項目」中關閉，因此 Orthant 不會自動啟動。', '開啟登入項目⋯'),
      (kTraditional, TargetPlatform.macOS, true): (
        '已在「系統設定 ▸ 一般 ▸ 登入項目與延伸功能」中關閉，因此 Orthant 不會自動啟動。',
        '開啟登入項目與延伸功能⋯'
      ),
      (kTraditional, TargetPlatform.windows, true):
          ('已在「設定 ▸ 應用程式 ▸ 啟動」中關閉，因此 Orthant 不會自動啟動。', '開啟啟動應用程式⋯'),
    };

    for (final entry in turnedOff.entries) {
      final (locale, platform, extensions) = entry.key;
      final (sentence, button) = entry.value;
      testWidgets(
          '${locale.toLanguageTag()} on $platform '
          '(extensions: $extensions): the OS screen is named whole',
          (tester) async {
        setAppStrings(locale);
        await pumpPane(tester, LoginItemStatus.requiresApproval,
            loginItemsHasExtensions: extensions, locale: locale);
        expect(find.text(sentence), findsOneWidget);
        await tester.tap(find.text(button));
        expect(openedLoginItems, 1);
      }, variant: TargetPlatformVariant.only(platform));
    }

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        for (final status in [
          LoginItemStatus.unavailable,
          LoginItemStatus.requiresApproval,
        ]) {
          testWidgets(
              '${locale.toLanguageTag()} on $platform, $status: no English '
              'is left, semantics included', (tester) async {
            setAppStrings(locale);
            await pumpPane(tester, status,
                granted: false,
                settings: const Settings(gaps: true, gapSize: 8),
                loginItemsHasExtensions: true,
                summonUnavailable: true,
                locale: locale);
            expectNoEnglish(tester);
          }, variant: TargetPlatformVariant.only(platform));
        }
      }

      testWidgets('${locale.toLanguageTag()}: granted, and a gap in points',
          (tester) async {
        setAppStrings(locale);
        await pumpPane(tester, LoginItemStatus.enabled,
            settings: const Settings(gaps: true, gapSize: 8), locale: locale);
        expectNoEnglish(tester);
        expect(find.text('pt'), findsOneWidget, reason: 'a unit, not a word');
      }, variant: macOS);
    }

    testWidgets('the refused-chord warning names the OS and is Chinese',
        (tester) async {
      setAppStrings(kSimplified);
      await pumpPane(tester, LoginItemStatus.disabled,
          summonUnavailable: true, locale: kSimplified);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
          'macOS 或其他应用已使用此组合键，因此 Orthant 收不到它。');
    }, variant: macOS);

    testWidgets('a stepper announces its caption, value and unit as one '
        'message', (tester) async {
      setAppStrings(kSimplified);
      await pumpPane(tester, LoginItemStatus.disabled, locale: kSimplified);
      expect(
          tester
              .widgetList<MacStepper>(find.byType(MacStepper))
              .map((s) => s.semanticLabel),
          ['列数 6', '行数 6', '大小 8 pt']);
    }, variant: macOS);
  });
}
