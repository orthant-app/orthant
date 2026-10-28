import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/permission_controller.dart';
import 'package:orthant/permission/onboarding_screen.dart';

import 'support/locales.dart';
import 'support/localized_host.dart';
import 'support/no_english.dart';

class _FakeWc implements WindowController {
  int openSettingsCalls = 0;
  bool granted = false;
  @override
  Future<bool> checkPermission() async => granted;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openAccessibilitySettings() async => openSettingsCalls++;
  @override
  Future<void> showConfigWindow() async {}
  @override
  Future<void> hideConfigWindow() async {}
  @override
  Future<CapturedWindow?> captureFrontmost() async => null;
  @override
  Future<Display?> activeScreenFrame() async => null;
  @override
  Future<List<Display>> screenFrames() async => const [];
  @override
  Future<bool> applyFrame(WinRect target) async => false;
  @override
  Future<bool> applyOverlayCommit(int sessionId, WinRect target) async => false;
  @override
  Future<void> showOverlay({double? pressedAtMs}) async {}
  @override
  Future<void> hideOverlay() async {}
  @override
  Future<void> startOverlay() async {}
  @override
  Future<void> setCommandsRunning(bool running) async {}
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
    required String locale,
  }) async {}
  // Launch-at-login is not what any of these tests exercise; the seam just
  // requires an answer. `unavailable` is the honest default for a fake.
  @override
  Future<Map<int, String>> keyboardLabels() async => const {};
  @override
  Future<AccentColors?> accentColor() async => null;

  @override
  Future<List<Locale>> systemLocales() async => const [];
  @override
  Future<String?> languageOverride() async => null;
  @override
  Future<void> setLanguageOverride(String? tag) async {}

  @override
  Future<AppVersion> appVersion() async => const AppVersion('1.0.0', '1');

  @override
  Future<bool> automaticUpdateChecks() async => true;

  @override
  Future<bool> setAutomaticUpdateChecks(bool enabled) async => enabled;

  @override
  Future<LoginItemStatus> loginItemStatus() async => LoginItemStatus.unavailable;
  @override
  Future<LoginItemStatus> setLoginItem(bool enabled) async =>
      LoginItemStatus.unavailable;
  @override
  Future<void> openLoginItemsSettings() async {}
  @override
  Future<void> checkForUpdates() async {}
  @override
  final ValueNotifier<AvailableUpdate?> availableUpdate = ValueNotifier(null);
}

