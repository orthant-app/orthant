import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'channel.dart';
import 'geometry.dart';
import 'window_controller.dart';
import 'windows_version_resource.dart';

/// The Windows backend of the seam.
///
/// Design: `.claude/docs/superpowers/specs/2026-09-18-windows-port-design.md`
/// §5. Everything stateless is `dart:ffi` via `package:win32`, in this file
/// or beside it. C++ in `windows/runner/` holds only what needs a window
/// handle, the message loop or a Flutter engine, and is reached over the same
/// `app.orthant/window` channel macOS uses (`windows/runner/window_channel.cpp`
/// is the handler). In W0 that is the config window and nothing else; every
/// other method below is a stub that names the milestone replacing it, and
/// **no stub may call the channel**: the C++ side answers `NotImplemented`
/// for anything it does not handle yet, which surfaces here as
/// `MissingPluginException`, and several of these run on the launch path.
class WindowsWindowController implements WindowController {
  WindowsWindowController._(this._readVersion);

  /// The one way to obtain the controller in production.
  ///
  /// W6 initialises WinSparkle here, before returning, so the updater runs
  /// from `main()` and never waits for Settings to open. macOS shipped three
  /// releases that never checked for updates on their own because its updater
  /// was a lazy static nothing read until the settings window did (spec §5.6).
  static WindowsWindowController start() =>
      WindowsWindowController._(readFixedFileVersion);

  /// The same controller with the version supplied, for a suite that runs on
  /// a Mac where `version.dll` does not exist. Nothing else differs.
  @visibleForTesting
  factory WindowsWindowController.forTest(
          {required VersionReader readVersion}) =>
      WindowsWindowController._(readVersion);

  final VersionReader _readVersion;

  static const MethodChannel _channel = MethodChannel(kOrthantChannel);

  // Permission. Windows needs no grant to move an ordinary window (spec §2.1);
  // elevated windows are a placement failure, not a permission (§7.4).
  @override
  Future<bool> checkPermission() async => true;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openAccessibilitySettings() async {}

  // The config window is the runner's own top-level window (spec §5.5).
  @override
  Future<void> showConfigWindow() =>
      _channel.invokeMethod<void>(kShowConfigWindow);
  @override
  Future<void> hideConfigWindow() =>
      _channel.invokeMethod<void>(kHideConfigWindow);

  // Read from the exe's version resource, which CMake fills from pubspec.yaml,
  // never from a Dart constant: those drift from what shipped. A release name
  // (the tag's own name, W6) is not stamped yet, so it is empty.
  @override
  Future<AppVersion> appVersion() async {
    final v = _readVersion();
    return v == null ? const AppVersion('', '') : AppVersion(v.short, v.build);
  }

  // W1: capture and placement over FFI. A null capture makes applyRegion
  // return before it ever reads a screen frame, so the zero rect below is
  // never compared against anything (the zero-rect lesson in CLAUDE.md).
  @override
  Future<CapturedWindow?> captureFrontmost() async => null;
  @override
  Future<WinRect> activeScreenFrame() async => const WinRect(0, 0, 0, 0);
  @override
  Future<List<WinRect>> screenFrames() async => const [];
  @override
  Future<bool> applyFrame(WinRect target) async => false;

  // W3: the overlay, one engine per monitor, in C++.
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) async {}
  @override
  Future<void> showOverlay() async {}
  @override
  Future<void> hideOverlay() async {}

  // R2: labels keyed by HID usage; on Windows the stored logical key labels
  // letters and named keys itself, so this serves punctuation only (§5.4).
  @override
  Future<Map<int, String>> keyboardLabels() async => const {};

  // W5: the Run key plus StartupApproved (§5.2). `unavailable` is the one
  // status the pane never renders as "on".
  @override
  Future<LoginItemStatus> loginItemStatus() async =>
      LoginItemStatus.unavailable;
  @override
  Future<LoginItemStatus> setLoginItem(bool enabled) async =>
      LoginItemStatus.unavailable;
  @override
  Future<void> openLoginItemsSettings() async {}

  // W6: WinSparkle over FFI (§5.6).
  @override
  Future<bool> automaticUpdateChecks() async => false;
  @override
  Future<bool> setAutomaticUpdateChecks(bool enabled) async => false;
  @override
  Future<void> checkForUpdates() async {}
}
