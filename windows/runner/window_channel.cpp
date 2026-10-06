#include "window_channel.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <iostream>
#include <optional>
#include <string>
#include <utility>

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

const flutter::EncodableValue* Field(const flutter::EncodableValue* arguments,
                                     const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return nullptr;
  const auto it = map->find(flutter::EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

std::optional<int64_t> IntOf(const flutter::EncodableValue* value) {
  if (!value) return std::nullopt;
  if (const auto* v = std::get_if<int32_t>(value)) return *v;
  if (const auto* v = std::get_if<int64_t>(value)) return *v;
  return std::nullopt;
}

}  // namespace

WindowChannel::WindowChannel(flutter::BinaryMessenger* messenger,
                             HWND config_window,
                             WindowsOverlaySet* overlays)
    : config_window_(config_window), overlays_(overlays) {
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

void WindowChannel::NotifyOverlayCommit(flutter::EncodableMap payload) {
#ifdef ORTHANT_DEV_BUILD
  last_commit_ = payload;
#endif
  channel_->InvokeMethod("onOverlayCommit",
                         std::make_unique<flutter::EncodableValue>(
                             std::move(payload)));
}

void WindowChannel::NotifyOverlaySaveRegion(flutter::EncodableMap payload) {
  channel_->InvokeMethod("onOverlaySaveRegion",
                         std::make_unique<flutter::EncodableValue>(
                             std::move(payload)));
}

#ifdef ORTHANT_DEV_BUILD
void WindowChannel::NotifyDebugSummon() {
  // A press stamped for a summon Dart never hears of (its handler is not set
  // in the first moments after launch) must not be taken for the next
  // summon's: the engine answers that case "not implemented".
  WindowsOverlaySet* overlays = overlays_;
  channel_->InvokeMethod(
      "onDebugSummon", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          nullptr,
          [overlays](const std::string&, const std::string&,
                     const flutter::EncodableValue*) {
            overlays->ForgetTrigger();
          },
          [overlays]() { overlays->ForgetTrigger(); }));
}

void WindowChannel::DebugReplayLastCommit() {
  if (!last_commit_) {
    std::cout << "[orthant] overlay commit replay: nothing to replay"
              << std::endl;
    return;
  }
  // find, not at: with exceptions off, at() on a missing key terminates.
  const auto it = last_commit_->find(flutter::EncodableValue("sessionId"));
  const std::optional<int64_t> id =
      it == last_commit_->end() ? std::nullopt : IntOf(&it->second);
  std::cout << "[orthant] overlay commit replayed: id=" << id.value_or(-1)
            << std::endl;
  channel_->InvokeMethod(
      "onOverlayCommit",
      std::make_unique<flutter::EncodableValue>(*last_commit_));
}
#endif

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
    for (const auto& display : overlays_->Displays()) {
      list.push_back(DisplayToValue(display));
    }
    result->Success(flutter::EncodableValue(list));
  } else if (method == "getActiveScreenFrame") {
    const auto display = overlays_->DisplayUnderCursor();
    if (display) {
      result->Success(DisplayToValue(*display));
    } else {
      result->Success();  // null: Dart reads "no display", never a zero rect
    }
  } else if (method == "setOverlayGrid") {
    // Plain numbers from Dart's settings, included in every summon. saveHint
    // defaults rather than being required, as on macOS.
    const auto cols = IntOf(Field(call.arguments(), "cols"));
    const auto rows = IntOf(Field(call.arguments(), "rows"));
    const auto* gap = Field(call.arguments(), "gap");
    const auto* gap_value = gap ? std::get_if<double>(gap) : nullptr;
    const auto* save_hint = Field(call.arguments(), "saveHint");
    const auto* save_hint_value =
        save_hint ? std::get_if<bool>(save_hint) : nullptr;
    if (cols && rows && gap_value) {
      overlays_->SetGrid(static_cast<int>(*cols), static_cast<int>(*rows),
                         *gap_value, save_hint_value && *save_hint_value);
    }
    result->Success();
  } else if (method == "showOverlay") {
    // {captureId, appName}: Dart has captured the window already, and the
    // session is named by that capture's id. The reply is whether it showed:
    // engines not attached yet, or Esc or Enter refused, is false.
    const auto capture_id = IntOf(Field(call.arguments(), "captureId"));
    const auto* app_name = Field(call.arguments(), "appName");
    const auto* app_name_value =
        app_name ? std::get_if<std::string>(app_name) : nullptr;
    const bool shown =
        capture_id &&
        overlays_->Show(*capture_id,
                        app_name_value ? *app_name_value : std::string()) ==
            WindowsOverlaySet::ShowResult::kShown;
    result->Success(flutter::EncodableValue(shown));
  } else if (method == "hideOverlay") {
    // Also how Dart ends a summon that will not reach showOverlay (nothing to
    // capture), so that its press is not taken for the next summon's.
    overlays_->ForgetTrigger();
    overlays_->Dismiss("hideOverlay");
    result->Success();
  } else {
    result->NotImplemented();
  }
}
