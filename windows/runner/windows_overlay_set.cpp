#include "windows_overlay_set.h"

#include <iostream>

namespace {

constexpr wchar_t kPanelClass[] = L"ORTHANT_OVERLAY_PANEL";

LRESULT CALLBACK PanelProc(HWND hwnd, UINT message, WPARAM wparam,
                           LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      // Never activate, even if a click ever reaches a panel. Orthant must
      // never become the frontmost window (CLAUDE.md invariants).
      return MA_NOACTIVATE;
    case WM_DPICHANGED:
      // A hidden panel keeps its rect: it exists to sit on its monitor and
      // report that monitor's DPI, which GetDpiForWindow now does. W3, which
      // shows these, owns resizing them.
      return 0;
    case WM_CLOSE:
      // Panels live until Reconcile or the destructor destroys them, and a
      // graceful taskkill or a close-all-windows tool must not take one away.
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  reinterpret_cast<std::vector<HMONITOR>*>(data)->push_back(monitor);
  return TRUE;
}

// Whether `monitor` is still attached. GetMonitorInfoW fails for one that has
// gone, between the change and the WM_DISPLAYCHANGE that reports it.
bool MonitorExists(HMONITOR monitor) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  return GetMonitorInfoW(monitor, &info) != FALSE;
}

}  // namespace

WindowsOverlaySet::WindowsOverlaySet() : instance_(GetModuleHandle(nullptr)) {
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = PanelProc;
  window_class.hInstance = instance_;
  window_class.lpszClassName = kPanelClass;
  const ATOM registered = RegisterClassExW(&window_class);
#ifndef NDEBUG
  if (registered == 0) {
    // Read before anything else runs: writing to cout can reset it.
    const DWORD error = GetLastError();
    std::cout << "[orthant] overlay panel class not registered, error "
              << error << std::endl;
  }
#else
  (void)registered;
#endif
  Reconcile("launch");
}

WindowsOverlaySet::~WindowsOverlaySet() {
  DestroyPanels();
  UnregisterClassW(kPanelClass, instance_);
}

void WindowsOverlaySet::DestroyPanels() {
  for (const auto& panel : panels_) {
    DestroyWindow(panel.hwnd);
  }
  panels_.clear();
}

void WindowsOverlaySet::Reconcile(const char* reason) {
  // Rebuilt rather than diffed. W1's panels have no engine, so a rebuild is a
  // handful of CreateWindowEx calls, and a window created on a monitor takes
  // that monitor's DPI at creation, the one property W1 needs. Keeping panels
  // whose HMONITOR survives starts to pay when W3 attaches an engine to each,
  // and is W3's to add.
  DestroyPanels();
  unpanelled_.clear();
  std::vector<HMONITOR> monitors;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                      reinterpret_cast<LPARAM>(&monitors));
  for (HMONITOR monitor : monitors) {
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) {
      continue;
    }
    const RECT& work = info.rcWork;
    HWND hwnd = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kPanelClass, L"", WS_POPUP,
        work.left, work.top, work.right - work.left, work.bottom - work.top,
        nullptr, nullptr, instance_, nullptr);
    if (hwnd) {
      panels_.push_back({monitor, hwnd});
    } else {
#ifndef NDEBUG
      const DWORD error = GetLastError();
      std::cout << "[orthant] overlay panel not created, error " << error
                << std::endl;
#endif
      unpanelled_.push_back(monitor);
    }
  }
#ifndef NDEBUG
  std::cout << "[orthant] displays reconciled (" << reason
            << "): " << panels_.size();
  for (const auto& display : Displays()) {
    std::cout << " [" << display.work.left << "," << display.work.top << " "
              << (display.work.right - display.work.left) << "x"
              << (display.work.bottom - display.work.top) << " @"
              << display.dpi << "]";
  }
  std::cout << std::endl;
#else
  (void)reason;
#endif
}

std::optional<WindowsOverlaySet::Display> WindowsOverlaySet::DisplayFor(
    const Panel& panel) const {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(panel.monitor, &info)) {
    return std::nullopt;
  }
  const UINT dpi = GetDpiForWindow(panel.hwnd);
  if (dpi == 0) {
    return std::nullopt;
  }
  return Display{info.rcWork, dpi};
}

std::vector<WindowsOverlaySet::Display> WindowsOverlaySet::Displays() const {
  // All or none, the rule Dart's displaysFromReply applies to this reply: a
  // shorter list lets displayContaining fall back to the first display and
  // place a window on the wrong monitor. A monitor that has gone is skipped,
  // since a WM_DISPLAYCHANGE and a reconcile follow; one still attached with
  // no working panel (never created, or destroyed: GetDpiForWindow answers 0)
  // empties the list, and Dart falls back to the cursor's display.
  for (HMONITOR monitor : unpanelled_) {
    if (MonitorExists(monitor)) {
      return {};
    }
  }
  std::vector<Display> displays;
  for (const auto& panel : panels_) {
    if (auto display = DisplayFor(panel)) {
      displays.push_back(*display);
    } else if (MonitorExists(panel.monitor)) {
      return {};
    }
  }
  return displays;
}

std::optional<WindowsOverlaySet::Display>
WindowsOverlaySet::DisplayUnderCursor() const {
  POINT cursor;
  if (!GetCursorPos(&cursor)) {
    return std::nullopt;
  }
  const HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  for (const auto& panel : panels_) {
    if (panel.monitor == monitor) {
      return DisplayFor(panel);
    }
  }
  return std::nullopt;
}
