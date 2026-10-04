#include "window_channel.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <string>

namespace {

constexpr char kChannelName[] = "app.orthant/window";

// Every `id` in a replaceHotkeys payload, as the list of refused ids Dart
// expects back. W0 registers nothing, so every id is refused; the pane
// renders those as "Not set" and the tray as unavailable, which is the
// truth.
//
// A payload of an unexpected shape yields nullopt and the caller answers
// null. The polarity matters: Dart's HotkeyService.apply treats any reply
// that is not a list as "everything refused", but an EMPTY list as
// "nothing refused", so returning an empty list here would report every
// shortcut live when nothing is registered. The same polarity applies per
// entry: Dart's whereType<int>() silently drops a non-int id, so an id of
// the wrong type must not be let through either, or that shortcut is
// reported as live when nothing is registered for it.
std::optional<flutter::EncodableList> AllIdsRefused(
    const flutter::EncodableValue* arguments) {
  const auto* args = std::get_if<flutter::EncodableMap>(arguments);
  if (!args) return std::nullopt;
  const auto bindings = args->find(flutter::EncodableValue("bindings"));
  if (bindings == args->end()) return std::nullopt;
  const auto* list = std::get_if<flutter::EncodableList>(&bindings->second);
  if (!list) return std::nullopt;
  flutter::EncodableList refused;
  for (const auto& entry : *list) {
    const auto* binding = std::get_if<flutter::EncodableMap>(&entry);
    if (!binding) return std::nullopt;
    const auto id = binding->find(flutter::EncodableValue("id"));
    if (id == binding->end()) return std::nullopt;
    if (!std::get_if<int32_t>(&id->second) &&
        !std::get_if<int64_t>(&id->second)) {
      return std::nullopt;
    }
    refused.push_back(id->second);
  }
  return refused;
}

// A display as Dart's displayFromReply reads it: the work area in physical
// pixels, which is Windows' global placement space (spec §5.2), and the
// scale that turns a device-independent gap into those pixels.
flutter::EncodableValue DisplayToValue(
    const WindowsOverlaySet::Display& display) {
  const RECT& r = display.work;
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(r.left))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(r.top))},
      {flutter::EncodableValue("w"),
       flutter::EncodableValue(static_cast<double>(r.right - r.left))},
      {flutter::EncodableValue("h"),
       flutter::EncodableValue(static_cast<double>(r.bottom - r.top))},
      {flutter::EncodableValue("scale"),
       flutter::EncodableValue(static_cast<double>(display.dpi) /
                               USER_DEFAULT_SCREEN_DPI)},
  });
}

}  // namespace

WindowChannel::WindowChannel(flutter::BinaryMessenger* messenger,
                             HWND config_window,
                             const WindowsOverlaySet* displays)
    : config_window_(config_window), displays_(displays) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

WindowChannel::~WindowChannel() {
  channel_->SetMethodCallHandler(nullptr);
}

void WindowChannel::NotifyConfigWindowClosed() {
  channel_->InvokeMethod("onConfigWindowClosed", nullptr);
}

void WindowChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "showConfigWindow") {
    // A minimized window shown with SW_SHOW stays minimized; restore it.
    // SetForegroundWindow succeeds because the tray click that asked for
    // this window granted the process foreground rights; there is no other
    // path that shows it (spec §5.5).
    ShowWindow(config_window_,
               IsIconic(config_window_) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(config_window_);
    result->Success();
  } else if (method == "hideConfigWindow") {
    ShowWindow(config_window_, SW_HIDE);
    result->Success();
  } else if (method == "configFirstFrame") {
    // On macOS this signal is load-bearing: native shows the window
    // transparent and waits for Dart's first frame before revealing it, so
    // the pane appears already painted instead of as a black rectangle
    // filling in. W0's showConfigWindow shows the window directly, so there
    // is nothing here to reveal yet, but the method must still be answered
    // rather than refused, because the Dart caller does not catch. W5 owns
    // the real reveal-on-first-frame, with a deadline.
    result->Success();
  } else if (method == "replaceHotkeys") {
    const auto refused = AllIdsRefused(call.arguments());
    if (refused) {
      result->Success(flutter::EncodableValue(*refused));
    } else {
      result->Success();  // null: Dart reads "everything refused"
    }
  } else if (method == "unregisterAllHotkeys") {
    result->Success();
  } else if (method == "getScreenFrames") {
    flutter::EncodableList list;
    for (const auto& display : displays_->Displays()) {
      list.push_back(DisplayToValue(display));
    }
    result->Success(flutter::EncodableValue(list));
  } else if (method == "getActiveScreenFrame") {
    const auto display = displays_->DisplayUnderCursor();
    if (display) {
      result->Success(DisplayToValue(*display));
    } else {
      result->Success();  // null: Dart reads "no display", never a zero rect
    }
  } else {
    result->NotImplemented();
  }
}
