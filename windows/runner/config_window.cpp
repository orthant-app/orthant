#include "config_window.h"

#include <dwmapi.h>

#include <algorithm>
#include <cstdio>
#include <iostream>
#include <utility>

namespace {

// On the settings window, beside the overlay's host timers (0x4F57 up).
constexpr UINT_PTR kRevealTimer = 0x4F43;
constexpr UINT_PTR kSaveTimer = 0x4F44;

// The frame, under the app's own key: CompanyName and ProductName, as the
// preferences' folder is. "left,top,right,bottom,height": the window's frame
// in physical pixels, which says which monitor it was on, and its client
// height in device-independent pixels, so a monitor whose scale changed since
// gives the same height in its own pixels. A value in any other form (an
// earlier build's) reads as none.
constexpr wchar_t kKey[] = L"Software\\Orthant\\Orthant";
constexpr wchar_t kValue[] = L"SettingsWindow";

bool ReadSaved(RECT* frame, int* height_dip) {
  wchar_t text[96] = {};
  DWORD size = sizeof(text);
  if (RegGetValueW(HKEY_CURRENT_USER, kKey, kValue, RRF_RT_REG_SZ, nullptr,
                   text, &size) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t rest = 0;
  return swscanf_s(text, L"%ld,%ld,%ld,%ld,%d%lc", &frame->left, &frame->top,
                   &frame->right, &frame->bottom, height_dip, &rest, 1) == 5 &&
         frame->right > frame->left && frame->bottom > frame->top &&
         *height_dip > 0 && *height_dip < 100000;
}

void WriteSaved(const RECT& frame, int height_dip) {
  wchar_t text[96] = {};
  swprintf_s(text, L"%ld,%ld,%ld,%ld,%d", frame.left, frame.top, frame.right,
             frame.bottom, height_dip);
  RegSetKeyValueW(HKEY_CURRENT_USER, kKey, kValue, REG_SZ, text,
                  static_cast<DWORD>((wcslen(text) + 1) * sizeof(wchar_t)));
}

void Cloak(HWND hwnd, bool on) {
  const BOOL value = on ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, &value, sizeof(value));
}

}  // namespace

UINT ConfigWindow::FramePresentedMessage() {
  static const UINT message =
      RegisterWindowMessageW(L"OrthantConfigFramePresented");
  return message;
}

ConfigWindow::ConfigWindow(HWND hwnd, ArmFrame arm_frame, Hold hold)
    : hwnd_(hwnd), arm_frame_(std::move(arm_frame)), hold_(std::move(hold)) {
  // No maximize: the width is pinned, so a maximized window would be a full
  // height strip at the work area's left edge. A vertical maximize (a double
  // click on the top edge) keeps the width and is left to Windows.
  SetWindowLongPtr(hwnd_, GWL_STYLE,
                   GetWindowLongPtr(hwnd_, GWL_STYLE) & ~WS_MAXIMIZEBOX);
  Place();
}

SIZE ConfigWindow::OuterSize(int width_dip, int height_dip, UINT dpi) const {
  RECT r{0, 0, MulDiv(width_dip, dpi, USER_DEFAULT_SCREEN_DPI),
         MulDiv(height_dip, dpi, USER_DEFAULT_SCREEN_DPI)};
  AdjustWindowRectExForDpi(
      &r, static_cast<DWORD>(GetWindowLongPtr(hwnd_, GWL_STYLE)), FALSE,
      static_cast<DWORD>(GetWindowLongPtr(hwnd_, GWL_EXSTYLE)), dpi);
  return SIZE{r.right - r.left, r.bottom - r.top};
}

