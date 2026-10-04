import 'package:orthant/core/windows_window_ops.dart';

/// Facts for a test window: a placeable 800x600 Notepad of another process,
/// unless a test says otherwise. Pass `frame: null` for a window DWM will not
/// describe.
WindowFacts windowFacts(
  int hwnd, {
  int pid = 200,
  String className = 'Notepad',
  bool visible = true,
  bool cloaked = false,
  bool iconic = false,
  bool toolWindow = false,
  bool framed = true,
  PxRect? frame = const PxRect(0, 0, 800, 600),
}) =>
    WindowFacts(
      hwnd: hwnd,
      pid: pid,
      className: className,
      visible: visible,
      cloaked: cloaked,
      iconic: iconic,
      toolWindow: toolWindow,
      framed: framed,
      frame: frame,
    );

/// A desktop as data: [windows] is the z-order, top first.
class FakeDesktop implements Win32Desktop {
  FakeDesktop({this.ownPid = 1});

  final int ownPid;
  int foreground = 0;
  final List<WindowFacts> windows = [];
  final Map<int, String> names = {};
  final List<int> reactivated = [];
  bool foregroundRefused = false;

  /// How many z-order entries a walk has consumed.
  int pulled = 0;

  @override
  int get currentProcessId => ownPid;

  @override
  int foregroundWindow() => foreground;

  @override
  Iterable<int> zOrder() sync* {
    for (final w in windows) {
      pulled++;
      yield w.hwnd;
    }
  }

  @override
  WindowFacts facts(int hwnd) => windows.firstWhere((w) => w.hwnd == hwnd,
      orElse: () => windowFacts(hwnd, pid: 0, visible: false, frame: null));

  @override
  String? processName(int pid) => names[pid];

  @override
  bool setForeground(int hwnd) {
    reactivated.add(hwnd);
    return !foregroundRefused;
  }
}

/// A desktop with nothing on it, for tests about everything except capture and
/// placement. Each answer is the one Win32 gives about a window that does not
/// exist.
class NoWindows implements Win32Desktop, Win32Placer {
  @override
  int get currentProcessId => 1;
  @override
  int foregroundWindow() => 0;
  @override
  Iterable<int> zOrder() => const [];
  @override
  WindowFacts facts(int hwnd) =>
      windowFacts(hwnd, pid: 0, visible: false, frame: null);
  @override
  String? processName(int pid) => null;
  @override
  bool setForeground(int hwnd) => false;
  @override
  bool isWindow(int hwnd) => false;
  @override
  bool isZoomed(int hwnd) => false;
  @override
  bool restoreAsync(int hwnd) => false;
  @override
  PxRect? windowRect(int hwnd) => null;
  @override
  PxRect? extendedFrame(int hwnd) => null;
  @override
  SetPosResult setWindowPosAsync(int hwnd, int x, int y, int width, int height,
          {bool touchOnly = false}) =>
      (ok: false, error: 1400); // ERROR_INVALID_WINDOW_HANDLE
  @override
  bool beep() => false;
}

/// The invisible resize border, per edge, between a window's outer rect
/// (`GetWindowRect`) and the frame DWM draws.
class Border {
  const Border(this.left, this.top, this.right, this.bottom);
  final int left;
  final int top;
  final int right;
  final int bottom;

  PxRect around(PxRect f) =>
      PxRect(f.left - left, f.top - top, f.right + right, f.bottom + bottom);
  PxRect inside(PxRect o) =>
      PxRect(o.left + left, o.top + top, o.right - right, o.bottom - bottom);
}

/// One window, modelling what placement depends on: an outer rect around a
/// visible frame, a maximized state that takes reads to restore, a write that
/// lands after a delay or never (hung), a size floor, a self-resize after
/// crossing a DPI boundary (WM_DPICHANGED), and UIPI.
class FakeWindow implements Win32Placer {
  FakeWindow({required PxRect frame, this.border = const Border(7, 0, 7, 7)})
      : outer = border.around(frame);

  PxRect outer;
  Border border;
  PxRect get frame => border.inside(outer);

  bool exists = true;
  bool frameReadable = true;
  bool hung = false;
  bool deniedTouch = false;
  bool deniedWrite = false;

  bool zoomed = false;
  bool restorePostable = true;
  PxRect? restoredFrame;
  Border restoredBorder = const Border(7, 0, 7, 7);
  int restoreReads = 2;

  /// A write lands on the extendedFrame read after this many.
  int lagReads = 0;
  int? minOuterWidth;

  /// The window refuses to go above this outer top, as a target app's own
  /// WM_WINDOWPOSCHANGING handler can.
  int? minOuterTop;

  /// After the first write lands, the window resizes itself by this factor
  /// about its top-left and its border becomes [dpiBorder].
  double? dpiResize;
  Border? dpiBorder;

  final List<PxRect> writes = [];
  int touches = 0;
  int beeps = 0;
  bool restoreRequested = false;
  int? lastHwnd;

  PxRect? _pending;
  int _pendingReads = 0;
  int _zoomReads = 0;
  bool _resized = false;

  @override
  bool isWindow(int hwnd) => exists;

  @override
  bool isZoomed(int hwnd) {
    if (zoomed && restoreRequested && !hung && ++_zoomReads >= restoreReads) {
      zoomed = false;
      border = restoredBorder;
      outer = restoredBorder.around(restoredFrame ?? frame);
    }
    return zoomed;
  }

  @override
  bool restoreAsync(int hwnd) {
    if (!restorePostable) return false;
    restoreRequested = true;
    return true;
  }

  @override
  PxRect? windowRect(int hwnd) => exists ? outer : null;

  @override
  PxRect? extendedFrame(int hwnd) {
    if (!exists || !frameReadable) return null;
    if (_pending != null && !hung && ++_pendingReads > lagReads) {
      _apply(_pending!);
      _pending = null;
    }
    return frame;
  }

  @override
  SetPosResult setWindowPosAsync(int hwnd, int x, int y, int width, int height,
      {bool touchOnly = false}) {
    lastHwnd = hwnd;
    if (!exists) return (ok: false, error: 1400);
    if (touchOnly) {
      touches++;
      return deniedTouch
          ? (ok: false, error: kErrorAccessDenied)
          : (ok: true, error: 0);
    }
    if (deniedWrite) return (ok: false, error: kErrorAccessDenied);
    final r = PxRect(x, y, x + width, y + height);
    writes.add(r);
    _pending = r;
    _pendingReads = 0;
    return (ok: true, error: 0);
  }

  @override
  bool beep() {
    beeps++;
    return true;
  }

  void _apply(PxRect r) {
    var w = r.width;
    final floor = minOuterWidth;
    if (floor != null && w < floor) w = floor;
    var top = r.top;
    final topFloor = minOuterTop;
    if (topFloor != null && top < topFloor) top = topFloor;
    outer = PxRect(r.left, top, r.left + w, top + r.height);
    final factor = dpiResize;
    if (factor != null && !_resized) {
      _resized = true;
      border = dpiBorder ?? border;
      outer = PxRect(outer.left, outer.top,
          outer.left + (outer.width * factor).round(),
          outer.top + (outer.height * factor).round());
    }
  }
}

/// A clock whose sleeps take no time.
class FakeClock implements PlacementClock {
  @override
  int elapsedMs = 0;

  @override
  Future<void> sleep(int ms) async {
    elapsedMs += ms;
  }
}
