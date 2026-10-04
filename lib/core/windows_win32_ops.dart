import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'windows_version_resource.dart';
import 'windows_window_ops.dart';

/// [Win32Desktop] and [Win32Placer] over `package:win32` 6.4.0. Windows only,
/// and verified in the VM, since none of it can run on the Mac that runs the
/// suite. It decides nothing: which window to capture is `windows_capture.dart`
/// and how to place it is `windows_placement.dart`.
///
/// Every call here is thread-agnostic, and none sends the target window a
/// message, which is what keeps a hung target from hanging Orthant:
/// `GetClassName`, `IsWindowVisible`, `IsIconic`, `IsZoomed`,
/// `GetWindowLongPtr`, `GetWindowRect`, `GetDpiForWindow` and
/// `GetWindowDpiAwarenessContext` read window-manager state; `MonitorFromRect`
/// and `GetDpiForMonitor` read display state and name no window;
/// `DwmGetWindowAttribute` asks DWM; `ShowWindowAsync` and `SetWindowPos`
/// with `SWP_ASYNCWINDOWPOS` post; `SetForegroundWindow` on another thread's
/// window queues the activation rather than waiting for it.
///
/// Nothing is called in the constructor, so building one on the Mac (as
/// `WindowsWindowController.start` would) is harmless.
class FfiWin32WindowOps implements Win32Desktop, Win32Placer {
  /// Process names by executable path. A name read is a file read, and this
  /// sits on the summon path from W3; an app's description does not change
  /// while it runs.
  final Map<String, String> _names = {};

  static HWND _h(int hwnd) => HWND(Pointer<Void>.fromAddress(hwnd));

  @override
  int get currentProcessId => GetCurrentProcessId();

  @override
  int foregroundWindow() => GetForegroundWindow().address;

  @override
  Iterable<int> zOrder() sync* {
    // GetWindow in a loop can revisit or skip a window whose z-order changes
    // mid-walk, which is why EnumWindows' documentation prefers itself. The
    // cap bounds any loop, and the capture policy wants only the first
    // eligible window near the top, so the walk is short in practice.
    var h = GetTopWindow(null).value;
    for (var i = 0; i < 1024 && h.address != 0; i++) {
      yield h.address;
      h = GetWindow(h, GW_HWNDNEXT).value;
    }
  }

  @override
  WindowFacts facts(int hwnd) {
    final h = _h(hwnd);
    Pointer<Uint32>? pid;
    Pointer<Utf16>? cls;
    try {
      pid = calloc<Uint32>();
      cls = calloc<Uint16>(256).cast<Utf16>();
      GetWindowThreadProcessId(h, pid);
      final n = GetClassName(h, PWSTR(cls), 256).value;
      final style = GetWindowLongPtr(h, GWL_STYLE).value;
      final exStyle = GetWindowLongPtr(h, GWL_EXSTYLE).value;
      return WindowFacts(
        hwnd: hwnd,
        pid: pid.value,
        className: n > 0 ? cls.toDartString(length: n) : '',
        visible: IsWindowVisible(h),
        cloaked: _cloaked(h),
        iconic: IsIconic(h),
        toolWindow: (exStyle & WS_EX_TOOLWINDOW) != 0,
        // WS_CAPTION is two bits (WS_BORDER | WS_DLGFRAME); only both together
        // are a title bar. A thin-border popup is not a window a user can move.
        framed: (style & WS_CAPTION) == WS_CAPTION || (style & WS_THICKFRAME) != 0,
        frame: extendedFrame(hwnd),
      );
    } finally {
      if (cls != null) calloc.free(cls);
      if (pid != null) calloc.free(pid);
    }
  }

  @override
  String? processName(int pid) {
    final path = _imagePath(pid);
    if (path == null) return null;
    return _names.putIfAbsent(path, () => readFileDescription(path) ?? _stem(path));
  }

  @override
  bool setForeground(int hwnd) => SetForegroundWindow(_h(hwnd));

  @override
  bool isWindow(int hwnd) => IsWindow(_h(hwnd));

  @override
  bool isZoomed(int hwnd) => IsZoomed(_h(hwnd));

