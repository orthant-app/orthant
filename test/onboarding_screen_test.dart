import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<WinRect> activeScreenFrame() async => const WinRect(0, 0, 0, 0);
  @override
  Future<List<WinRect>> screenFrames() async => const [];
  @override
  Future<bool> applyFrame(WinRect target) async => false;
  @override
  Future<void> showOverlay() async {}
  @override
  Future<void> hideOverlay() async {}
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) async {}
  // Launch-at-login is not what any of these tests exercise; the seam just
  // requires an answer. `unavailable` is the honest default for a fake.
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
}

void main() {
  testWidgets('shows explainer and the button opens settings', (tester) async {
    final wc = _FakeWc();
    final c = PermissionController(wc);
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(controller: c)));

    expect(find.textContaining('Accessibility'), findsWidgets);
    await tester.tap(find.text('Open Accessibility Settings'));
    await tester.pump();

    expect(wc.openSettingsCalls, 1);
  });
}
