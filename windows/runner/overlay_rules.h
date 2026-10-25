#ifndef RUNNER_OVERLAY_RULES_H_
#define RUNNER_OVERLAY_RULES_H_

#include <flutter/encodable_value.h>

#include <cstdint>
#include <optional>

// The overlay session's own decisions, kept free of Win32 calls and the
// engine so that overlay_rules_test.cpp can make them (ctest runs it).
// WindowsOverlaySet asks the system what it needs and passes the answers in.

// A hotkey summon reaching Show later than this after its press waited behind
// something: this thread (an engine attaching takes over a second, measured),
// or a placement ahead of it in Dart's command queue. Shown now, it would take
// Esc, Enter and the arrows from whatever the user has moved on to. Each
// summon carries its own press time, through Dart and back in showOverlay, so
// two presses cannot share one, and nothing is left over to be mistaken for a
// later summon's.
constexpr double kStaleSummonMs = 1000;

// Whether a summon pressed `age_ms` ago is too old to show. A summon with no
// press (the tray's, `pressed_ms` 0) never is; a press from the future is no
// press of ours (the tick is this machine's and monotonic), so it is.
bool IsStaleSummon(double pressed_ms, double age_ms);

// The press time of a hotkey message on GetTickCount64's clock, given that
// clock now and the message's time. A message time is the low 32 bits of the
// same tick count, to its resolution, so the difference is taken modulo 2^32:
// a press just before the low 32 bits wrapped is still a moment ago.
double PressTickAt(uint64_t now, uint32_t message_time);

// Where the foreground went while a grid selection is up.
enum class ForegroundMove {
  // A window of the runner's own thread (Orthant's own windows: a tray
  // summon's foreground is the hidden window until its capture reactivates
  // the target), or one of the captured app's own (that capture, or a dialog
  // of the app's): the selection stays.
  kStays,
  // The taskbar, Start or a flyout: the user went elsewhere.
  kShell,
  // A window of another thread of this process: the updater's (WinSparkle
  // runs its windows on a thread of its own). Left up, the grid's grabbed
  // Enter and arrows would act on the captured window while the user answers
  // the updater.
  kUpdater,
  // Any other process's window.
  kOtherApp,
};

// The move to `pid`'s window on `thread`, `shell` when its class is one of
// the shell's surfaces, from a session whose runner is `own_pid` on
// `own_thread` and whose captured window belongs to `captured_pid`.
ForegroundMove ClassifyForegroundMove(uint32_t pid, uint32_t thread,
                                      bool shell, uint32_t own_pid,
                                      uint32_t own_thread,
                                      uint32_t captured_pid);

// A whole number from the channel, which sends a Dart int as int32 or int64.
std::optional<int64_t> IntOf(const flutter::EncodableValue* value);

// A finite number from the channel: a double, or a whole number.
std::optional<double> NumberOf(const flutter::EncodableValue* value);

// The session a call names: {sessionId: n, ...}, or a bare n; -1 for neither.
int64_t SessionOf(const flutter::EncodableValue* arguments);

#endif  // RUNNER_OVERLAY_RULES_H_
