import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/permission_controller.dart';
import 'package:orthant/permission/onboarding_screen.dart';

class _FakeWc implements WindowController {
  int openSettingsCalls = 0;
  @override
  Future<bool> checkPermission() async => false;
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
}
