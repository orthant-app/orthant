#include "windows_overlay_set.h"

#include <dwmapi.h>
#include <flutter/dart_project.h>
#include <flutter/standard_method_codec.h>
#include <shellscalingapi.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <utility>

namespace {

constexpr wchar_t kPanelClass[] = L"ORTHANT_OVERLAY_PANEL";
constexpr char kOverlayChannel[] = "app.orthant/overlay";

// Posted to a panel by Dismiss: hide it, unless it has been shown again since.
// wparam is the panel's show count at the dismissal.
constexpr UINT kHidePanel = WM_APP + 1;
// Posted to a panel by its engine's next-frame callback. wparam is the show
// count the callback was registered for.
constexpr UINT kFramePresented = WM_APP + 2;
constexpr UINT_PTR kRevealTimer = 1;
constexpr UINT_PTR kWarmTimer = 2;
// On the host window, whose timer ids are shared with whatever else sets one
// there: hence values no small counter would reach.
constexpr UINT_PTR kStartEnginesTimer = 0x4F57;
// The next engine attaches on a timer, not a posted message: Windows delivers
// a timer only when no posted message is waiting, so a hotkey's notice and the
// work Dart does for it (posted, as all of an engine's tasks are) go first,
// and an attach takes the thread only when it is otherwise idle. Posted, the
// attaches queued ahead of that work, and a press made as the engines started
// waited for all of them (measured: 10.5 s in Debug on two displays).
constexpr UINT_PTR kAttachTimer = 0x4F58;
// How long a hotkey's notice, or the tray menu's, holds the next attach: long
// enough for Dart to say its command is running, which then holds it until
// the command is done.
constexpr ULONGLONG kAttachHoldMs = 1000;
// The longest Dart's commands may hold the attaches. A placement takes 2.8 s
// at most (windows_placement.dart), so this is three of the slowest queued,
// and a Dart that never says they are done cannot keep the overlay from ever
// being ready.
constexpr ULONGLONG kCommandsCeilingMs = 10000;

// The engines start when Dart says launch is done, or after this. Each takes
// over a second of the thread every engine shares (measured), and started
// first they made the hotkeys and the tray wait for all of them. The deadline
// is for a launch that never says so, so it must be longer than any launch
// that does, in every build, or it brings the old ordering back: Dart's
// launch said so 0.06 s after the panels existed in Profile and 0.6 s in
// Debug (measured, in the VM).
constexpr UINT kStartEnginesDeadlineMs = 10000;
// A failed engine attach is tried again after this, and at most this many
// times a panel, and again whenever the displays change: a panel with no
// engine refuses every summon, but each attempt costs over a second of the
// thread every engine shares.
constexpr UINT_PTR kAttachRetryTimer = 0x4F59;
constexpr UINT kAttachRetryMs = 10000;
constexpr int kAttachAttempts = 3;

// WM_DPICHANGED_BEFOREPARENT, spelled out: WinUser.h defines it only for
// WINVER >= 0x0605.
constexpr UINT kDpiChangedBeforeParent = 0x02E2;

// A panel is revealed on its engine's next presented frame, or after this.
// Measured in the VM: a warm summon's frame is presented in 50-100 ms.
constexpr UINT kRevealDeadlineMs = 250;
// A warm-up whose frame never comes must not leave a shown, cloaked panel.
constexpr UINT kWarmDeadlineMs = 2000;
// A hotkey summon reaching Show later than this after its press waited behind
// something: this thread (an engine attaching takes over a second, measured),
// or a placement ahead of it in Dart's command queue. Shown now, it would take
// Esc, Enter and the arrows from whatever the user has moved on to. Each
// summon carries its own press time, through Dart and back in showOverlay, so
// two presses cannot share one, and nothing is left over to be mistaken for a
// later summon's.
constexpr double kStaleSummonMs = 1000;

struct Grab {
  int id;
  UINT modifiers;
  UINT vk;
  bool required;
  const char* name;
};

// The overlay's key grabs, with macOS's ids (HotkeyManager.swift) so a log
// line means the same thing on both. VK_RETURN covers keypad Enter as well, so
// macOS's separate keypad id has no twin. Esc and Enter come first and are
// required: without Esc the overlay has no keyboard way out, and without Enter
// a press meant to commit reaches the app behind. Ctrl+S and the arrows take
// nothing the overlay needs to stay honest, so a refusal costs only that key.
constexpr Grab kGrabs[] = {
    {901, 0, VK_ESCAPE, true, "Esc"},
    {902, 0, VK_RETURN, true, "Enter"},
    {904, MOD_CONTROL, 'S', false, "Ctrl+S"},
    {910, 0, VK_LEFT, false, "Left"},
    {911, 0, VK_RIGHT, false, "Right"},
    {912, 0, VK_UP, false, "Up"},
    {913, 0, VK_DOWN, false, "Down"},
    {914, MOD_SHIFT, VK_LEFT, false, "Shift+Left"},
    {915, MOD_SHIFT, VK_RIGHT, false, "Shift+Right"},
    {916, MOD_SHIFT, VK_UP, false, "Shift+Up"},
    {917, MOD_SHIFT, VK_DOWN, false, "Shift+Down"},
};
constexpr int kGrabEsc = 901;
constexpr int kGrabEnter = 902;
constexpr int kGrabSave = 904;
constexpr int kGrabArrowFirst = 910;
constexpr int kGrabArrowLast = 917;
constexpr const char* kDirections[] = {"left", "right", "up", "down"};

// Debug and Profile builds log; Release is silent. The acceptance harness
// parses these lines: change a format only together with it.
void DevLog(const std::string& line) {
#ifdef ORTHANT_DEV_BUILD
  std::cout << "[orthant] " << line << std::endl;
#else
  (void)line;
#endif
}

std::string Ms(double ms) {
  std::ostringstream text;
  text << std::fixed << std::setprecision(1) << ms;
  return text.str();
}

// Milliseconds since the Unix epoch: the clock Dart's DateTime.now() reads,
// so a trigger stamped here and a first frame timed there subtract.
double EpochMs() {
  FILETIME file_time;
  GetSystemTimePreciseAsFileTime(&file_time);
  ULARGE_INTEGER t;
  t.LowPart = file_time.dwLowDateTime;
  t.HighPart = file_time.dwHighDateTime;
  return static_cast<double>(t.QuadPart - 116444736000000000ULL) / 10000.0;
}

double MsSince(LARGE_INTEGER start) {
  LARGE_INTEGER frequency, now;
  QueryPerformanceFrequency(&frequency);
  QueryPerformanceCounter(&now);
  return static_cast<double>(now.QuadPart - start.QuadPart) * 1000.0 /
         static_cast<double>(frequency.QuadPart);
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  reinterpret_cast<std::vector<HMONITOR>*>(data)->push_back(monitor);
  return TRUE;
}

std::vector<HMONITOR> Monitors() {
  std::vector<HMONITOR> monitors;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                      reinterpret_cast<LPARAM>(&monitors));
  return monitors;
}

