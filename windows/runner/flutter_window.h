#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "window_channel.h"
#include "windows_overlay_set.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
#ifdef ORTHANT_DEV_BUILD
  // The temporary chords that drive W3's acceptance until W2's real hotkeys.
  bool HandleDevChord(int id);
#endif

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The overlay: one panel per monitor, each with its own engine, and the
  // source of every display's DPI. Created before the channel that reads it
  // and destroyed after.
  std::unique_ptr<WindowsOverlaySet> overlay_set_;

  // The Windows half of app.orthant/window. Owned here because it needs this
  // window's handle and the engine's messenger, both of which exist only
  // between OnCreate and OnDestroy.
  std::unique_ptr<WindowChannel> window_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