  @override
  bool restoreAsync(int hwnd) => ShowWindowAsync(_h(hwnd), SW_RESTORE);

  @override
  PxRect? windowRect(int hwnd) {
    final r = calloc<RECT>();
    try {
      if (!GetWindowRect(_h(hwnd), r).value) return null;
      return PxRect(r.ref.left, r.ref.top, r.ref.right, r.ref.bottom);
    } finally {
      calloc.free(r);
    }
  }

  @override
  PxRect? extendedFrame(int hwnd) {
    final r = calloc<RECT>();
    try {
      DwmGetWindowAttribute(
          _h(hwnd), DWMWA_EXTENDED_FRAME_BOUNDS, r, sizeOf<RECT>());
      return PxRect(r.ref.left, r.ref.top, r.ref.right, r.ref.bottom);
    } on WindowsException {
      // A window that has gone, or one DWM will not describe. Null, never a
      // zero rect (the zero-rect lesson).
      return null;
    } finally {
      calloc.free(r);
    }
  }

  @override
  int windowDpi(int hwnd) => GetDpiForWindow(_h(hwnd));

  @override
  int monitorDpi(PxRect rect) {
    Pointer<RECT>? r;
    Pointer<Uint32>? x;
    Pointer<Uint32>? y;
    try {
      r = calloc<RECT>();
      x = calloc<Uint32>();
      y = calloc<Uint32>();
      r.ref
        ..left = rect.left
        ..top = rect.top
        ..right = rect.right
        ..bottom = rect.bottom;
      final monitor = MonitorFromRect(r, MONITOR_DEFAULTTONEAREST);
      if (monitor.address == 0) return 0;
      GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, x, y);
      return x.value;
    } catch (_) {
      // Any failure is "unknown": a failed HRESULT, or the API set's DLL,
      // which loads lazily, failing to load (an ArgumentError). The answer
      // only decides whether placement waits for a DPI change, so it must
      // never fail the placement.
      return 0;
    } finally {
      if (y != null) calloc.free(y);
      if (x != null) calloc.free(x);
      if (r != null) calloc.free(r);
    }
  }

  @override
  bool perMonitorAware(int hwnd) =>
      GetAwarenessFromDpiAwarenessContext(
          GetWindowDpiAwarenessContext(_h(hwnd))) ==
      DPI_AWARENESS_PER_MONITOR_AWARE;

  @override
  SetPosResult setWindowPosAsync(int hwnd, int x, int y, int width, int height,
      {bool touchOnly = false}) {
    var flags = SWP_NOACTIVATE | SWP_NOZORDER | SWP_ASYNCWINDOWPOS;
    if (touchOnly) flags = flags | SWP_NOMOVE | SWP_NOSIZE;
    final r = SetWindowPos(_h(hwnd), null, x, y, width, height, flags);
    return (ok: r.value, error: r.error);
  }

  @override
  bool beep() => MessageBeep(MB_OK).value;

  static bool _cloaked(HWND h) {
    final v = calloc<Uint32>();
    try {
      DwmGetWindowAttribute(h, DWMWA_CLOAKED, v, sizeOf<Uint32>());
      return v.value != 0;
    } on WindowsException {
      // Unreadable only if DWM itself is not answering, in which case the
      // frame is unreadable too and the window is not placeable regardless.
      return false;
    } finally {
      calloc.free(v);
    }
  }

  static String? _imagePath(int pid) {
    final process =
        OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).value;
    if (process.address == 0) return null;
    Pointer<Utf16>? buf;
    Pointer<Uint32>? size;
    try {
      buf = calloc<Uint16>(32768).cast<Utf16>();
      size = calloc<Uint32>()..value = 32768;
      if (!QueryFullProcessImageName(process, PROCESS_NAME_WIN32, PWSTR(buf), size)
          .value) {
        return null;
      }
      return buf.toDartString(length: size.value);
    } finally {
      if (size != null) calloc.free(size);
      if (buf != null) calloc.free(buf);
      CloseHandle(process);
    }
  }

  static String _stem(String path) {
    final base = path.split(r'\').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