void ConfigWindow::Place() {
  RECT frame{};
  int height_dip = 0;
  bool saved = ReadSaved(&frame, &height_dip);
  const LONG left = frame.left, top = frame.top;
  HMONITOR monitor = nullptr;
  if (saved) {
    // The monitor holding most of the frame, as Windows itself gives a
    // window the scale of the monitor holding most of it. Not its corner,
    // which a window flush with a monitor's left edge has in its invisible
    // resize border, and not a strip of the width at 100 %: at 200 % that
    // is half the window, and can lie mostly on the other monitor.
    monitor = MonitorFromRect(&frame, MONITOR_DEFAULTTONULL);
  }
  if (!monitor) {
    // Never saved, or saved on a monitor that is gone.
    saved = false;
    POINT cursor{};
    GetCursorPos(&cursor);
    monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
  }
  MONITORINFO info{sizeof(info)};
  GetMonitorInfo(monitor, &info);
  const RECT work = info.rcWork;
  // Onto that monitor first, so the window takes its DPI. A move across a
  // DPI boundary is resized by Windows' suggestion (WM_DPICHANGED), which
  // scales whatever size it was given (measured: a 560 x 500 frame became
  // 373 x 333 moving from 150 % to 100 %); the size below replaces it.
  SetWindowPos(hwnd_, nullptr, work.left, work.top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  const UINT dpi = GetDpiForWindow(hwnd_);
  SIZE size = OuterSize(
      kWidthDip, saved ? (std::max)(height_dip, kMinHeightDip)
                       : kOpeningHeightDip,
      dpi);
  size.cy = (std::min)(size.cy, static_cast<LONG>(work.bottom - work.top));
  LONG x = saved ? left : work.left + (work.right - work.left - size.cx) / 2;
  LONG y = saved ? top : work.top + (work.bottom - work.top - size.cy) / 2;
  x = (std::max)(work.left, (std::min)(x, work.right - size.cx));
  y = (std::max)(work.top, (std::min)(y, work.bottom - size.cy));
  SetWindowPos(hwnd_, nullptr, x, y, size.cx, size.cy,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
#ifdef ORTHANT_DEV_BUILD
  // The acceptance parses this line: change it only together with it.
  std::cout << "[orthant] config window placed: "
            << (saved ? "saved" : "centred") << " " << x << "," << y << " "
            << size.cx << "x" << size.cy << " dpi " << dpi << std::endl;
#endif
}

void ConfigWindow::Save() {
  // Only a frame the user can see: a minimized window's rectangle is its
  // icon's, and a hidden one has nothing new to say.
  if (!IsWindowVisible(hwnd_) || IsIconic(hwnd_) || IsZoomed(hwnd_)) return;
  RECT frame{};
  RECT client{};
  GetWindowRect(hwnd_, &frame);
  GetClientRect(hwnd_, &client);
  const UINT dpi = GetDpiForWindow(hwnd_);
  if (dpi == 0) return;
  const int height_dip =
      MulDiv(client.bottom - client.top, USER_DEFAULT_SCREEN_DPI, dpi);
  WriteSaved(frame, height_dip);
}

void ConfigWindow::Show() {
  if (!IsWindowVisible(hwnd_)) {
    // Shown cloaked, so what its surface last held (a white client before
    // any frame, measured; or the previous screen) is never seen.
    Cloak(hwnd_, true);
    awaiting_frame_ = true;
    reported_ = false;
    ++shows_;
    shown_at_ = GetTickCount64();
    SetTimer(hwnd_, kRevealTimer, kShowDeadlineMs, nullptr);
    if (hold_) hold_();
    // Its monitor can go while it is hidden; Windows moves a visible window
    // off a monitor that goes, not necessarily a hidden one. Placed once the
    // show is waiting: a move across a DPI boundary has Flutter draw the
    // pane there and then, and its report would otherwise find no show to
    // count for (measured: revealed by the deadline).
    if (!MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONULL)) Place();
  }
  // A minimized window shown with SW_SHOW stays minimized; restore it.
  ShowWindow(hwnd_, IsIconic(hwnd_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd_);
}

void ConfigWindow::Hide() {
  Save();
  KillTimer(hwnd_, kSaveTimer);
  KillTimer(hwnd_, kRevealTimer);
  ShowWindow(hwnd_, SW_HIDE);
  // A hide before the reveal resets it, so the next show starts clean;
  // uncloaked only once hidden, so nothing unpainted can be composed between.
  if (awaiting_frame_) {
    awaiting_frame_ = false;
    Cloak(hwnd_, false);
  }
}

void ConfigWindow::FirstFrame() {
  if (!awaiting_frame_ || reported_) return;
  reported_ = true;
  // From here the frame has a short wait of its own: the screen has drawn.
  SetTimer(hwnd_, kRevealTimer, kPresentDeadlineMs, nullptr);
  if (hold_) hold_();
  Arm();
}

void ConfigWindow::Arm() {
  if (frame_armed_ || !arm_frame_) return;
  frame_armed_ = arm_frame_(shows_);
}

void ConfigWindow::Reveal(const char* why) {
  KillTimer(hwnd_, kRevealTimer);
  if (!awaiting_frame_) return;
  awaiting_frame_ = false;
  Cloak(hwnd_, false);
#ifdef ORTHANT_DEV_BUILD
  // The acceptance parses this line: change it only together with it.
  std::cout << "[orthant] config window revealed after "
            << (GetTickCount64() - shown_at_) << " ms (" << why << ")"
            << std::endl;
#else
  (void)why;
#endif
}

bool ConfigWindow::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam,
                                 LRESULT* result) {
  if (message == FramePresentedMessage() && message != 0) {
    frame_armed_ = false;
    // Only once the current show has reported: before that, a frame says
    // nothing about its screen, and the report arms one of its own.
    if (awaiting_frame_ && reported_) {
      // Armed for an earlier show, so this frame may be that show's: the
      // current one waits for one of its own, its deadline still bounding it.
      if (static_cast<uint64_t>(wparam) == shows_) {
        Reveal("frame");
      } else {
        Arm();
      }
    }
    *result = 0;
    return true;
  }
  switch (message) {
    case WM_GETMINMAXINFO: {
      // At the window's current DPI, so a move to a monitor of another scale
      // keeps the same width and floor in device-independent pixels.
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(hwnd_);
      if (dpi == 0) return false;
      const SIZE floor = OuterSize(kWidthDip, kMinHeightDip, dpi);
      // Never a floor taller than the work area, which placement clamps to
      // as well: on a short screen the floor would push the window's bottom,
      // and the pane's footer, off it at the first resize.
      MONITORINFO info{sizeof(info)};
      GetMonitorInfo(MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST),
                     &info);
      limits->ptMinTrackSize = POINT{
          floor.cx, (std::min)(floor.cy, static_cast<LONG>(
                                             info.rcWork.bottom -
                                             info.rcWork.top))};
      limits->ptMaxTrackSize.x = floor.cx;
      *result = 0;
      return true;
    }
    case WM_NCHITTEST: {
      // The side edges and corners are plain border: the width does not
      // change, so no horizontal resize cursor offers to change it.
      LRESULT hit = DefWindowProc(hwnd_, message, wparam, lparam);
      switch (hit) {
        case HTLEFT:
        case HTRIGHT:
          hit = HTBORDER;
          break;
        case HTTOPLEFT:
        case HTTOPRIGHT:
          hit = HTTOP;
          break;
        case HTBOTTOMLEFT:
        case HTBOTTOMRIGHT:
          hit = HTBOTTOM;
          break;
      }
      *result = hit;
      return true;
    }
    case WM_EXITSIZEMOVE:
      // The end of a move or resize by the user: kept now, since Quit exits
      // without hiding the window first.
      KillTimer(hwnd_, kSaveTimer);
      Save();
      return false;
    case WM_WINDOWPOSCHANGED:
      // Any other move or resize while it is on screen (a snap, a keyboard
      // move, a monitor change): kept once it settles. Passed on, since the
      // default handling turns it into WM_MOVE and WM_SIZE.
      if (IsWindowVisible(hwnd_) && !IsIconic(hwnd_)) {
        SetTimer(hwnd_, kSaveTimer, kSaveDelayMs, nullptr);
      }
      return false;
    case WM_TIMER:
      if (wparam == kSaveTimer) {
        KillTimer(hwnd_, kSaveTimer);
        Save();
        *result = 0;
        return true;
      }
      if (wparam != kRevealTimer) return false;
      Reveal(reported_ ? "deadline after the report" : "deadline");
      *result = 0;
      return true;
  }
  return false;
}
