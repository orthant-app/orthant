// overlay_rules's tests: one executable, run by ctest, that prints each
// failure and exits non-zero when there is one.

#include <cmath>
#include <cstdio>
#include <limits>
#include <string>

#include "overlay_rules.h"

namespace {

int failures = 0;

void Check(bool ok, const char* what) {
  if (!ok) {
    std::printf("FAIL %s\n", what);
    ++failures;
  }
}

void StaleSummons() {
  Check(!IsStaleSummon(0, 0), "a tray summon has no press, so is never stale");
  Check(!IsStaleSummon(0, 5000), "a tray summon is not stale at any age");
  Check(!IsStaleSummon(1, 999), "a press 999 ms ago is fresh");
  Check(!IsStaleSummon(1, kStaleSummonMs), "a press exactly at the limit is fresh");
  Check(IsStaleSummon(1, 1001), "a press 1001 ms ago is stale");
  Check(IsStaleSummon(1, -1), "a press from the future is stale");
}

void PressTicks() {
  Check(PressTickAt(1000050, 1000000) == 1000000,
        "a press 50 ms ago is 50 ms ago");
  Check(PressTickAt(1000000, 1000000) == 1000000,
        "a press this moment is now");
  // The low 32 bits wrapped between the press and now.
  const uint64_t now = 0x100000010ull;
  Check(PressTickAt(now, 0xFFFFFFF0u) == static_cast<double>(0xFFFFFFF0ull),
        "a press just before the low 32 bits wrapped is 32 ms ago");
  // Fifty days of uptime: only the low bits travel in the message.
  const uint64_t later = 0x100000000ull * 3 + 500;
  Check(PressTickAt(later, 400) == static_cast<double>(later - 100),
        "a press after several wraps is still 100 ms ago");
}

void ForegroundMoves() {
  const uint32_t own = 10, runner = 1, sparkle = 2, captured = 20, other = 30;
  Check(ClassifyForegroundMove(own, runner, false, own, runner, captured) ==
            ForegroundMove::kStays,
        "the runner thread's own window keeps the selection");
  Check(ClassifyForegroundMove(own, sparkle, false, own, runner, captured) ==
            ForegroundMove::kUpdater,
        "another thread of this process (the updater) ends it");
  Check(ClassifyForegroundMove(captured, 7, false, own, runner, captured) ==
            ForegroundMove::kStays,
        "the captured app's own window keeps it");
  Check(ClassifyForegroundMove(captured, 7, true, own, runner, captured) ==
            ForegroundMove::kShell,
        "a shell surface ends it, even in the captured process");
  Check(ClassifyForegroundMove(other, 7, true, own, runner, captured) ==
            ForegroundMove::kShell,
        "the taskbar or Start ends it as the shell");
  Check(ClassifyForegroundMove(other, 7, false, own, runner, captured) ==
            ForegroundMove::kOtherApp,
        "another app's window ends it");
}

void ChannelValues() {
  const flutter::EncodableValue i32(int32_t{7});
  const flutter::EncodableValue i64(int64_t{1} << 40);
  const flutter::EncodableValue real(1.5);
  const flutter::EncodableValue text(std::string("7"));
  const flutter::EncodableValue nan(std::numeric_limits<double>::quiet_NaN());
  const flutter::EncodableValue inf(std::numeric_limits<double>::infinity());

  Check(IntOf(&i32) == 7, "an int32 is a whole number");
  Check(IntOf(&i64) == (int64_t{1} << 40), "an int64 is a whole number");
  Check(!IntOf(&real), "a double is not a whole number");
  Check(!IntOf(&text), "a string is not a whole number");
  Check(!IntOf(nullptr), "nothing is not a whole number");

  Check(NumberOf(&real) == 1.5, "a double is a number");
  Check(NumberOf(&i32) == 7.0, "a whole number is a number");
  Check(!NumberOf(&nan), "NaN is refused");
  Check(!NumberOf(&inf), "infinity is refused");
  Check(!NumberOf(&text), "a string is not a number");
  Check(!NumberOf(nullptr), "nothing is not a number");

  const flutter::EncodableValue named(flutter::EncodableMap{
      {flutter::EncodableValue("sessionId"), flutter::EncodableValue(9)},
      {flutter::EncodableValue("x"), flutter::EncodableValue(1.0)},
  });
  const flutter::EncodableValue unnamed(flutter::EncodableMap{
      {flutter::EncodableValue("x"), flutter::EncodableValue(1.0)},
  });
  const flutter::EncodableValue wrong(flutter::EncodableMap{
      {flutter::EncodableValue("sessionId"), flutter::EncodableValue("9")},
  });
  Check(SessionOf(&named) == 9, "a map names its session");
  Check(SessionOf(&i32) == 7, "a bare number is the session");
  Check(SessionOf(&unnamed) == -1, "a map without sessionId names none");
  Check(SessionOf(&wrong) == -1, "a sessionId that is not a number names none");
  Check(SessionOf(&real) == -1, "a bare double names none");
  Check(SessionOf(nullptr) == -1, "no arguments name none");
}

}  // namespace

int main() {
  StaleSummons();
  PressTicks();
  ForegroundMoves();
  ChannelValues();
  std::printf("overlay_rules: %d failure(s)\n", failures);
  return failures == 0 ? 0 : 1;
}