void main() {
  testWidgets('reports its first frame, which reveals the window', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel(kOrthantChannel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(controller: PermissionController(_FakeWc()))));
    await tester.pump();
    expect(calls, ['configFirstFrame']);
  });

  testWidgets('on macOS it leaves its reveal to the fallback', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel(kOrthantChannel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(controller: PermissionController(_FakeWc()))));
    await tester.pump();
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('on Windows it reports its first frame', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel(kOrthantChannel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(controller: PermissionController(_FakeWc()))));
    await tester.pump();
    expect(calls, ['configFirstFrame']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('shows explainer and the button opens settings', (tester) async {
    final wc = _FakeWc();
    final c = PermissionController(wc);
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(controller: c)));

    expect(find.textContaining('Accessibility'), findsWidgets);
    await tester.tap(find.text('Open Accessibility Settings'));
    await tester.pump();

    expect(wc.openSettingsCalls, 1);
  });

  testWidgets('on macOS the button is white on the accent, as it always was',
      (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: orthantTheme(b),
        home: OnboardingScreen(controller: PermissionController(_FakeWc())),
      ));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style!.foregroundColor!.resolve({}),
          const Color(0xFFFFFFFF), reason: '$b');
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  group('in the app\'s language', () {
    // The English the screen has always shown, word for word: what the screen
    // reads from the generated strings must come out as what it hard-coded.
    testWidgets('English is exactly what it was', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(controller: PermissionController(_FakeWc()))));
      expect(find.text('Orthant needs Accessibility permission'), findsOneWidget);
      expect(
          find.text('Orthant moves your windows using macOS Accessibility. '
              'Enable “Orthant” under Privacy & Security ▸ Accessibility '
              'and Orthant will pick it up straight away.'),
          findsOneWidget);
      expect(find.text('Open Accessibility Settings'), findsOneWidget);
      expect(find.text('Waiting for permission…'), findsOneWidget);
    });

    testWidgets('English says the permission is granted', (tester) async {
      final wc = _FakeWc()..granted = true;
      final c = PermissionController(wc);
      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(controller: c)));
      await c.refresh();
      await tester.pump();
      expect(find.text('Permission granted'), findsOneWidget);
      expect(find.text('Waiting for permission…'), findsNothing);
    });

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      for (final granted in [false, true]) {
        testWidgets(
            '${locale.toLanguageTag()}, ${granted ? 'granted' : 'waiting'}: '
            'no English is left, semantics included', (tester) async {
          final wc = _FakeWc()..granted = granted;
          final c = PermissionController(wc);
          await tester.pumpWidget(localizedApp(
              locale, OnboardingScreen(controller: c)));
          await c.refresh();
          await tester.pump();
          expectNoEnglish(tester);
        });
      }
    }

    // The instruction names a screen of the operating system, so it is one
    // whole message per language and each language copies Apple's own words;
    // Hong Kong's macOS calls the pane something else than Taiwan's.
    Future<void> pumpIn(WidgetTester tester, Locale locale) => tester.pumpWidget(
        localizedApp(locale, OnboardingScreen(controller: PermissionController(_FakeWc()))));

    testWidgets('Simplified Chinese names the panes as macOS does',
        (tester) async {
      await pumpIn(tester, kSimplified);
      expect(find.textContaining('隐私与安全性 ▸ 辅助功能'), findsOneWidget);
    });

    testWidgets('Traditional Chinese names the panes as Taiwan\'s macOS does',
        (tester) async {
      await pumpIn(tester, kTraditional);
      expect(find.textContaining('隱私權與安全性 ▸ 輔助使用'), findsOneWidget);
      expect(find.textContaining('私隱與保安'), findsNothing);
    });

    testWidgets('Hong Kong names the privacy pane as its own macOS does',
        (tester) async {
      await pumpIn(tester, kHongKong);
      expect(find.textContaining('私隱與保安 ▸ 輔助使用'), findsOneWidget);
      expect(find.textContaining('隱私權與安全性'), findsNothing);
    });

    // macOS 27 renamed the pane that lists the apps allowed to control the
    // Mac, from Accessibility to Device Control and Data Access, so the
    // instruction is a second whole message chosen by the host. The first stays
    // as macOS 13 to 26 print it.
    testWidgets('English on macOS 27 and later names the renamed pane',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: OnboardingScreen(
              controller: PermissionController(_FakeWc()),
              privacyListIsDeviceControl: true)));
      expect(
          find.text('Orthant moves your windows using macOS Accessibility. '
              'Enable “Orthant” under Privacy & Security ▸ Device Control '
              'and Data Access and Orthant will pick it up straight away.'),
          findsOneWidget);
      expect(find.textContaining('▸ Accessibility'), findsNothing);
    });

    testWidgets('without the flag the pane is the one macOS 13 to 26 print',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: OnboardingScreen(controller: PermissionController(_FakeWc()))));
      expect(find.textContaining('▸ Accessibility'), findsOneWidget);
      expect(find.textContaining('Device Control'), findsNothing);
    });

    const mac27 = {
      'zh': ('设备控制和数据访问', '隐私与安全 ▸ ', '辅助功能'),
      'zh-Hant': ('裝置控制和資料取用', '隱私權與安全性 ▸ ', '輔助使用'),
      'zh-Hant-HK': ('裝置控制和資料取用權限', '私隱與保安 ▸ ', '輔助使用'),
    };
    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      final (pane, parent, older) = mac27[locale.toLanguageTag()]!;
      testWidgets('${locale.toLanguageTag()} on macOS 27 and later names '
          '$parent$pane, with no English left', (tester) async {
        await tester.pumpWidget(localizedApp(
            locale,
            OnboardingScreen(
                controller: PermissionController(_FakeWc()),
                privacyListIsDeviceControl: true)));
        expect(find.textContaining('$parent$pane'), findsOneWidget);
        expect(find.textContaining('$parent$older'), findsNothing);
        expectNoEnglish(tester);
      });
    }

    testWidgets('the button still opens the pane when it is in Chinese',
        (tester) async {
      final wc = _FakeWc();
      await tester.pumpWidget(localizedApp(
          kSimplified, OnboardingScreen(controller: PermissionController(wc))));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(wc.openSettingsCalls, 1);
    });
  });
}