bool WorkArea(HMONITOR monitor, RECT* work) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) return false;
  *work = info.rcWork;
  return true;
}

// Whether `monitor` is still attached. GetMonitorInfoW fails for one that has
// gone, between the change and the reconcile that follows it.
bool MonitorExists(HMONITOR monitor) {
  RECT work;
  return WorkArea(monitor, &work);
}

// The monitor's effective DPI as Windows applies it now. Used to notice that a
// panel's own DPI is stale: Fit nudges the panel when the two disagree, and
// until it has, DisplayFor reports no display for it. The display list answers
// from GetDpiForWindow, the documented source for a per-monitor-aware thread.
UINT MonitorDpi(HMONITOR monitor) {
  UINT x = 0, y = 0;
  return SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &x, &y)) ? x
                                                                          : 0;
}

// The set whose session the foreground hook watches. One overlay set exists
// per process, and a WinEvent callback carries no context of its own.
WindowsOverlaySet* g_foreground_watcher = nullptr;

// The shell's own surfaces: the desktop (Win+D), the taskbars, the tray's
// overflow, Start and Search, Alt+Tab (whose first foreground window is a
// ForegroundStaging, measured) and Task View. Explorer owns most of them, and
// a File Explorer window can share its process (on the VM it had one of its
// own), so for a grid opened over a File Explorer window the process alone
// cannot tell the user going elsewhere from the target: these end a grid
// whatever their process. Every class the capture skips as a target is here
// (windows_capture.dart's three sets; menus aside, since the captured app's
// own menu is not the user going elsewhere), and a test holds this list to
// that. ForegroundStaging and MultitaskingViewFrame are here too and in none
// of those sets.
constexpr const wchar_t* kShellSurfaces[] = {
    L"Progman",
    L"WorkerW",
    L"Shell_TrayWnd",
    L"Shell_SecondaryTrayWnd",
    L"NotifyIconOverflowWindow",
    L"TopLevelWindowForOverflowXamlIsland",
    L"Windows.UI.Core.CoreWindow",
    L"XamlExplorerHostIslandWindow",
    L"ForegroundStaging",
    L"MultitaskingViewFrame",
};

bool IsShellSurface(HWND hwnd) {
  wchar_t name[64] = {};
  const int length = GetClassNameW(hwnd, name, 64);
  if (length <= 0) return false;
  for (const wchar_t* cls : kShellSurfaces) {
    if (wcscmp(name, cls) == 0) return true;
  }
  return false;
}

const flutter::EncodableValue* Field(const flutter::EncodableMap& map,
                                     const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<int64_t> IntOf(const flutter::EncodableValue* value) {
  if (!value) return std::nullopt;
  if (const auto* v = std::get_if<int32_t>(value)) return *v;
  if (const auto* v = std::get_if<int64_t>(value)) return *v;
  return std::nullopt;
}

std::optional<double> NumberOf(const flutter::EncodableValue* value) {
  std::optional<double> number;
  if (const auto* d = value ? std::get_if<double>(value) : nullptr) {
    number = *d;
  } else if (const auto i = IntOf(value)) {
    number = static_cast<double>(*i);
  }
  if (number && !std::isfinite(*number)) return std::nullopt;
  return number;
}

// The session a call names: {sessionId: n, ...}, or a bare n; -1 for neither.
int64_t SessionOf(const flutter::EncodableValue* arguments) {
  if (!arguments) return -1;
  if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
    return IntOf(Field(*map, "sessionId")).value_or(-1);
  }
  return IntOf(arguments).value_or(-1);
}

}  // namespace

struct WindowsOverlaySet::Panel {
  WindowsOverlaySet* owner = nullptr;
  int index = 0;               // creation order, for logs
  HMONITOR monitor = nullptr;  // null while parked
  HWND hwnd = nullptr;
  std::unique_ptr<flutter::FlutterViewController> controller;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  // The last summon sent, replayed if it arrived before overlayMain's handler
  // was live (macOS OverlayPanel.lastSummon).
  std::optional<flutter::EncodableValue> last_summon;
  bool attach_failed = false;  // until the next retry or display change
  int attach_attempts = 0;
  bool ready = false;      // overlayMain's handler is live
  bool warming = false;    // the launch warm-up has started
  bool warm = false;       // and finished
  bool cloaked = false;
  uint64_t shows = 0;      // every show, the warm-up's included
  // A next-frame callback is registered and not yet delivered. The engine
  // keeps one, and registering over one still in flight can leave it calling
  // an empty function, which terminates the process (read in the engine's
  // source, 3.47.4): so a panel never has two, and a show that finds one
  // pending lets it arrive and arms again (OnFramePresented).
  bool frame_armed = false;

  HWND View() const {
    return controller && controller->view()
               ? controller->view()->GetNativeWindow()
               : nullptr;
  }
};

WindowsOverlaySet::WindowsOverlaySet(HWND host, Forward forward)
    : instance_(GetModuleHandle(nullptr)),
      host_(host),
      forward_(std::move(forward)),
      reconcile_message_(RegisterWindowMessageW(L"OrthantOverlayReconcile")) {
  QueryPerformanceCounter(&started_);
#ifdef ORTHANT_DEV_BUILD
  char fail[8] = {};
  if (GetEnvironmentVariableA("ORTHANT_DEBUG_FAIL_ATTACHES", fail, 8) > 0) {
    attaches_to_fail_ = atoi(fail);
  }
#endif
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = PanelProc;
  window_class.hInstance = instance_;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kPanelClass;
  if (RegisterClassExW(&window_class) == 0) {
    // Read before anything else runs: writing to cout can reset it.
    const DWORD error = GetLastError();
    DevLog("overlay panel class not registered, error " +
           std::to_string(error));
  }
  // Windows now, engines later: the windows are a few CreateWindowEx calls and
  // answer the display list at once, while each engine costs over a second of
  // this thread (measured). They attach one per turn of the message loop, and
  // only once launch has done what must answer first (StartEngines).
  Reconcile("launch");
  SetTimer(host_, kStartEnginesTimer, kStartEnginesDeadlineMs, nullptr);
}

WindowsOverlaySet::~WindowsOverlaySet() {
  KillTimer(host_, kStartEnginesTimer);
  KillTimer(host_, kAttachTimer);
  KillTimer(host_, kAttachRetryTimer);
  Unhook();
  ReleaseKeys();
  for (auto& panel : panels_) {
    if (panel->channel) panel->channel->SetMethodCallHandler(nullptr);
    panel->channel.reset();
    panel->controller.reset();  // shuts its engine down
    if (panel->hwnd) DestroyWindow(panel->hwnd);
  }
  panels_.clear();
  UnregisterClassW(kPanelClass, instance_);
}

// ---------------------------------------------------------------- panels

