#include "flutter_window.h"

#include <iostream>
#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

namespace {

#ifdef ORTHANT_DEV_BUILD
// W3's temporary chords, Debug and Profile builds only, until W2 registers the
// real summon. None uses Alt: an Alt chord leaves a WinUI target such as
// Notepad in access-key mode, eating the next keys typed into it (measured).
constexpr int kDevSummon = 0xBFF0;
constexpr int kDevReplayCommit = 0xBFF1;
constexpr int kDevCyclePanels = 0xBFF2;

struct DevChord {
  int id;
  UINT modifiers;
  UINT vk;
  const char* name;
};

constexpr DevChord kDevChords[] = {
    {kDevSummon, MOD_CONTROL | MOD_SHIFT, 'O', "Ctrl+Shift+O summons"},
    {kDevReplayCommit, MOD_CONTROL | MOD_SHIFT, VK_F11,
     "Ctrl+Shift+F11 replays the last commit"},
    {kDevCyclePanels, MOD_CONTROL | MOD_SHIFT, VK_F10,
     "Ctrl+Shift+F10 parks and reuses every panel"},
};
#endif

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
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

#ifdef ORTHANT_DEV_BUILD
  for (const DevChord& chord : kDevChords) {
    const BOOL registered = RegisterHotKey(
        GetHandle(), chord.id, chord.modifiers | MOD_NOREPEAT, chord.vk);
    std::cout << "[orthant] dev chord " << chord.name << ": "
              << (registered ? "registered" : "refused") << std::endl;
  }
#endif

  // The template shows the window on the engine's first frame. Orthant is a
  // tray app: the window stays hidden until Dart asks for it over the channel
  // (spec §5.5), so there is no first-frame reveal here. W5 adds the
  // reveal-on-first-frame with a deadline for the first *show*.
  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  overlay_set_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The overlay's posted work: reconciles and engine attaches.
  if (overlay_set_ && overlay_set_->HandleHostMessage(message)) {
    return 0;
  }

  switch (message) {
    case WM_HOTKEY: {
      const int id = static_cast<int>(wparam);
#ifdef ORTHANT_DEV_BUILD
      // Ahead of the overlay's live-session swallow on purpose: the replay and
      // cycle chords must work while a session is live, since replaying an
      // older session's commit during a newer one is exactly the stale commit
      // Dart must refuse. Only the dev summon is swallowed, in HandleDevChord.
      if (HandleDevChord(id)) return 0;
#endif
      // The overlay's grabs, and anything at all while a session is live.
      if (overlay_set_ && overlay_set_->HandleHotkey(id)) return 0;
      break;
    }
    case WM_CLOSE:
      // Closing the settings window hides it. A tray app outlives its
      // window; Quit is the tray item (spec §5.5). Handled ahead of the
      // Flutter delegation so no plugin can turn this into a DestroyWindow.
      ShowWindow(hwnd, SW_HIDE);
      if (window_channel_) {
        window_channel_->NotifyConfigWindowClosed();
      }
      return 0;
    case WM_EXITMENULOOP:
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

#ifdef ORTHANT_DEV_BUILD
bool FlutterWindow::HandleDevChord(int id) {
  if (!overlay_set_ || !window_channel_) return false;
  switch (id) {
    case kDevSummon:
      // Swallowed while a session is live, as every other hotkey is.
      if (!overlay_set_->live()) {
        window_channel_->NotifyDebugSummon(
            WindowsOverlaySet::PressedAtMs(GetMessageTime()));
      }
      return true;
    case kDevReplayCommit:
      window_channel_->DebugReplayLastCommit();
      return true;
    case kDevCyclePanels:
      overlay_set_->DebugCyclePanels();
      return true;
  }
  return false;
}
#endif
