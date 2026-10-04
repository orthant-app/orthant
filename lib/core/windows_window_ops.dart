/// A rectangle in physical pixels with Win32 `RECT` semantics: [right] and
/// [bottom] are exclusive.
class PxRect {
  const PxRect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is PxRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  /// No spaces, so the debug log's `key=value` fields stay one token each.
  @override
  String toString() => '[$left,$top,$right,$bottom]';
}

/// What the capture policy needs to know about one top-level window.
///
/// Every field is read without sending the window a message (class name,
/// styles, visibility and DWM's view of it), so reading the facts of a hung
/// window cannot hang Orthant.
class WindowFacts {
  const WindowFacts({
    required this.hwnd,
    required this.pid,
    required this.className,
    required this.visible,
    required this.cloaked,
    required this.iconic,
    required this.toolWindow,
    required this.framed,
    required this.frame,
  });

  final int hwnd;
  final int pid;
  final String className;
  final bool visible;

  /// `DWMWA_CLOAKED`: how a window on another virtual desktop, a suspended UWP
  /// host, or a shell surface that is "shown" but not on screen presents.
  final bool cloaked;
  final bool iconic;

  /// `WS_EX_TOOLWINDOW`: palettes, flyouts, tooltips. Not an app window.
  final bool toolWindow;

  /// `WS_CAPTION` or `WS_THICKFRAME`: a window a user could move or resize.
  final bool framed;

  /// `DWMWA_EXTENDED_FRAME_BOUNDS`, the frame the user sees; null when DWM
  /// would not describe it.
  final PxRect? frame;
}

/// What one asynchronous `SetWindowPos` reported.
typedef SetPosResult = ({bool ok, int error});

/// `ERROR_ACCESS_DENIED`: what UIPI answers a write from a lower integrity
/// level, i.e. what an elevated target answers a non-elevated Orthant.
const int kErrorAccessDenied = 5;

/// The part of the desktop that capture reads. `windows_win32_ops.dart` is the
/// real one; the suite uses a fake, because which window to capture is a
/// decision and decisions are tested (CLAUDE.md: macOS's placement retry loop
/// went uncovered for a milestone for want of exactly this seam).
///
/// Window handles are plain ints, private to the Windows backend. They never
/// cross the method channel; the seam carries only plain data.
abstract interface class Win32Desktop {
  int get currentProcessId;

  /// `GetForegroundWindow`; 0 when there is none, as during an activation
  /// change.
  int foregroundWindow();

  /// Top-level windows from the top of the z-order down, lazily, so a walk
  /// that finds its window near the top reads no further.
  Iterable<int> zOrder();

  WindowFacts facts(int hwnd);

  /// The `FileDescription` of the process's executable, else its file stem,
  /// else null.
  String? processName(int pid);

  bool setForeground(int hwnd);
}

/// The part of Win32 that placement uses, on one captured window.
abstract interface class Win32Placer {
  bool isWindow(int hwnd);
  bool isZoomed(int hwnd);

  /// `ShowWindowAsync(SW_RESTORE)`. False if the request could not be posted.
  bool restoreAsync(int hwnd);

  /// `GetWindowRect`, which includes the invisible resize border. Read only to
  /// measure that border, never as the window's frame (Windows design §5.7).
  PxRect? windowRect(int hwnd);

  /// `DWMWA_EXTENDED_FRAME_BOUNDS`, the frame the user sees.
  PxRect? extendedFrame(int hwnd);

  /// `GetDpiForWindow` of the target: its DPI now, or 0 when unknown. For a
  /// per-monitor-aware window this changes the moment it moves onto a monitor
  /// of another scale, when the system sends it WM_DPICHANGED, and before the
  /// window's own handling of that message resizes it.
  int windowDpi(int hwnd);

  /// `SetWindowPos` with `SWP_NOACTIVATE | SWP_NOZORDER | SWP_ASYNCWINDOWPOS`.
  /// With [touchOnly], also `SWP_NOMOVE | SWP_NOSIZE`: a write that changes
  /// nothing, whose only purpose is the access check UIPI applies to every
  /// write.
  SetPosResult setWindowPosAsync(int hwnd, int x, int y, int width, int height,
      {bool touchOnly = false});

  /// `MessageBeep(MB_OK)`, the system's "cannot do that".
  bool beep();
}

/// Time, for placement's bounded waits. Injected so a test can run a 500 ms
/// deadline in no time.
abstract interface class PlacementClock {
  int get elapsedMs;
  Future<void> sleep(int ms);
}

class RealPlacementClock implements PlacementClock {
  RealPlacementClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  int get elapsedMs => _watch.elapsedMilliseconds;

  @override
  Future<void> sleep(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
}
