import 'geometry.dart';
import 'window_controller.dart';

/// The Windows backend of the seam. Filled in by Task 6 of the W0 plan.
class WindowsWindowController implements WindowController {
  WindowsWindowController._();

  static WindowsWindowController start() => WindowsWindowController._();

  @override
  Future<bool> checkPermission() => throw UnimplementedError();
  @override
  Future<void> requestPermission() => throw UnimplementedError();
  @override
  Future<CapturedWindow?> captureFrontmost() => throw UnimplementedError();
  @override
  Future<WinRect> activeScreenFrame() => throw UnimplementedError();
  @override
  Future<List<WinRect>> screenFrames() => throw UnimplementedError();
  @override
  Future<bool> applyFrame(WinRect target) => throw UnimplementedError();
  @override
  Future<void> openAccessibilitySettings() => throw UnimplementedError();
  @override
  Future<void> showConfigWindow() => throw UnimplementedError();
  @override
  Future<void> hideConfigWindow() => throw UnimplementedError();
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> showOverlay() => throw UnimplementedError();
  @override
  Future<void> hideOverlay() => throw UnimplementedError();
  @override
  Future<AppVersion> appVersion() => throw UnimplementedError();
  @override
  Future<Map<int, String>> keyboardLabels() => throw UnimplementedError();
  @override
  Future<LoginItemStatus> loginItemStatus() => throw UnimplementedError();
  @override
  Future<LoginItemStatus> setLoginItem(bool enabled) =>
      throw UnimplementedError();
  @override
  Future<void> openLoginItemsSettings() => throw UnimplementedError();
  @override
  Future<bool> automaticUpdateChecks() => throw UnimplementedError();
  @override
  Future<bool> setAutomaticUpdateChecks(bool enabled) =>
      throw UnimplementedError();
  @override
  Future<void> checkForUpdates() => throw UnimplementedError();
}
