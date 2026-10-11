#include "flutter_window.h"

#include <commctrl.h>

#include <iostream>
#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The view's subclass, unique to this file.
constexpr UINT_PTR kViewSubclass = 1;

// The focus never activates a window of Orthant's that nobody can see: the
// settings window while it is hidden, or an overlay panel, which never takes
// it at all. Flutter asks for its view's focus as an app starts (the first
// route takes the focus, and the view follows), and the embedder's SetFocus
// activates the window holding the view. At launch, while the process may
// still take the foreground, the hidden settings window and then each panel
// took it from the window the user was in, and the hidden one could keep it
// (measured). The hidden window may still be activated, which the tray does
// so that its menu closes on a click elsewhere, and once active it may focus
// its view: that focus is what the settings window has when the tray then
// shows it, already active, with no second activation to set it (measured:
// refused, the shortcut recorder heard nothing). A thread hook sees only this
// thread's windows, and every window Orthant has is on this thread.
HHOOK g_focus_guard = nullptr;

LRESULT CALLBACK FocusGuard(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HCBT_SETFOCUS || code == HCBT_ACTIVATE) {
    HWND root = GetAncestor(reinterpret_cast<HWND>(wparam), GA_ROOT);
    if (root) {
      const bool never =
          (GetWindowLongPtrW(root, GWL_EXSTYLE) & WS_EX_NOACTIVATE) != 0;
      const bool activates_unseen = code == HCBT_SETFOCUS &&
                                    !IsWindowVisible(root) &&
                                    GetActiveWindow() != root;
      if (never || activates_unseen) return 1;
    }
  }
  return CallNextHookEx(g_focus_guard, code, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  // Before any engine, so that none of their first requests gets through.
  g_focus_guard = SetWindowsHookExW(WH_CBT, FocusGuard, nullptr,
                                    GetCurrentThreadId());
  if (!g_focus_guard) {
#ifdef ORTHANT_DEV_BUILD
    const DWORD error = GetLastError();
    std::cout << "[orthant] focus guard not installed, error " << error
              << std::endl;
#endif
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // A commit is forwarded to Dart, which owns the captured window; the
  // channel exists by the time a panel can commit.
  overlay_set_ = std::make_unique<WindowsOverlaySet>(
      GetHandle(),
      WindowsOverlaySet::Forward{
          [this](flutter::EncodableMap payload) {
            if (window_channel_) {
              window_channel_->NotifyOverlayCommit(std::move(payload));
            }
          },
          [this](flutter::EncodableMap payload) {
            if (window_channel_) {
              window_channel_->NotifyOverlaySaveRegion(std::move(payload));
            }
          },
      });
  window_channel_ = std::make_unique<WindowChannel>(
      flutter_controller_->engine()->messenger(), GetHandle(),
      overlay_set_.get());
  if (!SetWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                         ViewProc, kViewSubclass,
                         reinterpret_cast<DWORD_PTR>(this))) {
#ifdef ORTHANT_DEV_BUILD
    // The labels then follow a layout switch only when this window is next
    // activated.
    std::cout << "[orthant] view not subclassed: layout notices only on "
                 "activation"
              << std::endl;
#endif
  }

  // The template shows the window on the engine's first frame. Orthant is a
  // tray app: the window stays hidden until Dart asks for it over the channel
  // (spec §5.5), so there is no first-frame reveal here. W5 adds the
  // reveal-on-first-frame with a deadline for the first *show*.
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_ && flutter_controller_->view()) {
    RemoveWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                         ViewProc, kViewSubclass);
  }
  window_channel_ = nullptr;
  overlay_set_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  if (g_focus_guard) {
    UnhookWindowsHookEx(g_focus_guard);
    g_focus_guard = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The overlay's posted work and its timer: reconciles, engine attaches, and
  // the deadline for starting the engines.
  if (overlay_set_ && overlay_set_->HandleHostMessage(message, wparam)) {
    return 0;
  }

  switch (message) {
    case WM_HOTKEY: {
      const int id = static_cast<int>(wparam);
      // The overlay's grabs, and anything at all while a session is live.
      if (overlay_set_ && overlay_set_->HandleHotkey(id)) return 0;
      // A shortcut, to Dart with its press: the summon's stale check and its
      // first-frame timing read the press, not this dispatch. Ids from
      // kFirstGrabId up are the overlay's and were handled above.
      if (id >= 0 && id < WindowsOverlaySet::kFirstGrabId && window_channel_) {
        // A fixed hold (one second) keeps an engine from attaching between
        // this press and Dart's own notice that its command is running
        // (setCommandsRunning), which then holds the attaches until the
        // commands are done, up to a ceiling. The hold runs out whether or
        // not Dart says so.
        if (overlay_set_) overlay_set_->HoldAttaches();
        window_channel_->NotifyHotkey(
            id, WindowsOverlaySet::PressTick(GetMessageTime()));
        return 0;
      }
      break;
    }
    case WM_ACTIVATE:
      // This thread takes up the user's current layout when it is activated
      // (measured: a switch made in another app reaches it only then), so a
      // label read now can differ from the last. Then on to Flutter and the
      // template's handler, which focuses the view.
      if (LOWORD(wparam) != WA_INACTIVE && window_channel_) {
        window_channel_->NotifyKeyboardLayoutChanged("WM_ACTIVATE");
      }
      break;
    case WM_CLOSE:
      // Closing the settings window hides it. A tray app outlives its
      // window; Quit is the tray item (spec §5.5). Handled ahead of the
      // Flutter delegation so no plugin can turn this into a DestroyWindow.
      ShowWindow(hwnd, SW_HIDE);
      if (window_channel_) {
        window_channel_->NotifyConfigWindowClosed();
      }
      return 0;
    case WM_ENTERMENULOOP:
      // The tray's menu, tracked on this thread: no engine attaches under it.
      if (overlay_set_) overlay_set_->MenuLoop(true);
      break;
    case WM_EXITMENULOOP:
      if (overlay_set_) overlay_set_->MenuLoop(false);
      // tray_manager tracks its menu with this window as owner but never
      // posts the WM_NULL Microsoft prescribes after TrackPopupMenu for a
      // notification icon's menu. Without it the second opening of the menu
      // appears and immediately vanishes. Posted here, once the loop exits,
      // and then falls through: Flutter and DefWindowProc still see it.
      PostMessage(hwnd, WM_NULL, 0, 0);
      break;
    case WM_DISPLAYCHANGE:
      // A monitor came, went or changed mode or scale. The overlay ends any
      // session and reconciles its panels on a later turn of the loop; then
      // fall through so Flutter and DefWindowProc see the message too.
      if (overlay_set_) {
        overlay_set_->OnDisplayChange("WM_DISPLAYCHANGE");
      }
      break;
    case WM_SETTINGCHANGE:
      // A work area moved: a taskbar resized, moved or rescaled. Measured to
      // follow a scale change by about 200 ms, without a WM_DISPLAYCHANGE.
      if (wparam == SPI_SETWORKAREA && overlay_set_) {
        overlay_set_->OnDisplayChange("SPI_SETWORKAREA");
      }
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK FlutterWindow::ViewProc(HWND hwnd, UINT message,
                                         WPARAM wparam, LPARAM lparam,
                                         UINT_PTR id, DWORD_PTR data) {
  if (message == WM_NCDESTROY) {
    // The view is going without OnDestroy having run (the ~Win32Window path):
    // the subclass must not outlive it.
    RemoveWindowSubclass(hwnd, ViewProc, id);
    return DefSubclassProc(hwnd, message, wparam, lparam);
  }
  if (message == WM_INPUTLANGCHANGE) {
    // This thread's input language changed, so a punctuation key may print
    // differently: Dart re-reads the labels.
    auto* self = reinterpret_cast<FlutterWindow*>(data);
    if (self->window_channel_) {
      self->window_channel_->NotifyKeyboardLayoutChanged("WM_INPUTLANGCHANGE");
    }
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}
