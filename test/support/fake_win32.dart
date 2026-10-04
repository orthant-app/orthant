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
