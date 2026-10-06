#ifndef RUNNER_WINDOW_CHANNEL_H_
#define RUNNER_WINDOW_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>

#include "windows_overlay_set.h"

// The Windows half of `app.orthant/window` (lib/core/channel.dart). The
// mirror of macos/Runner/MainFlutterWindow.swift's handler. Only what needs
// a window handle, the message loop or a Flutter engine lives on this side
// (spec 2026-09-18 Windows design, §5.1); everything stateless is Dart FFI.
//
// W0 handles the config window, and answers the hotkey pair without
// registering anything: every id refused, unregister a no-op. That is not
// laziness. The coordinator registers hotkeys the moment permission reads as
// granted, which on Windows is always, and Dart's apply() does not catch a
// channel failure, so NotImplemented there is a MissingPluginException thrown
// before runApp. W2 replaces those two branches with RegisterHotKey. W1 adds
// the displays, answered from WindowsOverlaySet's per-monitor windows; W3
// adds setOverlayGrid, showOverlay and hideOverlay, and the overlay's commit
// and save-region notifications to Dart. Anything else answers
// NotImplemented, which Dart surfaces as MissingPluginException;
// test/windows_channel_contract_test.dart fails if Dart calls a method this
// file does not answer.
class WindowChannel {
 public:
  WindowChannel(flutter::BinaryMessenger* messenger, HWND config_window,
                WindowsOverlaySet* overlays);
  // Destroying a MethodChannel does not unregister its handler with the
  // messenger, and the registered handler captures `this`.
  ~WindowChannel();

  WindowChannel(const WindowChannel&) = delete;
  WindowChannel& operator=(const WindowChannel&) = delete;

  // Tell Dart the config window was closed, i.e. hidden. The same message
  // the macOS side sends from windowShouldClose; HotkeyService routes it to
  // the coordinator, which resumes hotkeys a recording may have suspended.
  void NotifyConfigWindowClosed();

  // The overlay's commit and Ctrl+S, after the panels are dismissed. Dart owns
  // the captured window: it applies them only if the session id still names
  // its current, unapplied capture.
  void NotifyOverlayCommit(flutter::EncodableMap payload);
  void NotifyOverlaySaveRegion(flutter::EncodableMap payload);

#ifdef ORTHANT_DEV_BUILD
  // W3's temporary summon, until W2's hotkeys. `pressed_at_ms` is its key
  // press (WindowsOverlaySet::PressedAtMs), which Dart sends back with the
  // summon's showOverlay.
  void NotifyDebugSummon(double pressed_at_ms);
  // Sends the last commit again, so the acceptance can watch Dart refuse a
  // duplicate, and a commit from a session a newer capture replaced.
  void DebugReplayLastCommit();
#endif

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND config_window_;
  // Owned by FlutterWindow, which destroys this channel first.
  WindowsOverlaySet* overlays_;
#ifdef ORTHANT_DEV_BUILD
  std::optional<flutter::EncodableMap> last_commit_;
#endif
};

#endif  // RUNNER_WINDOW_CHANNEL_H_
