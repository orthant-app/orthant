import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/permission_controller.dart';

class _FakeWc implements WindowController {
  bool permission = false;
  final calls = <String>[];

  @override
  Future<bool> checkPermission() async => permission;
  @override
  Future<void> requestPermission() async => calls.add('request');
  @override
  Future<void> openAccessibilitySettings() async {
    calls.add('openSettings');
  }
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
  Future<Map<int, String>> keyboardLabels() async => const {};

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
  test('refresh reflects the underlying permission and notifies on change',
      () async {
    final wc = _FakeWc()..permission = false;
    final c = PermissionController(wc);
    var notifications = 0;
    c.addListener(() => notifications++);

    await c.refresh();
    expect(c.status, PermissionStatus.denied);
    expect(c.granted, isFalse);
    expect(notifications, 1);

    wc.permission = true;
    await c.refresh();
    expect(c.granted, isTrue);
    expect(notifications, 2);

    await c.refresh(); // no change -> no extra notification
    expect(notifications, 2);
  });

  test('openSettings only deep-links — no second prompt for one click',
      () async {
    // It used to request *and* deep-link, so one click put macOS's "…would
    // like to control this computer" dialog on screen with the pane behind it.
    // The dialog has its own "Open System Settings" button, so ours was asking
    // the same question twice.
    final wc = _FakeWc();
    await PermissionController(wc).openSettings();
    expect(wc.calls, ['openSettings']);
  });

  test('register is what creates the row, and is separate', () async {
    // AXIsProcessTrustedWithOptions is what puts Orthant in the Accessibility
    // list at all. Split out so it can happen once at launch rather than
    // behind the button.
    final wc = _FakeWc();
    await PermissionController(wc).register();
    expect(wc.calls, ['request']);
  });

}
