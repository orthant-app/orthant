import 'windows_window_ops.dart';

/// The shell's desktop. Never a target: macOS once captured an empty Desktop
/// as a window, and the grid then appeared over nothing (CLAUDE.md, M5).
const Set<String> kDesktopClasses = {'Progman', 'WorkerW'};

/// The taskbar and the notification area's overflow flyout (Windows 10 and
/// 11). A tray click hands foreground to one of these, or to Orthant's own
/// hidden window, before Orthant's menu command runs.
const Set<String> kTrayClasses = {
  'Shell_TrayWnd',
  'Shell_SecondaryTrayWnd',
  'NotifyIconOverflowWindow',
  'TopLevelWindowForOverflowXamlIsland',
};

/// Shell surfaces that are top-level, visible and framed while open and are
/// still nothing to snap: Start, Search and the notification centre
/// (CoreWindow), Alt+Tab and Snap Assist (XamlExplorerHostIslandWindow), and
/// menus. A UWP app is unaffected: its top-level window is an
/// ApplicationFrameWindow, with the CoreWindow inside it.
const Set<String> kShellSurfaceClasses = {
  'Windows.UI.Core.CoreWindow',
  'XamlExplorerHostIslandWindow',
  '#32768',
};

enum CaptureBranch { foreground, beneath, none }

class CaptureDecision {
  const CaptureDecision.capture(
    WindowFacts this.window, {
    required this.branch,
    required this.reactivate,
    required this.reason,
  });

  const CaptureDecision.none(this.reason)
      : window = null,
        branch = CaptureBranch.none,
        reactivate = false;

  /// The window to place, or null to place nothing.
  final WindowFacts? window;
  final CaptureBranch branch;

  /// Whether to hand this window foreground before placing it, because the
  /// tray took it away from the window the user was working in.
  final bool reactivate;

  /// One kebab-case token for the debug log.
  final String reason;
}

/// Whether Orthant may move [w]: another process's window, on screen, not
/// minimized, not the desktop, the taskbar or a shell surface, and with a
/// frame DWM will describe. A minimized window is refused rather than
/// restored: placing it would either do nothing or un-minimize it, neither of
/// which a snap asked for.
bool isPlaceable(WindowFacts w, int ownPid) {
  final frame = w.frame;
  return w.pid != ownPid &&
      w.visible &&
      !w.cloaked &&
      !w.iconic &&
      !kDesktopClasses.contains(w.className) &&
      !kTrayClasses.contains(w.className) &&
      !kShellSurfaceClasses.contains(w.className) &&
      frame != null &&
      !frame.isEmpty;
}

/// Which window a placement acts on, decided from the desktop as it is now.
///
/// Usually the foreground window, as on macOS. The exception is what a tray
/// click does on Windows: by the time Orthant's menu command runs, foreground
/// belongs to the taskbar, the overflow flyout, or Orthant's own hidden window
/// (tray_manager foregrounds it so the menu can dismiss), never to the window
/// the user was working in. In those states the target is the topmost
/// placeable window beneath (an always-on-top one only when nothing else is
/// placeable), and it is reactivated, so the user's keyboard
/// focus ends where it was before the tray took it. With Orthant's visible
/// settings window in front, the window beneath is still the target (macOS
/// captures nothing there; on Windows the tray itself puts that window in
/// front), but focus stays with the settings window the user is looking at.
///
/// The desktop, and anything else unplaceable in front, capture nothing, as on
/// macOS. Two consequences of the tray path that differ from macOS, accepted
/// because a tray click erases what was in front before it: a user who clicked
/// the desktop and then the tray gets the topmost window snapped, where macOS
/// would capture nothing; and with the settings window open, tray_manager
/// raises it before the menu (so its menu can dismiss), so focus ends on
/// Orthant's settings window rather than going back to the snapped one.
///
/// Nothing here sends a window a message: [Win32Desktop.facts] reads
/// window-manager state, so a hung window cannot hang the decision.
CaptureDecision decideCapture(Win32Desktop desktop) {
  final ownPid = desktop.currentProcessId;
  final fg = desktop.foregroundWindow();
  if (fg == 0) {
    return _beneath(desktop, ownPid, fg,
        reactivate: true, reason: 'no-foreground');
  }
  final front = desktop.facts(fg);
  if (front.pid == ownPid) {
    // A minimized window keeps WS_VISIBLE, so "on screen" is both.
    return front.visible && !front.iconic
        ? _beneath(desktop, ownPid, fg,
            reactivate: false, reason: 'orthant-window-in-front')
        : _beneath(desktop, ownPid, fg,
            reactivate: true, reason: 'orthant-hidden-window');
  }
  if (kTrayClasses.contains(front.className)) {
    return _beneath(desktop, ownPid, fg,
        reactivate: true, reason: 'tray-holds-foreground');
  }
  if (isPlaceable(front, ownPid)) {
    return CaptureDecision.capture(front,
        branch: CaptureBranch.foreground,
        reactivate: false,
        reason: 'foreground-placeable');
  }
  return const CaptureDecision.none('foreground-not-placeable');
}

CaptureDecision _beneath(Win32Desktop desktop, int ownPid, int fg,
    {required bool reactivate, required String reason}) {
  CaptureDecision found(WindowFacts w) => CaptureDecision.capture(w,
      branch: CaptureBranch.beneath, reactivate: reactivate, reason: reason);
  // An always-on-top window (a pinned video, a sticky note) sits first in
  // z-order whether or not the user was last working in it, so it is taken
  // only when nothing below it is placeable. The topmost band comes first,
  // so the walk still stops at the first ordinary placeable window.
  WindowFacts? pinned;
  for (final hwnd in desktop.zOrder()) {
    if (hwnd == fg) continue;
    final w = desktop.facts(hwnd);
    // A guess, unlike the foreground window, so held to more: tool windows
    // (palettes, flyouts, tooltips) and borderless popups are passed over.
    if (w.toolWindow || !w.framed || !isPlaceable(w, ownPid)) continue;
    if (!w.topmost) return found(w);
    pinned ??= w;
  }
  return pinned == null
      ? const CaptureDecision.none('nothing-placeable-beneath')
      : found(pinned);
}
