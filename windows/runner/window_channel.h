#ifndef RUNNER_WINDOW_CHANNEL_H_
#define RUNNER_WINDOW_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <vector>

#include "windows_overlay_set.h"

// The Windows half of `app.orthant/window` (lib/core/channel.dart). The
// mirror of macos/Runner/MainFlutterWindow.swift's handler. Only what needs
// a window handle, the message loop or a Flutter engine lives on this side
// (spec 2026-09-18 Windows design, §5.1); everything stateless is Dart FFI.
//
// It handles the config window; the global hotkeys (W2): replaceHotkeys
// registers each chord with RegisterHotKey on the config window, which is
// this thread's, since a registration belongs to the calling thread's queue,
// and a press comes back as onHotkey; the displays, answered from
// WindowsOverlaySet's per-monitor windows (W1); and setOverlayGrid,
// showOverlay and hideOverlay, with the overlay's commit and save-region
// notifications to Dart (W3). Anything else answers NotImplemented, which
// Dart surfaces as MissingPluginException;
// test/windows_channel_contract_test.dart fails if Dart calls a method this
// file does not answer, or this file sends one Dart does not handle.
class WindowChannel {
 public:
  WindowChannel(flutter::BinaryMessenger* messenger, HWND config_window,
                WindowsOverlaySet* overlays);
  // Destroying a MethodChannel does not unregister its handler with the
  // messenger, and the registered handler captures `this`. Also unregisters
  // every hotkey this channel registered.
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

  // A registered shortcut was pressed: its id (below 900) and its press
  // (WindowsOverlaySet::PressTick). Dart dispatches the id; a summon carries
  // the press back in showOverlay.
  void NotifyHotkey(int id, double pressed_at_ms);

  // This thread's input language may have changed (`why`: the message that
  // said so), so a punctuation key's printed symbol may have changed with it.
  void NotifyKeyboardLayoutChanged(const char* why);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Unregisters the previous set, then registers every entry of a
  // replaceHotkeys payload. Answers the refused ids, or nullopt for a payload
  // of an unexpected shape, with nothing registered.
  std::optional<flutter::EncodableList> ReplaceHotkeys(
      const flutter::EncodableValue* arguments);
  void UnregisterHotkeys();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND config_window_;
  // Owned by FlutterWindow, which destroys this channel first.
  WindowsOverlaySet* overlays_;
  // The ids registered on config_window_, so a replacement or the destructor
  // can unregister exactly them; the overlay's grabs (900 up) are not here.
  std::vector<int> registered_;
};

#endif  // RUNNER_WINDOW_CHANNEL_H_
