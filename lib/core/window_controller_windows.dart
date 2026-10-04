import 'package:flutter/foundation.dart'
    show debugPrint, kReleaseMode, visibleForTesting;
import 'package:flutter/services.dart';
import 'channel.dart';
import 'geometry.dart';
import 'window_controller.dart';
import 'windows_capture.dart';
import 'windows_placement.dart';
import 'windows_version_resource.dart';
import 'windows_win32_ops.dart';
import 'windows_window_ops.dart';

/// The Windows backend of the seam.
///
/// Design: `.claude/docs/superpowers/specs/2026-09-18-windows-port-design.md`
/// §5. Everything stateless is `dart:ffi` via `package:win32`; C++ in
/// `windows/runner/` holds only what needs a window we create, the message
/// loop or (from W3) an engine, and is reached over the same
/// `app.orthant/window` channel macOS uses (`windows/runner/window_channel.cpp`).
///
/// Since W1: capture and placement are Dart decisions (`windows_capture.dart`,
/// `windows_placement.dart`) over Win32 calls made here through
/// `windows_win32_ops.dart`, and the displays come from the runner's
/// per-monitor windows. The methods still marked with a later milestone are
/// stubs, and **no stub may call the channel**: the runner answers
/// `NotImplemented` for anything it does not handle, which surfaces here as
/// `MissingPluginException` (`test/windows_channel_contract_test.dart` guards
/// the methods that do call it).
class WindowsWindowController implements WindowController {
  WindowsWindowController._(
      this._readVersion, this._desktop, this._placer, this._clock);

  /// The one way to obtain the controller in production.
  ///
  /// W6 initialises WinSparkle here, before returning, so the updater runs
  /// from `main()` and never waits for Settings to open. macOS shipped three
  /// releases that never checked for updates on their own because its updater
  /// was a lazy static nothing read until the settings window did (spec §5.6).
  static WindowsWindowController start() {
    final win32 = FfiWin32WindowOps();
    return WindowsWindowController._(
        readFixedFileVersion, win32, win32, RealPlacementClock());
  }

  /// The same controller with its OS supplied, for a suite that runs on a Mac
  /// where neither `version.dll` nor `user32.dll` exists.
  @visibleForTesting
  factory WindowsWindowController.forTest({
    required VersionReader readVersion,
    required Win32Desktop desktop,
    required Win32Placer placer,
    PlacementClock? clock,
  }) =>
      WindowsWindowController._(
          readVersion, desktop, placer, clock ?? RealPlacementClock());

  final VersionReader _readVersion;
  final Win32Desktop _desktop;
  final Win32Placer _placer;
  final PlacementClock _clock;

  /// The capture slot: the window the next [applyFrame] moves. A handle, so it
  /// stays here, private to this backend; the seam sees only the
  /// [CapturedWindow] built from it (Windows design §5.1).
  int? _captured;

  static const MethodChannel _channel = MethodChannel(kOrthantChannel);

  /// Debug and Profile only. The acceptance harness reads these lines; their
  /// formats are fixed in the W1 plan (Task 7's Interfaces).
  static void _log(String message) {
    if (!kReleaseMode) debugPrint('[orthant] $message');
  }

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

  @override
  Future<CapturedWindow?> captureFrontmost() async {
    // Cleared first, so every early return leaves nothing captured and a later
    // applyFrame cannot move whatever an earlier capture held: the rule the
    // macOS slot follows for the same reason (WindowControl.swift).
    _captured = null;
    try {
      final decision = decideCapture(_desktop);
      final window = decision.window;
      final frame = window?.frame;
      if (window == null || frame == null) {
        _log('capture: branch=none reason=${decision.reason}');
        return null;
      }
      var reactivated = 'no';
      if (decision.reactivate) {
        reactivated = _desktop.setForeground(window.hwnd) ? 'yes' : 'refused';
      }
      final name = _desktop.processName(window.pid) ?? '';
      _captured = window.hwnd;
      _log('capture: branch=${decision.branch.name} '
          'hwnd=0x${window.hwnd.toRadixString(16)} class=${window.className} '
          'pid=${window.pid} frame=$frame reactivated=$reactivated '
          'reason=${decision.reason}');
      return CapturedWindow(
        name,
        WinRect(frame.left.toDouble(), frame.top.toDouble(),
            frame.width.toDouble(), frame.height.toDouble()),
      );
    } catch (e) {
      // A boundary: whatever Win32 did, a failed capture is "nothing to
      // place", never an exception escaping into the command queue.
      _log('capture: branch=none reason=threw ($e)');
      return null;
    }
  }

  @override
  Future<bool> applyFrame(WinRect target) async {
    final hwnd = _captured;
    if (hwnd == null) return false;
    final started = _clock.elapsedMs;
    try {
      final result =
          await placeWindow(_placer, hwnd, pxRectFor(target), clock: _clock);
      _log('place: outcome=${result.outcome.name} '
          'ms=${_clock.elapsedMs - started} ${result.trace}');
      return result.placed;
    } catch (e) {
      _log('place: outcome=failed ms=${_clock.elapsedMs - started} '
          'why=threw ($e)');
      return false;
    }
  }

  @override
  Future<List<Display>> screenFrames() async {
    final displays =
        displaysFromReply(await _channel.invokeMethod<Object?>(kScreenFrames));
    _log('displays: ${displays.map(_format).join(' ')}');
    return displays;
  }

  @override
  Future<Display?> activeScreenFrame() async {
    final display = displayFromReply(
        await _channel.invokeMethod<Object?>(kActiveScreenFrame));
    _log('active display: ${display == null ? 'none' : _format(display)}');
    return display;
  }

  static String _format(Display d) =>
      '${d.frame.x.round()},${d.frame.y.round()},'
      '${d.frame.width.round()}x${d.frame.height.round()}@${d.scale}';

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

/// One display from the runner's reply, or null if any field is missing,
/// non-numeric, non-finite or impossible. Strict on purpose: a scale that
/// defaulted to 1.0 would make a Windows display that lost it place every gap
/// at the wrong size and still look like it worked.
@visibleForTesting
Display? displayFromReply(Object? reply) {
  if (reply is! Map) return null;
  double? read(String key) {
    final v = reply[key];
    return v is num && v.isFinite ? v.toDouble() : null;
  }

  final x = read('x');
  final y = read('y');
  final w = read('w');
  final h = read('h');
  final scale = read('scale');
  if (x == null || y == null || w == null || h == null || scale == null) {
    return null;
  }
  if (w <= 0 || h <= 0 || scale <= 0) return null;
  return Display(WinRect(x, y, w, h), scale);
}

/// Every display, or none: a list with one entry dropped could place a window
/// on the wrong display, since `displayContaining` falls back to the first.
@visibleForTesting
List<Display> displaysFromReply(Object? reply) {
  if (reply is! List) return const [];
  final displays = <Display>[];
  for (final entry in reply) {
    final display = displayFromReply(entry);
    if (display == null) return const [];
    displays.add(display);
  }
  return displays;
}
