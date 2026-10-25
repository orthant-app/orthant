#include "overlay_rules.h"

#include <cmath>
#include <variant>

bool IsStaleSummon(double pressed_ms, double age_ms) {
  return pressed_ms > 0 && (age_ms > kStaleSummonMs || age_ms < 0);
}

double PressTickAt(uint64_t now, uint32_t message_time) {
  const uint32_t queued = static_cast<uint32_t>(now) - message_time;
  return static_cast<double>(now - queued);
}

ForegroundMove ClassifyForegroundMove(uint32_t pid, uint32_t thread,
                                      bool shell, uint32_t own_pid,
                                      uint32_t own_thread,
                                      uint32_t captured_pid) {
  if (pid == own_pid && thread == own_thread) return ForegroundMove::kStays;
  if (pid == captured_pid && !shell) return ForegroundMove::kStays;
  if (shell) return ForegroundMove::kShell;
  if (pid == own_pid) return ForegroundMove::kUpdater;
  return ForegroundMove::kOtherApp;
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

int64_t SessionOf(const flutter::EncodableValue* arguments) {
  if (!arguments) return -1;
  if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
    const auto it = map->find(flutter::EncodableValue("sessionId"));
    return IntOf(it == map->end() ? nullptr : &it->second).value_or(-1);
  }
  return IntOf(arguments).value_or(-1);
}
