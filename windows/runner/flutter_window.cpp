#include "flutter_window.h"

#include <iostream>
#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

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

  overlay_set_ = std::make_unique<WindowsOverlaySet>(
      GetHandle(), WindowsOverlaySet::Forward{});
  window_channel_ = std::make_unique<WindowChannel>(
      flutter_controller_->engine()->messenger(), GetHandle(),
      overlay_set_.get());

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
