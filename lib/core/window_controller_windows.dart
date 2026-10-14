import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'dart:isolate' show Isolate;

import 'package:flutter/foundation.dart'
    show debugPrint, kReleaseMode, visibleForTesting;
import 'package:flutter/services.dart';
import 'channel.dart';
import 'geometry.dart';
import 'window_controller.dart';
import 'windows_accent.dart';
import 'windows_app_icon.dart';
import 'windows_capture.dart';
import 'windows_keys.dart';
import 'windows_login_item.dart';
import 'windows_placement.dart';
import 'windows_version_resource.dart';
import 'windows_win32_ops.dart';
import 'windows_window_ops.dart';

/// The Windows backend of the seam.
///
/// Everything stateless is `dart:ffi` via `package:win32`; C++ in
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
      this._readVersion,
      this._desktop,
      this._placer,
      this._clock,
      this._keyLabel,
      this._readIcon,
      this._readAccentPalette,
      this._startup,
      this._exePath,
      this._openStartupApps);

  /// The one way to obtain the controller in production.
  ///
  /// W6 initialises WinSparkle here, before returning, so the updater runs
  /// from `main()` and never waits for Settings to open. macOS shipped three
  /// releases that never checked for updates on their own because its updater
  /// was a lazy static nothing read until the settings window did (spec §5.6).
  static WindowsWindowController start() {
    final win32 = FfiWin32WindowOps();
    return WindowsWindowController._(
        readFixedFileVersion,
        win32,
        win32,
        RealPlacementClock(),
        win32.keyLabel,
        _readIconInBackground,
        readAccentPalette,
        const FfiStartupRegistry(),
        () => Platform.resolvedExecutable,
        openStartupAppsSettings);
  }

  /// [readAppIconPng] blocks, so it runs on an isolate of its own.
  static Future<Uint8List?> _readIconInBackground(String exe) =>
      Isolate.run(() => readAppIconPng(exe));

  /// The same controller with its OS supplied, for a suite that runs on a Mac
  /// where neither `version.dll` nor `user32.dll` exists.
  @visibleForTesting
  factory WindowsWindowController.forTest({
    required VersionReader readVersion,
    required Win32Desktop desktop,
    required Win32Placer placer,
    PlacementClock? clock,
    String? Function(int vk)? keyLabel,
    Future<Uint8List?> Function(String exe)? readIcon,
    AccentPaletteReader? readAccentPalette,
    StartupRegistry? startup,
    String Function()? exePath,
    bool Function()? openStartupApps,
  }) =>
      WindowsWindowController._(
          readVersion,
          desktop,
          placer,
          clock ?? RealPlacementClock(),
          keyLabel ?? (_) => null,
          readIcon ?? (_) async => null,
          readAccentPalette ?? () => null,
          startup ?? const _NoStartup(),
          exePath ?? () => r'C:\Orthant\Orthant.exe',
          openStartupApps ?? () => false);

  final VersionReader _readVersion;
  final Win32Desktop _desktop;
  final Win32Placer _placer;
  final PlacementClock _clock;

  /// What a virtual key types under the layout in front
  /// (`FfiWin32WindowOps.keyLabel`), for [keyboardLabels].
  final String? Function(int vk) _keyLabel;

  /// An executable's icon as a PNG ([readAppIconPng], off this isolate).
  final Future<Uint8List?> Function(String exe) _readIcon;

  /// Windows' accent palette ([readAccentPalette]), for [accentColor].
  final AccentPaletteReader _readAccentPalette;

  /// The registry values launch at login lives in ([FfiStartupRegistry]).
  final StartupRegistry _startup;

  /// This executable's path, which the startup entry must name to be this
  /// copy's ([Platform.resolvedExecutable]).
  final String Function() _exePath;

  /// Opens Settings' Startup apps page ([openStartupAppsSettings]).
  final bool Function() _openStartupApps;

  /// Icons by executable path, null for an app that has none to read. Read
  /// once per app per run: an executable's icon does not change while it
  /// runs, and the summon carries a cached one at no cost.
  final Map<String, Uint8List?> _icons = {};

  /// Executables whose icon is being read, so a second summon of the same app
  /// does not start a second read.
  final Set<String> _iconReads = {};

  /// The grid the runner last showed: its session (the capture id) and the
  /// app's executable. An icon that finishes reading goes to it only if it is
  /// still open and is still that app's.
  int? _shownId;
  String? _shownExe;

  /// The capture slot: the window the next placement moves. A handle, so it
  /// stays here, private to this backend; the seam sees only the
  /// [CapturedWindow] built from it. The owning process
  /// and class are kept beside it because Windows reuses handles: if the
  /// window closes before it is placed, the same number can in principle name
  /// a stranger's window (rare, as the handle's high word counts reuses),
  /// which must fail rather than move. [id] names the capture to the overlay:
  /// a summon's session is this id.
  ({int hwnd, int pid, String className, int id, String? exe})? _captured;

  /// The last id handed out. Every capture takes the next one, the direct
  /// shortcuts' included, so a commit from an older summon can never match a
  /// newer capture.
  int _captureSeq = 0;

  /// Whether the overlay has committed [_captured] already. Applying consumes
  /// the slot, so a duplicate commit is refused.
  bool _consumed = false;

  /// Whether the runner may still be showing a grid for [_captured]: set when
  /// a summon showed, cleared by a commit (the runner dismisses before it
  /// forwards one) and by [hideOverlay]. An Esc the runner handles itself
  /// leaves it set, which costs one unneeded hide at the next capture.
  bool _gridOpen = false;

  /// The current capture's id, or null when nothing is captured.
  @visibleForTesting
  int? get captureId => _captured?.id;

  static const MethodChannel _channel = MethodChannel(kOrthantChannel);

  /// Debug and Profile only. The acceptance harness parses these lines, so
  /// their formats, the `key=value` tokens included, are an interface: change
  /// one only together with the harness.
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

  /// The capture a shortcut makes. It first ends a grid still open: that grid
  /// names the capture this one replaces, so every commit from it would be
  /// dropped while it holds Esc, Enter and the arrows. The runner swallows
  /// hotkeys while a grid is live, but a shortcut pressed just before the
  /// grid showed waits in the command queue behind the summon, and lands here
  /// after it. Ended before the capture, so a capture that finds nothing ends
  /// it too. A summon does not come here ([showOverlay] captures for itself):
  /// the runner replaces a live session with the new one.
  @override
  Future<CapturedWindow?> captureFrontmost() async {
    if (_gridOpen) {
      try {
        await hideOverlay();
      } catch (e) {
        // The boundary below: logged, never thrown into the command queue.
        // And nothing captured: the grid may still be up, and replacing its
        // capture would leave it on a dead one. The next capture tries again.
        _log('capture: hide of the open grid threw ($e); nothing captured');
        return null;
      }
    }
    return _capture();
  }

  Future<CapturedWindow?> _capture() async {
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
      final exe = _desktop.imagePath(window.pid);
      final id = _captureSeq + 1;
      _log('capture: branch=${decision.branch.name} '
          'hwnd=0x${window.hwnd.toRadixString(16)} class=${window.className} '
          'pid=${window.pid} frame=$frame reactivated=$reactivated '
          'reason=${decision.reason} id=$id');
      final captured = CapturedWindow(
        name,
        WinRect(frame.left.toDouble(), frame.top.toDouble(),
            frame.width.toDouble(), frame.height.toDouble()),
      );
      // Last, so a throw anywhere above leaves nothing captured.
      _captureSeq = id;
      _captured = (
        hwnd: window.hwnd,
        pid: window.pid,
        className: window.className,
        id: id,
        exe: exe,
      );
      _consumed = false;
      return captured;
    } catch (e) {
      // A boundary: whatever Win32 did, a failed capture is "nothing to
      // place", never an exception escaping into the command queue.
      _log('capture: branch=none reason=threw ($e)');
      return null;
    }
  }

  @override
  Future<bool> applyFrame(WinRect target) async =>
      await _place(target) == PlacementOutcome.placed;

  /// Moves the captured window to [target] and reports how it went, or null
  /// when nothing was attempted: nothing captured, a different window behind
  /// the handle, or a throw.
  Future<PlacementOutcome?> _place(WinRect target) async {
    final captured = _captured;
    if (captured == null) return null;
    final hwnd = captured.hwnd;
    final started = _clock.elapsedMs;
    try {
      final now = _desktop.facts(hwnd);
      if (now.pid != captured.pid || now.className != captured.className) {
        _log('place: outcome=failed ms=0 why=window-changed '
            '(pid ${now.pid}, class ${now.className})');
        return null;
      }
      final result =
          await placeWindow(_placer, hwnd, pxRectFor(target), clock: _clock);
      _log('place: outcome=${result.outcome.name} '
          'ms=${_clock.elapsedMs - started} ${result.trace}');
      return result.outcome;
    } catch (e) {
      _log('place: outcome=failed ms=${_clock.elapsedMs - started} '
          'why=threw ($e)');
      return null;
    }
  }

  @override
  Future<bool> applyOverlayCommit(int sessionId, WinRect target) async {
    final captured = _captured;
    if (captured == null || captured.id != sessionId) {
      // Not the open grid's: a newer summon may have replaced that grid, and
      // it is still up.
      _log('overlay commit: id=$sessionId outcome=dropped why=stale '
          'slot=${captured?.id ?? 'none'}');
      return false;
    }
    // The runner ended the session before sending its commit.
    _gridOpen = false;
    if (_consumed) {
      _log('overlay commit: id=$sessionId outcome=dropped why=consumed');
      return false;
    }
    _consumed = true;
    final outcome = await _place(target);
    // A grid commit that moved nothing is never silent: macOS beeps for it
    // natively (OverlayPanelSet.commit). An elevated target was beeped at
    // inside placement already.
    if (outcome != PlacementOutcome.placed &&
        outcome != PlacementOutcome.elevated) {
      _placer.beep();
    }
    _log('overlay commit: id=$sessionId outcome=${outcome?.name ?? 'failed'}');
    return outcome == PlacementOutcome.placed;
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

  // The overlay: one panel per monitor in the runner, each with its own
  // engine running overlayMain (windows_overlay_set.cpp).
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) =>
      _channel.invokeMethod<void>(kSetOverlayGrid, {
        'cols': cols,
        'rows': rows,
        'gap': gap,
        'saveHint': saveHint,
      });

  /// Capture, then ask the runner to show the panels for that capture.
  ///
  /// The summon path's one Dart round trip, with the capture inside it and
  /// before any UI: the session is named by the capture's id, so the commit
  /// that comes back can be checked against the slot it was meant for, and
  /// [pressedAtMs] goes with it when the summon had a press.
  /// Nothing to capture is a beep and no overlay, as on macOS, and the runner
  /// is told to hide, which ends any grid still open. The reply says whether
  /// the panels showed, and a refusal is followed by the same hide. The
  /// runner refuses for four reasons: a monitor with no panel, or whose panel
  /// has no engine attached yet (the seconds after launch, or just after a
  /// monitor arrives); Esc or Enter held by another app; a hotkey press more
  /// than 1 s old (stale); or the displays changing (a reconcile posted or
  /// running, or a summon re-entered from inside a resize).
  @override
  Future<void> showOverlay({double? pressedAtMs}) async {
    final started = _clock.elapsedMs;
    final captured = await _capture();
    final id = captureId;
    final captureMs = _clock.elapsedMs - started;
    if (captured == null || id == null) {
      _placer.beep();
      _log('summon: outcome=no-capture capture=${captureMs}ms');
      // Ends a grid still open, whose capture was just cleared.
      await hideOverlay();
      return;
    }
    final exe = _captured?.exe;
    // The cached icon if there is one, and nothing otherwise: the summon never
    // waits for one (SHGetFileInfo can block).
    final icon = exe == null ? null : _icons[exe];
    final shown = await _channel.invokeMethod<Object?>(kShowOverlay, {
      'captureId': id,
      'appName': captured.appName,
      // The captured window's process: the runner ends the grid when the
      // foreground moves to any other (a click on the taskbar, Alt+Tab), and
      // not when Windows activates the captured window itself, which a tray
      // summon's capture does after the runner has shown the panels.
      'pid': _captured?.pid,
      'appIcon': ?icon,
      'pressedAtMs': ?pressedAtMs,
    });
    _log('summon: outcome=${shown == true ? 'shown' : 'refused'} id=$id '
        'capture=${captureMs}ms icon=${icon != null ? 'cached' : 'none'}');
    if (shown == true) {
      _gridOpen = true;
      _shownId = id;
      _shownExe = exe;
      if (exe != null && !_icons.containsKey(exe)) {
        unawaited(_readIconFor(exe));
      } else if (exe != null && icon == null && _icons[exe] != null) {
        // An earlier summon's read landed while this one was in flight: it
        // found no grid of this app open, and this summon went without.
        final started = _clock.elapsedMs;
        final late = _icons[exe]!;
        final outcome = await _sendIcon(id, late);
        _log('icon: id=$id outcome=$outcome bytes=${late.length} '
            'ms=${_clock.elapsedMs - started} (read during the summon)');
      }
    } else {
      // The capture slot was just replaced, so a grid still open names a
      // capture that no longer exists: every commit from it would be dropped
      // while it holds Esc, Enter and the arrows. The runner refuses for a
      // stale press, engines not ready, displays changing, or Esc or Enter
      // held, and some of those return before it replaces the session.
      // Through hideOverlay: a hide that fails leaves a grid still open
      // marked open, so the next capture ends it.
      await hideOverlay();
    }
  }

  /// Read [exe]'s icon, cache it, and send it to the grid on screen if that
  /// grid is still this app's. Never throws: an icon is a nicety, and this
  /// runs outside the command queue, where nothing would catch it.
  Future<void> _readIconFor(String exe) async {
    if (!_iconReads.add(exe)) return;
    final started = _clock.elapsedMs;
    Uint8List? png;
    try {
      png = await _readIcon(exe);
    } catch (e) {
      // Not cached, so the next summon of this app tries again.
      _log('icon: outcome=threw ($e) ms=${_clock.elapsedMs - started}');
      return;
    } finally {
      _iconReads.remove(exe);
    }
    _icons[exe] = png;
    final id = _shownId;
    final String outcome;
    if (png == null) {
      outcome = 'none';
    } else if (id != null && _gridOpen && _shownExe == exe) {
      outcome = await _sendIcon(id, png);
    } else {
      outcome = 'kept';
    }
    _log('icon: id=${id ?? 'none'} outcome=$outcome '
        'bytes=${png?.length ?? 0} ms=${_clock.elapsedMs - started}');
  }

  /// Sends an icon to the grid of session [id]; its outcome for the log. A
  /// failure costs only this grid's chip: the icon is cached already, so the
  /// next summon of the app carries it.
  Future<String> _sendIcon(int id, Uint8List png) async {
    try {
      await _channel
          .invokeMethod<void>(kSetAppIcon, {'sessionId': id, 'png': png});
      return 'sent';
    } catch (e) {
      return 'unsent ($e)';
    }
  }

  /// Ends the grid the runner last showed, by its session: a hide can then
  /// never end a newer grid than the one it was meant for. -1 when no grid
  /// was ever shown, which ends nothing.
  @override
  Future<void> hideOverlay() async {
    await _channel
        .invokeMethod<void>(kHideOverlay, {'sessionId': _shownId ?? -1});
    // Cleared once the runner has answered: a hide that fails leaves the grid
    // marked open, so the next capture ends it.
    _gridOpen = false;
  }

  /// The runner holds the overlay's engines back until this, or a deadline of
  /// its own: each costs over a second of the thread the hotkeys and the tray
  /// answer on. Never throws: if it cannot be delivered, the deadline starts
  /// them anyway.
  @override
  Future<void> startOverlay() async {
    try {
      await _channel.invokeMethod<void>(kStartOverlay);
    } catch (e) {
      _log('start overlay: threw ($e)');
    }
  }

  @override
  Future<void> setCommandsRunning(bool running) async {
    // Never throws: the queue calls this around every burst of commands, and
    // a runner that misses one has a ceiling of its own.
    try {
      await _channel
          .invokeMethod<void>(kSetCommandsRunning, {'running': running});
    } catch (e) {
      _log('commands running: threw ($e)');
    }
  }

  /// Labels for the keys whose symbol depends on the layout, keyed by their
  /// Windows id (`KeyChord.labelKey` on Windows). Letters, digits and named
  /// keys are labelled from the chord's logical key itself, so they are not
  /// read here.
  @override
  Future<Map<int, String>> keyboardLabels() async {
    final labels = <int, String>{};
    try {
      for (final vk in windowsLabelledKeys) {
        final label = _keyLabel(vk);
        if (label != null && label.trim().isNotEmpty) {
          labels[windowsKeyOf(vk)] = label;
        }
      }
    } catch (e) {
      // Display data only: a key with no label shows its US glyph.
      _log('labels: threw ($e)');
      return const {};
    }
    return labels;
  }

  /// Read from the registry every time, where Windows' Settings writes it, so
  /// a change of accent shows the next time the window opens. A registry
  /// read, not the runner's: nothing here needs a window or the message loop.
  @override
  Future<AccentColors?> accentColor() async {
    try {
      return accentFromPalette(_readAccentPalette());
    } catch (e) {
      // Display data only: the theme draws the default accent.
      _log('accent: threw ($e)');
      return null;
    }
  }

  /// The Run value and its StartupApproved record, read every time: the user
  /// can change either in Task Manager or Settings without telling anyone, as
  /// on macOS. A registry read, so Dart, with no window and no runner.
  @override
  Future<LoginItemStatus> loginItemStatus() async {
    try {
      return loginItemStatusOf(
          run: _startup.readRun(),
          approved: _startup.readApproved(),
          exe: _exePath());
    } catch (e) {
      _log('login item: threw ($e)');
      return LoginItemStatus.unavailable;
    }
  }

  /// Writes or deletes the Run value, then answers what the registry says,
  /// never what was asked: turning it on over the user's off in Startup apps
  /// leaves it off, which is [LoginItemStatus.requiresApproval].
  @override
  Future<LoginItemStatus> setLoginItem(bool enabled) async {
    try {
      final done = enabled
          ? _startup.writeRun(runCommandFor(_exePath()))
          : _startup.deleteRun();
      if (!done) _log('login item: ${enabled ? 'write' : 'delete'} failed');
    } catch (e) {
      _log('login item: threw ($e)');
    }
    return loginItemStatus();
  }

  @override
  Future<void> openLoginItemsSettings() async {
    try {
      if (!_openStartupApps()) _log('startup apps: not opened');
    } catch (e) {
      _log('startup apps: threw ($e)');
    }
  }

  // W6: WinSparkle over FFI (§5.6).
  @override
  Future<bool> automaticUpdateChecks() async => false;
  @override
  Future<bool> setAutomaticUpdateChecks(bool enabled) async => false;
  @override
  Future<void> checkForUpdates() async {}
}

/// No startup entry, for a test that does not name one.
class _NoStartup implements StartupRegistry {
  const _NoStartup();
  @override
  RegRead<String> readRun() => (found: RegFound.absent, data: null);
  @override
  RegRead<Uint8List> readApproved() => (found: RegFound.absent, data: null);
  @override
  bool writeRun(String command) => false;
  @override
  bool deleteRun() => true;
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
/// None means "no display list": `applyRegion` then places only on the
/// cursor's display, and only a window that is on it.
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
