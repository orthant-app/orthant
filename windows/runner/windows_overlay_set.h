#ifndef RUNNER_WINDOWS_OVERLAY_SET_H_
#define RUNNER_WINDOWS_OVERLAY_SET_H_

#include <windows.h>

#include <optional>
#include <vector>

// One resident overlay window per monitor. The twin of
// macos/Runner/OverlayPanelSet.swift (Windows design §3.2): any change to
// overlay session semantics is a two-file, two-platform, two-acceptance-suite
// change, and this comment exists so the second half is not forgotten.
//
// W1 builds only the windows: one hidden, engine-less window per monitor,
// covering its work area. They are load-bearing already, as the documented
// source of per-monitor DPI: GetDpiForMonitor's own documentation says it
// "should not be used if the calling thread is per-monitor DPI aware" and
// points to GetDpiForWindow, which needs a window on the monitor (spec §5.2).
// W3 attaches a Flutter engine to each and proves styles, transparency and the
// session protocol; until then nothing here is ever shown.
class WindowsOverlaySet {
 public:
  struct Display {
    RECT work;  // rcWork, physical pixels, top-left origin
    UINT dpi;   // GetDpiForWindow of this monitor's panel
  };

  WindowsOverlaySet();
  ~WindowsOverlaySet();

  WindowsOverlaySet(const WindowsOverlaySet&) = delete;
  WindowsOverlaySet& operator=(const WindowsOverlaySet&) = delete;

  // Rebuilds the panel set against the monitors that exist now. Called at
  // construction and on WM_DISPLAYCHANGE. `reason` is for the Debug log.
  void Reconcile(const char* reason);

  // Every monitor's work area and DPI, in enumeration order. The work area is
  // read live, so a taskbar that moved is current without a reconcile. A
  // panel whose monitor has gone, between the change and the WM_DISPLAYCHANGE
  // that reports it, is skipped rather than reported with a stale rect. A
  // monitor still attached with no working panel empties the list: all or
  // none, as Dart's displaysFromReply.
  std::vector<Display> Displays() const;

  // The monitor under the cursor, or nullopt if it has no panel yet.
  std::optional<Display> DisplayUnderCursor() const;

 private:
  struct Panel {
    HMONITOR monitor;
    HWND hwnd;
  };

  std::optional<Display> DisplayFor(const Panel& panel) const;
  void DestroyPanels();

  HINSTANCE instance_;
  std::vector<Panel> panels_;
  // Monitors the last Reconcile could not create a panel for.
  std::vector<HMONITOR> unpanelled_;
};

#endif  // RUNNER_WINDOWS_OVERLAY_SET_H_
