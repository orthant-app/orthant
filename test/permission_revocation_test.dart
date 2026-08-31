import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/permission_controller.dart';

class _FakeWc implements WindowController {
  bool permission = false;

  @override
  Future<bool> checkPermission() async => permission;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openAccessibilitySettings() async {}
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
  test('refresh detects revocation after a grant (granted -> denied)', () async {
    final wc = _FakeWc()..permission = true;
    final c = PermissionController(wc);
    final seen = <PermissionStatus>[];
    c.addListener(() => seen.add(c.status));

    await c.refresh();
    expect(c.granted, isTrue);

    // The user turns Accessibility off in System Settings.
    wc.permission = false;
    await c.refresh();

    expect(c.granted, isFalse);
    expect(c.status, PermissionStatus.denied);
    expect(seen, [PermissionStatus.granted, PermissionStatus.denied]);
  });

  test('re-granting after a revocation is detected too', () async {
    final wc = _FakeWc()..permission = true;
    final c = PermissionController(wc);
    await c.refresh();

    wc.permission = false;
    await c.refresh();
    expect(c.granted, isFalse);

    wc.permission = true;
    await c.refresh();
    expect(c.granted, isTrue);
  });
}