LRESULT CALLBACK WindowsOverlaySet::PanelProc(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* panel =
      reinterpret_cast<Panel*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (panel && panel->owner) {
    return panel->owner->HandlePanelMessage(*panel, hwnd, message, wparam,
                                            lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT WindowsOverlaySet::HandlePanelMessage(Panel& panel, HWND hwnd,
                                              UINT message, WPARAM wparam,
                                              LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      // Never activate, even when clicked: the window being placed keeps
      // foreground (measured: a click on a panel left it with Notepad).
      return MA_NOACTIVATE;
    case WM_CLOSE:
      // Panels live as long as the set; a graceful taskkill or a
      // close-all-windows tool must not take one away.
      return 0;
    case WM_SIZE:
      if (HWND view = panel.View()) {
        MoveWindow(view, 0, 0, LOWORD(lparam), HIWORD(lparam), TRUE);
      }
      return 0;
    case WM_DPICHANGED:
      OnPanelDpiChanged(panel, HIWORD(wparam));
      return 0;
    case WM_TIMER:
      if (wparam == kRevealTimer) {
        KillTimer(hwnd, kRevealTimer);
        if (session_) Reveal(panel, "deadline");
        return 0;
      }
      if (wparam == kWarmTimer) {
        EndWarm(panel, panel.shows, "deadline");
        return 0;
      }
      break;
    case kHidePanel:
      if (static_cast<uint64_t>(wparam) == panel.shows) {
        ShowWindow(hwnd, SW_HIDE);
      }
      return 0;
    case kFramePresented:
      OnFramePresented(panel, static_cast<uint64_t>(wparam));
      return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

WindowsOverlaySet::Panel* WindowsOverlaySet::CreatePanel(HMONITOR monitor) {
  RECT work;
  if (!WorkArea(monitor, &work)) return nullptr;
  auto panel = std::make_unique<Panel>();
  panel->owner = this;
  panel->index = next_index_++;
  panel->monitor = monitor;
  // Created on its monitor, so it has that monitor's DPI from the start.
  // WS_EX_NOACTIVATE (and MA_NOACTIVATE above): never the foreground window.
  // WS_EX_TOOLWINDOW: no taskbar button or Alt+Tab entry, and not managed by
  // virtual desktops, so it shows on whichever desktop is current (measured).
  // WS_EX_TOPMOST: above the window being placed. Not WS_EX_LAYERED: the DWM
  // frame below is what makes it transparent.
  panel->hwnd = CreateWindowExW(
      WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kPanelClass, L"",
      WS_POPUP, work.left, work.top, work.right - work.left,
      work.bottom - work.top, nullptr, nullptr, instance_, panel.get());
  if (!panel->hwnd) {
    const DWORD error = GetLastError();
    DevLog("overlay panel not created, error " + std::to_string(error));
    return nullptr;
  }
  // Transparency. The engine clears to transparent black and draws into a
  // plain window surface; a frame extended over the whole client area makes
  // DWM compose those pixels as see-through (measured: without it the panel
  // is opaque black).
  const MARGINS margins{-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(panel->hwnd, &margins);
  panels_.push_back(std::move(panel));
  return panels_.back().get();
}

void WindowsOverlaySet::Reconcile(const char* reason) {
  // A SetWindowPos in Fit can dispatch messages back into this object while it
  // walks the panels (measured: a broadcast WM_DISPLAYCHANGE arrived inside a
  // panel's resize). Re-entry only asks for one more pass.
  if (reconciling_) {
    reconcile_again_ = true;
    return;
  }
  // Panels are about to move between monitors, and no session may outlive
  // that. A display change has ended it already; this covers any other way in.
  Dismiss(reason);
  reconciling_ = true;
  int parked = 0, reused = 0, created = 0;
  do {
    reconcile_again_ = false;
    const std::vector<HMONITOR> monitors = Monitors();
    for (auto& panel : panels_) {
      if (panel->monitor && std::find(monitors.begin(), monitors.end(),
                                      panel->monitor) == monitors.end()) {
        // Its monitor is gone. Parked, not destroyed, and kept for the next
        // monitor that comes. A session's panels are off the screen already:
        // a display change dismisses before it reconciles. A warm-up in
        // flight is not a session, so Dismiss leaves it shown and cloaked, and
        // its late frame would reveal it during the next session: it ends
        // here, hidden, once the panel is off Live() so NoteReady does not
        // count it. A panel whose warm-up never started has nothing to end.
        panel->monitor = nullptr;
        if (panel->warming && !panel->warm) {
          EndWarm(*panel, panel->shows, "parked");
        }
        parked++;
      }
    }
    for (HMONITOR monitor : monitors) {
      if (PanelFor(monitor)) continue;
      if (Panel* spare = Parked()) {
        spare->monitor = monitor;
        // Its warm-up, if it had one, rendered another monitor's size and
        // scale, or was ended by the park before its frame: warmed again
        // below, so the first summon on this monitor is not a cold one.
        spare->warming = false;
        spare->warm = false;
        reused++;
      } else if (CreatePanel(monitor)) {
        created++;
      }
    }
    for (Panel* panel : Live()) Fit(*panel);
  } while (reconcile_again_);
  reconciling_ = false;
  // A monitor that came or went is a new chance for an engine that failed to
  // attach: whatever made it fail may have been that display's, and a parked
  // panel that failed would otherwise go to the next monitor without one. A
  // work-area or scale change is not, or a failing engine would cost the
  // thread another three attempts each time the taskbar moved.
  if (parked || reused || created) {
    for (auto& panel : panels_) {
      panel->attach_failed = false;
      panel->attach_attempts = 0;
    }
  }
  // Reused panels whose engine is listening: warmed now, at their new size.
  // One whose overlayMain is not yet listening warms when it says so.
  for (Panel* panel : Live()) {
    if (panel->ready) Warm(*panel);
  }

  std::ostringstream line;
  const std::vector<Display> displays = Displays();
  line << "displays reconciled (" << reason << "): " << displays.size();
  for (const auto& display : displays) {
    line << " [" << display.work.left << "," << display.work.top << " "
         << (display.work.right - display.work.left) << "x"
         << (display.work.bottom - display.work.top) << " @" << display.dpi
         << "]";
  }
  line << " parked=" << parked << " reused=" << reused
       << " created=" << created;
  DevLog(line.str());
  ScheduleAttach();
}

void WindowsOverlaySet::Fit(Panel& panel) {
  RECT work, now;
  if (!panel.monitor || !WorkArea(panel.monitor, &work)) return;
  const int width = work.right - work.left;
  const int height = work.bottom - work.top;
  if (GetWindowRect(panel.hwnd, &now) && !EqualRect(&now, &work)) {
    SetWindowPos(panel.hwnd, nullptr, work.left, work.top, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  // Windows re-evaluates a window's DPI only when the window's rect changes
  // (measured): a scale change that leaves this work area alone, as on a
  // monitor with no taskbar, would leave the panel, and the display list, at
  // the old scale. A one-pixel resize and back makes it look again; the
  // WM_DPICHANGED arrives inside the first call.
  const UINT monitor_dpi = MonitorDpi(panel.monitor);
  if (monitor_dpi != 0 && GetDpiForWindow(panel.hwnd) != monitor_dpi) {
    SetWindowPos(panel.hwnd, nullptr, work.left, work.top, width, height - 1,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    SetWindowPos(panel.hwnd, nullptr, work.left, work.top, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    DevLog("overlay panel " + std::to_string(panel.index) + " nudged: " +
           std::to_string(GetDpiForWindow(panel.hwnd)) + " dpi, monitor " +
           std::to_string(monitor_dpi));
  }
}

void WindowsOverlaySet::OnPanelDpiChanged(Panel& panel, UINT dpi) {
  // Windows' suggested rect keeps the panel's logical size, which is not what
  // a panel wants: it covers its monitor's work area, whatever the scale.
  RECT work, now;
  if (panel.monitor && WorkArea(panel.monitor, &work) &&
      GetWindowRect(panel.hwnd, &now) && !EqualRect(&now, &work)) {
    SetWindowPos(panel.hwnd, nullptr, work.left, work.top,
                 work.right - work.left, work.bottom - work.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  // The view learned the new DPI from the WM_DPICHANGED_BEFOREPARENT Windows
  // sent it first, but it tells the engine only on a WM_SIZE.
  if (HWND view = panel.View()) {
    RECT client;
    GetClientRect(panel.hwnd, &client);
    SendMessageW(view, WM_SIZE, SIZE_RESTORED,
                 MAKELPARAM(client.right, client.bottom));
  }
  DevLog("overlay panel " + std::to_string(panel.index) + " now at " +
         std::to_string(dpi) + " dpi");
  // A live session was laid out at the old scale.
  Dismiss("WM_DPICHANGED");
}

void WindowsOverlaySet::ScheduleAttach() {
  // A menu that is open, or a session that is live, schedules again when it
  // ends (MenuLoop, Dismiss): an attach would freeze either for its length.
  if (!engines_started_ || menu_open_ || session_) return;
  for (const auto& panel : panels_) {
    if (!panel->controller && !panel->attach_failed) {
      // Setting the timer again replaces it, so the latest wait wins: a
      // hotkey's hold, or Dart's commands up to their ceiling.
      const ULONGLONG now = GetTickCount64();
      ULONGLONG until = hold_until_;
      if (commands_running_) {
        until = (std::max)(until, commands_since_ + kCommandsCeilingMs);
      }
      const UINT wait = until > now ? static_cast<UINT>(until - now)
                                    : USER_TIMER_MINIMUM;
      SetTimer(host_, kAttachTimer, wait, nullptr);
      return;
    }
  }
}

void WindowsOverlaySet::HoldAttaches() {
  hold_until_ = GetTickCount64() + kAttachHoldMs;
  ScheduleAttach();
}

bool WindowsOverlaySet::AttachHeld() {
  const ULONGLONG now = GetTickCount64();
  if (now < hold_until_) return true;
  if (!commands_running_) return false;
  if (now < commands_since_ + kCommandsCeilingMs) return true;
  if (!commands_ceiling_logged_) {
    commands_ceiling_logged_ = true;
    DevLog("overlay attaches go on: commands still running after " +
           std::to_string(kCommandsCeilingMs) + " ms");
  }
  return false;
}

void WindowsOverlaySet::CommandsRunning(bool running) {
  if (running == commands_running_) return;
  commands_running_ = running;
  if (running) {
    commands_since_ = GetTickCount64();
    commands_ceiling_logged_ = false;
  }
  DevLog(running ? "overlay commands running" : "overlay commands done");
  ScheduleAttach();  // the timer again, with the new wait
}

void WindowsOverlaySet::MenuLoop(bool open) {
  menu_open_ = open;
  if (open) {
    KillTimer(host_, kAttachTimer);
  } else {
    HoldAttaches();  // the menu's command, if one was chosen, runs next
  }
}

void WindowsOverlaySet::AttachNext() {
  // One engine per timer (kAttachTimer), never during a hold, an open menu or
  // a session: each costs over a second of this thread in the VM (measured),
  // and the main isolate, the hotkeys, the tray and the grid must not wait for
  // it. A panel on a monitor goes before a parked one.
  Panel* next = nullptr;
  for (const auto& panel : panels_) {
    if (panel->controller || panel->attach_failed) continue;
    if (!next || (panel->monitor && !next->monitor)) next = panel.get();
  }
  if (next) AttachEngine(*next);
  ScheduleAttach();
}

void WindowsOverlaySet::AttachEngine(Panel& panel) {
  RECT client;
  GetClientRect(panel.hwnd, &client);
  LARGE_INTEGER start;
  QueryPerformanceCounter(&start);
  ++panel.attach_attempts;
#ifdef ORTHANT_DEV_BUILD
  if (attaches_to_fail_ > 0) {
    --attaches_to_fail_;
    AttachFailed(panel, "failed on purpose");
    return;
  }
#endif
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint("overlayMain");
  // No plugins on this engine: overlayMain uses none, and a second copy of
  // each would be resident for nothing (macOS OverlayPanel does the same).
  auto controller = std::make_unique<flutter::FlutterViewController>(
      client.right, client.bottom, project);
  if (!controller->engine() || !controller->view()) {
    AttachFailed(panel, "not created");
    return;
  }
  panel.controller = std::move(controller);
  HWND view = panel.View();
  SetParent(view, panel.hwnd);
  // The view took its first DPI from the primary monitor and changes it only
  // on WM_DPICHANGED_BEFOREPARENT, so on a monitor at another scale it would
  // render at the wrong one (measured: 1.0 on a 150 % panel). Ask it to read
  // its DPI again now that it is parented; then a WM_SIZE, even at the same
  // size, makes it send the engine its metrics at that DPI.
  SendMessageW(view, kDpiChangedBeforeParent, 0, 0);
  MoveWindow(view, 0, 0, client.right, client.bottom, TRUE);
  SendMessageW(view, WM_SIZE, SIZE_RESTORED,
               MAKELPARAM(client.right, client.bottom));

  panel.channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          panel.controller->engine()->messenger(), kOverlayChannel,
          &flutter::StandardMethodCodec::GetInstance());
  Panel* raw = &panel;
  panel.channel->SetMethodCallHandler(
      [this, raw](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        HandleOverlayCall(*raw, call);
        result->Success();
      });
  DevLog("overlay engine attached: panel " + std::to_string(panel.index) +
         " in " + Ms(MsSince(start)) + " ms");
}

void WindowsOverlaySet::AttachFailed(Panel& panel, const char* why) {
  panel.attach_failed = true;
  const bool again = panel.attach_attempts < kAttachAttempts;
  DevLog("overlay engine " + std::string(why) + " for panel " +
         std::to_string(panel.index) + " (attempt " +
         std::to_string(panel.attach_attempts) + ")" +
         (again ? "; retrying" : "; giving up until the displays change"));
  if (again && !attach_retry_set_) {
    attach_retry_set_ =
        SetTimer(host_, kAttachRetryTimer, kAttachRetryMs, nullptr) != 0;
  }
}

void WindowsOverlaySet::RetryAttaches() {
  KillTimer(host_, kAttachRetryTimer);
  attach_retry_set_ = false;
  for (auto& panel : panels_) {
    if (panel->attach_failed && panel->attach_attempts < kAttachAttempts) {
      panel->attach_failed = false;
    }
  }
  ScheduleAttach();
}

std::vector<WindowsOverlaySet::Panel*> WindowsOverlaySet::Live() const {
  std::vector<Panel*> live;
  for (const auto& panel : panels_) {
    if (panel->monitor) live.push_back(panel.get());
  }
  return live;
}

WindowsOverlaySet::Panel* WindowsOverlaySet::PanelFor(
    HMONITOR monitor) const {
  if (!monitor) return nullptr;
  for (const auto& panel : panels_) {
    if (panel->monitor == monitor) return panel.get();
  }
  return nullptr;
}

WindowsOverlaySet::Panel* WindowsOverlaySet::Parked() const {
  Panel* found = nullptr;
  for (const auto& panel : panels_) {
    if (panel->monitor) continue;
    // One that already has an engine first: that is the point of parking.
    if (!found || (panel->controller && !found->controller)) {
      found = panel.get();
    }
  }
  return found;
}

std::optional<WindowsOverlaySet::Display> WindowsOverlaySet::DisplayFor(
    const Panel& panel) const {
  RECT work;
  if (!panel.monitor || !WorkArea(panel.monitor, &work)) return std::nullopt;
  const UINT dpi = GetDpiForWindow(panel.hwnd);
  if (dpi == 0) return std::nullopt;
  // A panel learns a scale change only when Fit, on a later turn of the loop,
  // nudges it (measured: Windows re-reads a static window's DPI only when its
  // rect changes). Until then its DPI is the old one, which would scale a
  // gap wrongly: no display rather than a stale one, so the list is empty for
  // that moment, as it is while a monitor that has just come has no panel.
  const UINT monitor_dpi = MonitorDpi(panel.monitor);
  if (monitor_dpi != 0 && monitor_dpi != dpi) return std::nullopt;
  return Display{work, dpi};
}

std::vector<WindowsOverlaySet::Display> WindowsOverlaySet::Displays() const {
  // All or none, the rule Dart's displaysFromReply applies to this reply: a
  // shorter list lets displayContaining fall back to the first display and
  // place a window on the wrong monitor. A monitor still attached with no
  // panel empties the list: one the last reconcile could not give a panel,
  // or one that has arrived since, for the turn of the loop before the
  // reconcile WM_DISPLAYCHANGE posted runs. A live panel whose monitor has
  // gone is skipped, since a reconcile follows; one whose monitor is still
  // attached but whose display cannot be read empties the list. Empty means
  // "no display list", not "no displays": Dart then places only on the
  // cursor's display, and only a window that is on it.
  for (HMONITOR monitor : Monitors()) {
    if (!PanelFor(monitor)) return {};
  }
  std::vector<Display> displays;
  for (const Panel* panel : Live()) {
    if (auto display = DisplayFor(*panel)) {
      displays.push_back(*display);
    } else if (MonitorExists(panel->monitor)) {
      return {};
    }
  }
  return displays;
}

std::optional<WindowsOverlaySet::Display>
WindowsOverlaySet::DisplayUnderCursor() const {
  POINT cursor;
  if (!GetCursorPos(&cursor)) return std::nullopt;
  const Panel* panel =
      PanelFor(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST));
  return panel ? DisplayFor(*panel) : std::nullopt;
}

void WindowsOverlaySet::OnDisplayChange(const char* reason) {
  // A session was laid out for the old geometry: end it now, as macOS does on
  // any screen change.
  Dismiss(reason);
  if (reconcile_posted_) return;
  reconcile_reason_ = reason;
  reconcile_posted_ =
      PostMessageW(host_, reconcile_message_, 0, 0) != FALSE;
}

void WindowsOverlaySet::StartEngines(const char* why) {
  if (engines_started_) return;
  engines_started_ = true;
  KillTimer(host_, kStartEnginesTimer);
  DevLog(std::string("overlay engines starting (") + why + "), " +
         Ms(MsSince(started_)) + " ms after launch");
  ScheduleAttach();
}

bool WindowsOverlaySet::HandleHostMessage(UINT message, WPARAM wparam) {
  if (message == WM_TIMER && wparam == kStartEnginesTimer) {
    StartEngines("deadline");
    return true;
  }
  if (message == WM_TIMER && wparam == kAttachTimer) {
    KillTimer(host_, kAttachTimer);
    // A hold a later hotkey extended, commands that started, or a menu or a
    // session opened since it was set.
    if (menu_open_ || session_ || AttachHeld()) {
      ScheduleAttach();
    } else {
      AttachNext();
    }
    return true;
  }
  if (message == WM_TIMER && wparam == kAttachRetryTimer) {
    RetryAttaches();
    return true;
  }
  if (message == 0) return false;  // a registration that failed
  if (message == reconcile_message_) {
    reconcile_posted_ = false;
    Reconcile(reconcile_reason_);
    return true;
  }
  return false;
}

// ---------------------------------------------------------------- session

bool WindowsOverlaySet::HandleHotkey(int id) {
  if (id < kFirstGrabId || id > kGrabArrowLast) {
    // Swallowed while a session is live (macOS suppressesRegionHotkeys): a
    // shortcut would capture anew underneath an open grid.
    return session_.has_value();
  }
  if (!session_) return true;
  if (id == kGrabEsc) {
    Dismiss("Esc");
  } else if (id == kGrabEnter) {
    Relay("commitCurrent", flutter::EncodableValue(session_->id));
  } else if (id == kGrabSave) {
    Relay("saveCurrent", flutter::EncodableValue(session_->id));
  } else if (id >= kGrabArrowFirst) {
    const int index = id - kGrabArrowFirst;
    Relay("moveSelection",
          flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("sessionId"),
               flutter::EncodableValue(session_->id)},
              {flutter::EncodableValue("direction"),
               flutter::EncodableValue(std::string(kDirections[index % 4]))},
              {flutter::EncodableValue("extend"),
               flutter::EncodableValue(index >= 4)},
          }));
  }
  return true;
}

double WindowsOverlaySet::PressTick(LONG message_time) {
  // The press, not the dispatch: a WM_HOTKEY waits in the queue while this
  // thread is busy (an engine attaching takes over a second, measured), and
  // that wait is what the stale check is for. A message time is the low 32
  // bits of the same tick count, to its resolution.
  const ULONGLONG now = GetTickCount64();
  const DWORD queued =
      static_cast<DWORD>(now) - static_cast<DWORD>(message_time);
  return static_cast<double>(now - queued);
}

void WindowsOverlaySet::SetGrid(int cols, int rows, double gap,
                                bool save_hint) {
  cols_ = cols;
  rows_ = rows;
  gap_ = gap;
  save_hint_ = save_hint;
}

flutter::EncodableMap WindowsOverlaySet::SummonPayload(
    const Panel& panel, int64_t session_id, double trigger_ms,
    const std::string& app_name, const std::vector<uint8_t>& app_icon,
    bool active, bool warm) const {
  RECT work{};
  WorkArea(panel.monitor, &work);
  const UINT dpi = GetDpiForWindow(panel.hwnd);
  flutter::EncodableMap payload{
      {flutter::EncodableValue("sessionId"), flutter::EncodableValue(session_id)},
      {flutter::EncodableValue("triggerMs"), flutter::EncodableValue(trigger_ms)},
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(work.left))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(work.top))},
      {flutter::EncodableValue("w"),
       flutter::EncodableValue(static_cast<double>(work.right - work.left))},
      {flutter::EncodableValue("h"),
       flutter::EncodableValue(static_cast<double>(work.bottom - work.top))},
      // Display units per logical pixel of this panel: the overlay converts
      // with it where its two spaces meet.
      {flutter::EncodableValue("scale"),
       flutter::EncodableValue(static_cast<double>(dpi) /
                               USER_DEFAULT_SCREEN_DPI)},
      {flutter::EncodableValue("appName"), flutter::EncodableValue(app_name)},
      {flutter::EncodableValue("active"), flutter::EncodableValue(active)},
      {flutter::EncodableValue("cols"), flutter::EncodableValue(cols_)},
      {flutter::EncodableValue("rows"), flutter::EncodableValue(rows_)},
      {flutter::EncodableValue("gap"), flutter::EncodableValue(gap_)},
      {flutter::EncodableValue("saveHint"), flutter::EncodableValue(save_hint_)},
  };
  if (!app_icon.empty()) {
    payload[flutter::EncodableValue("appIcon")] =
        flutter::EncodableValue(app_icon);
  }
  if (warm) {
    payload[flutter::EncodableValue("warm")] = flutter::EncodableValue(true);
  }
  return payload;
}

WindowsOverlaySet::ShowResult WindowsOverlaySet::Show(
    int64_t session_id, const std::string& app_name,
    const std::vector<uint8_t>& app_icon, double pressed_ms,
    DWORD owner_pid) {
  // Timed from the summon's key press when there is one, as macOS times from
  // its Carbon press; a tray summon has none (0) and is timed from here. The
  // age is read on the tick clock the press was stamped on; the trigger the
  // overlay times its first frame from is that press, in Dart's clock.
  const double now = EpochMs();
  const double age =
      pressed_ms > 0 ? static_cast<double>(GetTickCount64()) - pressed_ms : 0;
  // A press from the future is no press of ours (the tick is this machine's
  // and monotonic): stale, not fresh.
  if (pressed_ms > 0 && (age > kStaleSummonMs || age < 0)) {
    DevLog("overlay summon refused: stale, " + Ms(age) +
           " ms after its hotkey");
    MessageBeep(MB_OK);
    return ShowResult::kStale;
  }
  const double trigger = pressed_ms > 0 ? now - age : now;

  // Not while the panels are being re-read after a display change, whose
  // geometry and DPI are mid-change; and not from inside a resize, which can
  // run this very call (a view's blocking resize runs every engine's tasks,
  // read in the engine's source), including Show's own Fit below.
  if (showing_ || reconciling_ || reconcile_posted_) {
    DevLog("overlay summon refused: displays changing");
    MessageBeep(MB_OK);
    return ShowResult::kNotReady;
  }
  struct InShow {
    bool* flag;
    explicit InShow(bool* f) : flag(f) { *flag = true; }
    ~InShow() { *flag = false; }
  } in_show(&showing_);

  // A tray summon while a session is live: Dart has already captured anew, so
  // the open grid names a capture that is gone and every commit from it would
  // be dropped. End it, and show the new one.
  if (session_) Dismiss("replaced");

  // Every monitor needs a panel with an engine, or the summon would leave a
  // display uncovered. Only possible in the seconds after launch, while the
  // engines attach, or just after a monitor arrives.
  for (HMONITOR monitor : Monitors()) {
    const Panel* panel = PanelFor(monitor);
    if (!panel || !panel->channel) {
      DevLog("overlay summon refused: engines not ready");
      MessageBeep(MB_OK);
      return ShowResult::kNotReady;
    }
  }
  // Before anything is on screen, so a refusal can abort cleanly (macOS
  // grabOverlayKeys).
  if (!GrabKeys()) {
    ReleaseKeys();
    MessageBeep(MB_OK);
    return ShowResult::kKeysRefused;
  }
  // Each panel exactly on its work area, at its monitor's DPI. Normally a
  // no-op, because display changes re-fit already; done before the session
  // exists, so a WM_DPICHANGED it provokes cannot end it.
  for (Panel* panel : Live()) Fit(*panel);
  // A resize there can deliver a display change (measured), whose reconcile
  // would re-assign these panels under the session about to start: give the
  // summon up instead, and let the reconcile run.
  if (reconcile_posted_ || reconciling_) {
    ReleaseKeys();
    DevLog("overlay summon refused: displays changing");
    MessageBeep(MB_OK);
    return ShowResult::kNotReady;
  }

  session_ = Session{session_id, trigger, owner_pid};
  POINT cursor{};
  GetCursorPos(&cursor);
  const HMONITOR under = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  for (Panel* panel : Live()) {
    const bool active = panel->monitor == under;
    if (active) session_->active = panel;
    ++panel->shows;
    // A real summon renders what the warm-up would have: it counts as one.
    panel->warming = true;
    panel->warm = true;
    // Shown cloaked and revealed on the engine's next presented frame, so what
    // its surface held from before is not seen (see the class comment for
    // the one narrow exception).
    Cloak(*panel, true);
    SetWindowPos(panel->hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    const flutter::EncodableValue payload(SummonPayload(
        *panel, session_id, trigger, app_name, app_icon, active, false));
    panel->last_summon = payload;
    panel->channel->InvokeMethod(
        "summon", std::make_unique<flutter::EncodableValue>(payload));
    ArmFrame(*panel);
    SetTimer(panel->hwnd, kRevealTimer, kRevealDeadlineMs, nullptr);
  }
  // Last, once nothing above can end the session: a change of foreground from
  // here on ends it. Out of context, so the callback runs from this thread's
  // message loop, never inside another process.
  if (owner_pid != 0) {
    g_foreground_watcher = this;
    foreground_hook_ = SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr,
        ForegroundChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
    if (!foreground_hook_) DevLog("overlay click-away not hooked");
    // A move made before the hook existed, between Dart's capture and here,
    // is read once now by the same rule; any later one arrives as an event.
    if (foreground_hook_) OnForeground(foreground_hook_, GetForegroundWindow());
  }
  NoteReady();
  return ShowResult::kShown;
}

void WindowsOverlaySet::SetAppIcon(int64_t session_id,
                                   const std::vector<uint8_t>& png) {
  if (!session_ || session_->id != session_id || png.empty()) {
    DevLog("overlay icon dropped: session " + std::to_string(session_id));
    return;
  }
  const flutter::EncodableValue icon(png);
  for (Panel* panel : Live()) {
    // A panel whose overlayMain was not yet listening replays its last
    // summon when it is: that replay carries the icon too.
    if (panel->last_summon) {
      if (auto* summon =
              std::get_if<flutter::EncodableMap>(&*panel->last_summon)) {
        (*summon)[flutter::EncodableValue("appIcon")] = icon;
      }
    }
    if (!panel->channel) continue;
    panel->channel->InvokeMethod(
        "setAppIcon",
        std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
            {flutter::EncodableValue("sessionId"),
             flutter::EncodableValue(session_id)},
            {flutter::EncodableValue("png"), icon},
        }));
  }
  DevLog("overlay icon: session " + std::to_string(session_id) + ", " +
         std::to_string(png.size()) + " bytes");
}

void CALLBACK WindowsOverlaySet::ForegroundChanged(HWINEVENTHOOK hook, DWORD,
                                                   HWND hwnd, LONG object,
                                                   LONG, DWORD, DWORD) {
  if (object != OBJID_WINDOW || !hwnd || !g_foreground_watcher) return;
  g_foreground_watcher->OnForeground(hook, hwnd);
}

void WindowsOverlaySet::OnForeground(HWINEVENTHOOK hook, HWND hwnd) {
  // An event queued before an earlier session's hook was removed is not this
  // session's; no window at all is a switch still in progress.
  if (!session_ || hook != foreground_hook_ || !hwnd) return;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  // Orthant's own windows: a tray summon's foreground is the hidden window
  // until its capture reactivates the target.
  if (pid == GetCurrentProcessId()) return;
  // The captured window's own process: a tray summon's capture activates
  // that window after the panels show, and a dialog of the app's own may come
  // forward. Neither is the user going elsewhere.
  const bool shell = IsShellSurface(hwnd);
  if (pid == session_->owner_pid && !shell) return;
  DevLog(std::string("overlay foreground moved: ") +
         (shell ? "shell" : "process " + std::to_string(pid)));
  Dismiss("click-away");
}

void WindowsOverlaySet::Unhook() {
  if (foreground_hook_) UnhookWinEvent(foreground_hook_);
  foreground_hook_ = nullptr;
  if (g_foreground_watcher == this) g_foreground_watcher = nullptr;
}

void WindowsOverlaySet::Hide(int64_t session_id) {
  if (session_ && session_->id == session_id) Dismiss("hideOverlay");
}

void WindowsOverlaySet::Dismiss(const char* why) {
  if (!session_) return;
  const int64_t id = session_->id;
  session_.reset();
  Unhook();
  ReleaseKeys();
  for (const auto& owned : panels_) {
    Panel& panel = *owned;
    KillTimer(panel.hwnd, kRevealTimer);
    if (IsWindowVisible(panel.hwnd)) {
      // Off the screen now; hidden on the next turn of the loop, not inside
      // the event that dismissed it, which macOS defers for the same reason.
      Cloak(panel, true);
      PostMessageW(panel.hwnd, kHidePanel, static_cast<WPARAM>(panel.shows),
                   0);
    }
    if (panel.channel) {
      panel.channel->InvokeMethod(
          "hidden", std::make_unique<flutter::EncodableValue>(id));
    }
  }
  DevLog(std::string("overlay dismissed (") + why + ")");
  // Its outcome (a placement, the picker) runs before the next attach.
  HoldAttaches();
}

bool WindowsOverlaySet::GrabKeys() {
  std::ostringstream refused;
  bool ok = true;
  for (const Grab& grab : kGrabs) {
    if (RegisterHotKey(host_, grab.id, grab.modifiers | MOD_NOREPEAT,
                       grab.vk)) {
      grabbed_.push_back(grab.id);
      continue;
    }
    const DWORD error = GetLastError();
    refused << " " << grab.name << " (" << error << ")";
    if (grab.required) {
      ok = false;
      break;
    }
  }
  if (!refused.str().empty()) {
    DevLog("overlay keys refused:" + refused.str() +
           (ok ? "" : "; summon aborted"));
  }
  return ok;
}

void WindowsOverlaySet::ReleaseKeys() {
  for (int id : grabbed_) UnregisterHotKey(host_, id);
  grabbed_.clear();
}

void WindowsOverlaySet::Relay(const char* method,
                              flutter::EncodableValue arguments) {
  if (!session_) return;
  Panel* target =
      session_->press_locked ? session_->press_locked : session_->active;
  if (!target || !target->channel) return;
  target->channel->InvokeMethod(
      method, std::make_unique<flutter::EncodableValue>(std::move(arguments)));
}

void WindowsOverlaySet::HandleOverlayCall(
    Panel& panel, const flutter::MethodCall<flutter::EncodableValue>& call) {
  const std::string& method = call.method_name();
  const int64_t session_id = SessionOf(call.arguments());
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (method == "ready") {
    panel.ready = true;
    // overlayMain's handler is live. Replay a summon it missed (macOS
    // OverlayPanel's ready replay); otherwise render once, out of sight, so
    // the first summon is not a cold engine's (measured: 150-186 ms, against
    // 32-36 warm).
    if (session_ && IsWindowVisible(panel.hwnd) && panel.last_summon) {
      panel.channel->InvokeMethod(
          "summon",
          std::make_unique<flutter::EncodableValue>(*panel.last_summon));
    } else {
      Warm(panel);
    }
  } else if (method == "firstFrame") {
    const auto ms = NumberOf(call.arguments());
    if (ms && session_) {
      DevLog("summon -> first frame: " + Ms(*ms) + " ms (panel " +
             std::to_string(panel.index) + ", active " +
             (session_->active == &panel ? "1" : "0") + ")");
    }
  } else if (method == "becameActive") {
    BecameActive(session_id, &panel);
  } else if (method == "beginDrag") {
    if (session_ && session_->id == session_id && session_->active == &panel) {
      session_->press_locked = &panel;
    }
  } else if (method == "endDrag") {
    if (session_ && session_->id == session_id &&
        session_->press_locked == &panel) {
      session_->press_locked = nullptr;
      // The pointer may be on another display by now, whose becameActive was
      // dropped while the lock held (macOS endDrag).
      POINT cursor{};
      GetCursorPos(&cursor);
      Panel* target =
          PanelFor(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST));
      if (target && target != session_->active) {
        BecameActive(session_id, target);
      }
    }
  } else if (method == "commit") {
    Commit(session_id, args, &panel, false);
  } else if (method == "saveRegion") {
    Commit(session_id, args, &panel, true);
  } else if (method == "hide") {
    if (session_ && session_->id == session_id) Dismiss("hide");
  }
}

void WindowsOverlaySet::BecameActive(int64_t session_id, Panel* panel) {
  if (!session_ || session_->id != session_id) return;
  // Not while a drag holds the lock, or dragging from one display onto another
  // would dim the first under the user's own gesture.
  if (session_->press_locked) return;
  session_->active = panel;
  for (Panel* other : Live()) {
    if (other->channel) {
      other->channel->InvokeMethod(
          "setActive", std::make_unique<flutter::EncodableValue>(other == panel));
    }
  }
}

void WindowsOverlaySet::Commit(int64_t session_id,
                               const flutter::EncodableMap* args, Panel* panel,
                               bool save) {
  if (!session_ || session_->id != session_id || !args) return;
  // Only the panel that owns the gesture may commit (macOS commit).
  if (panel !=
      (session_->press_locked ? session_->press_locked : session_->active)) {
    return;
  }
  const auto x = NumberOf(Field(*args, "x"));
  const auto y = NumberOf(Field(*args, "y"));
  const auto w = NumberOf(Field(*args, "w"));
  const auto h = NumberOf(Field(*args, "h"));
  if (!x || !y || !w || !h) return;
  flutter::EncodableMap payload{
      {flutter::EncodableValue("sessionId"), flutter::EncodableValue(session_id)},
      {flutter::EncodableValue("x"), flutter::EncodableValue(*x)},
      {flutter::EncodableValue("y"), flutter::EncodableValue(*y)},
      {flutter::EncodableValue("w"), flutter::EncodableValue(*w)},
      {flutter::EncodableValue("h"), flutter::EncodableValue(*h)},
  };
  if (save) {
    flutter::EncodableMap block;
    for (const char* key : {"cols", "rows", "c0", "c1", "r0", "r1"}) {
      const auto value = IntOf(Field(*args, key));
      if (!value) return;
      block[flutter::EncodableValue(key)] = flutter::EncodableValue(*value);
    }
    payload[flutter::EncodableValue("block")] = flutter::EncodableValue(block);
  }
  // Dismissed first: the session does not own the window here, so nothing has
  // to land before it ends (macOS places, then dismisses). Then the main
  // engine is told; it places through its command queue.
  Dismiss(save ? "saveRegion" : "commit");
  const auto& forward = save ? forward_.save_region : forward_.commit;
  if (forward) forward(std::move(payload));
}

void WindowsOverlaySet::Cloak(Panel& panel, bool on) {
  const BOOL value = on ? TRUE : FALSE;
  DwmSetWindowAttribute(panel.hwnd, DWMWA_CLOAK, &value, sizeof(value));
  panel.cloaked = on;
}

void WindowsOverlaySet::Reveal(Panel& panel, const char* why) {
  KillTimer(panel.hwnd, kRevealTimer);
  if (!panel.cloaked) return;
  Cloak(panel, false);
  if (session_) {
    DevLog("summon -> presented: " + Ms(EpochMs() - session_->trigger_ms) +
           " ms (panel " + std::to_string(panel.index) + ", active " +
           (session_->active == &panel ? "1" : "0") + ", " + why + ")");
  }
}

void WindowsOverlaySet::Warm(Panel& panel) {
  if (session_ || showing_ || panel.warming || !panel.monitor ||
      !panel.channel) {
    return;
  }
  panel.warming = true;
  ++panel.shows;
  Cloak(panel, true);
  SetWindowPos(panel.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  // Rendered as the active panel, so the first real summon takes the warmed
  // path; the warm flag keeps it from speaking or reporting a first frame.
  panel.channel->InvokeMethod(
      "summon", std::make_unique<flutter::EncodableValue>(SummonPayload(
                    panel, 0, EpochMs(), "", {}, true, true)));
  ArmFrame(panel);
  SetTimer(panel.hwnd, kWarmTimer, kWarmDeadlineMs, nullptr);
}

void WindowsOverlaySet::ArmFrame(Panel& panel) {
  if (panel.frame_armed || !panel.controller) return;
  panel.frame_armed = true;
  const HWND hwnd = panel.hwnd;
  const uint64_t shows = panel.shows;
  // Delivered by message, not acted on here: the engine's wrapper empties its
  // slot after this returns, so a callback registered from inside it is lost.
  panel.controller->engine()->SetNextFrameCallback([hwnd, shows]() {
    PostMessageW(hwnd, kFramePresented, static_cast<WPARAM>(shows), 0);
  });
}

bool WindowsOverlaySet::AwaitsFrame(const Panel& panel) const {
  return session_ ? panel.cloaked && IsWindowVisible(panel.hwnd)
                  : panel.warming && !panel.warm;
}

void WindowsOverlaySet::OnFramePresented(Panel& panel, uint64_t shows) {
  panel.frame_armed = false;
  if (!AwaitsFrame(panel)) return;
  if (shows != panel.shows) {
    // Registered for an earlier show (a warm-up, or a session since ended),
    // so this frame may be that show's. The current show waits for one of its
    // own; its deadline still bounds the wait.
    ArmFrame(panel);
  } else if (session_) {
    Reveal(panel, "frame");
  } else {
    EndWarm(panel, shows, "frame");
  }
}

void WindowsOverlaySet::EndWarm(Panel& panel, uint64_t shows,
                                const char* why) {
  KillTimer(panel.hwnd, kWarmTimer);
  // A real summon has shown this panel since: it owns the panel now.
  if (panel.shows != shows || session_ || panel.warm) return;
  panel.warm = true;
  ShowWindow(panel.hwnd, SW_HIDE);
  if (panel.channel) {
    panel.channel->InvokeMethod(
        "hidden", std::make_unique<flutter::EncodableValue>(int64_t{0}));
  }
  DevLog("overlay panel " + std::to_string(panel.index) + " warmed (" + why +
         ")");
  NoteReady();
}

void WindowsOverlaySet::NoteReady() {
  if (announced_ready_) return;
  // Every monitor's, not every live panel's: a monitor that came and went at
  // launch would otherwise be announced ready with one panel short.
  for (HMONITOR monitor : Monitors()) {
    const Panel* panel = PanelFor(monitor);
    if (!panel || !panel->warm) return;
  }
  const std::vector<Panel*> live = Live();
  announced_ready_ = true;
  DevLog("overlay ready: " + std::to_string(live.size()) + " panels, " +
         Ms(MsSince(started_)) + " ms after launch");
}
