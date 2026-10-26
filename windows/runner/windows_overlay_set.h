#ifndef RUNNER_WINDOWS_OVERLAY_SET_H_
#define RUNNER_WINDOWS_OVERLAY_SET_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// One resident overlay panel per monitor, each hosting its own Flutter engine
// running overlayMain. The twin of macos/Runner/OverlayPanelSet.swift: any
// change to overlay session semantics is a two-file, two-platform,
// two-acceptance-suite change, and this comment exists so the second half is
// not forgotten.
//
// The panels are also the documented source of per-monitor DPI (W1):
// GetDpiForMonitor's own documentation says it "should not be used if the
// calling thread is per-monitor DPI aware" and points to GetDpiForWindow,
// which needs a window on the monitor.
//
// Where this differs from macOS, and why:
// - A session is named by Dart's capture id, and a commit is forwarded to
//   Dart, which owns the captured window on this platform; Dart applies it
//   only if that id is still its current, unapplied capture.
// - No fade. A panel is shown cloaked and revealed on its engine's next
//   presented frame, with a deadline, so what its surface held from an
//   earlier session is not seen. Not proven for a re-summon within about two
//   frames of the last frame an earlier session drew, which can still be in
//   the engine's two-frame pipeline and fire the new callback; no human input
//   is that fast.
// - A panel whose monitor goes away is parked, not destroyed, and reused for
//   the next monitor that comes: on this platform a destroyed engine leaks
//   several megabytes, and a new one costs over a second of the UI thread.
class WindowsOverlaySet {
 public:
  struct Display {
    RECT work;  // rcWork, physical pixels, top-left origin
    UINT dpi;   // GetDpiForWindow of this monitor's panel
  };

  // Where a commit goes once the panels are dismissed: to the main engine,
  // which owns the captured window. Each receives the payload for Dart.
  struct Forward {
    std::function<void(flutter::EncodableMap)> commit;
    std::function<void(flutter::EncodableMap)> save_region;
  };

  enum class ShowResult { kShown, kNotReady, kStale, kKeysRefused };

  // Hotkey ids from here up are the overlay's grabs, on the same window as
  // the shortcuts, whose ids are below it (Dart's HotkeyService._maxId is one
  // less, which a test holds the two to). RegisterHotKey wants 0x0000 to
  // 0xBFFF.
  static constexpr int kFirstGrabId = 900;

  WindowsOverlaySet(HWND host, Forward forward);
  ~WindowsOverlaySet();

  WindowsOverlaySet(const WindowsOverlaySet&) = delete;
  WindowsOverlaySet& operator=(const WindowsOverlaySet&) = delete;

  // Every monitor's work area and DPI, in panel order, from the panels that
  // are not parked. All or none: a monitor still attached with no working
  // panel empties the list, the rule Dart's displaysFromReply applies too.
  std::vector<Display> Displays() const;

  // The monitor under the cursor, or nullopt if it has no panel yet.
  std::optional<Display> DisplayUnderCursor() const;

  // A monitor came, went, changed mode or scale, or a work area moved. Any
  // session ends now; the panels are reconciled on a later turn of the loop.
  void OnDisplayChange(const char* reason);

  // A message posted to the host window, or one of this set's timers on it.
  // True if it was this set's.
  bool HandleHostMessage(UINT message, WPARAM wparam);

  // Launch has registered the hotkeys and built the tray (Dart's startOverlay,
  // or the deadline when that never comes), so the engines may attach. Until
  // then the panels exist, engine-less, and answer the display list.
  void StartEngines(const char* why);
  // Whether the next attach must wait: a hotkey's hold, or Dart's commands
  // within their ceiling.
  bool AttachHeld();

  // The user is doing something: a hotkey's command, or the tray's. The next
  // attach waits a second, so that work does not run behind one (each costs
  // over a second of this thread, measured). `press_ms` is the hotkey press
  // the hold is for (PressTick), 0 for anything else.
  void HoldAttaches(double press_ms = 0);
  // A menu (the tray's) is being tracked on this thread, whose modal loop
  // would run an attach and freeze the menu for its length: none starts while
  // it is open.
  void MenuLoop(bool open);

  // Dart's window commands are queued or running (true), or the last of them
  // has finished (false). No attach starts in between, up to a ceiling: a
  // placement leaves this thread idle between its reads, and an attach there
  // would hold the rest of the command for over a second.
  void CommandsRunning(bool running);

  // A WM_HOTKEY. True if the overlay consumed it: one of its grabs, or any
  // other hotkey while a session is live (macOS suppressesRegionHotkeys), so
  // nothing can capture anew underneath an open grid.
  bool HandleHotkey(int id);

  // A hotkey's press, from its WM_HOTKEY's GetMessageTime, in milliseconds on
  // the monotonic tick clock (GetTickCount64). It travels with the press to
  // Dart and, for a summon, back to Show, so the session's trigger is the
  // press, not the dispatch. A tick rather than the wall clock, so a clock
  // step (time sync after a wake) cannot make a fresh press look stale.
  static double PressTick(LONG message_time);

  void SetGrid(int cols, int rows, double gap, bool save_hint);
  // `pressed_ms` is the key press that asked for this summon, carried with it
  // (PressTick), or 0 for a summon with no press (the tray). A summon that
  // reaches Show more than a second after its press is refused as stale.
  // `app_icon` is the captured app's icon as PNG bytes, empty when Dart had
  // none cached; it then follows as SetAppIcon. `owner_pid` is the captured
  // window's process: the session ends when the foreground moves to a window
  // of any other process, or to one of the shell's surfaces (the desktop, the
  // taskbar, Start, Alt+Tab, Task View) whatever its process (click-away), and
  // 0 turns click-away off.
  ShowResult Show(int64_t session_id, const std::string& app_name,
                  const std::vector<uint8_t>& app_icon, double pressed_ms,
                  DWORD owner_pid);
  // An icon Dart read after the summon, for the panels of the live session
  // it names; dropped for any other.
  void SetAppIcon(int64_t session_id, const std::vector<uint8_t>& png);
  void Dismiss(const char* why);
  // Dart's hideOverlay: ends the live session only if it is `session_id`'s,
  // so a hide meant for one grid cannot end a newer one.
  void Hide(int64_t session_id);
  bool live() const { return session_.has_value(); }

  struct Panel;

 private:
  struct Session {
    int64_t id;
    double trigger_ms;
    DWORD owner_pid = 0;
    Panel* active = nullptr;
    Panel* press_locked = nullptr;
  };

  // Click-away: macOS dismisses on a click outside every panel through event
  // monitors. A panel covers its monitor's work area, so the click that lands
  // outside every panel is on the taskbar, which takes the foreground; so does
  // Alt+Tab, the Start menu, or a notification. Hooked only while a session
  // is live, so a hidden overlay costs nothing.
  static void CALLBACK ForegroundChanged(HWINEVENTHOOK hook, DWORD event,
                                         HWND hwnd, LONG object, LONG child,
                                         DWORD thread, DWORD time);
  void OnForeground(HWINEVENTHOOK hook, HWND hwnd);
  void Unhook();

  static LRESULT CALLBACK PanelProc(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam);
  LRESULT HandlePanelMessage(Panel& panel, HWND hwnd, UINT message,
                             WPARAM wparam, LPARAM lparam);

  // Panels.
  Panel* CreatePanel(HMONITOR monitor);
  void Reconcile(const char* reason);
  void Fit(Panel& panel);
  void ScheduleAttach();
  // A summon that Show refused: the hold its press set protects a command
  // that is now over, and only delays the engines it was waiting for.
  void ReleaseHold(double press_ms);
  void AttachNext();
  void AttachEngine(Panel& panel);
  void AttachFailed(Panel& panel, const char* why);
  void RetryAttaches();
  void OnPanelDpiChanged(Panel& panel, UINT dpi);
  std::vector<Panel*> Live() const;
  Panel* PanelFor(HMONITOR monitor) const;
  Panel* Parked() const;
  std::optional<Display> DisplayFor(const Panel& panel) const;

  // Session.
  void HandleOverlayCall(
      Panel& panel, const flutter::MethodCall<flutter::EncodableValue>& call);
  flutter::EncodableMap SummonPayload(const Panel& panel, int64_t session_id,
                                      double trigger_ms,
                                      const std::string& app_name,
                                      const std::vector<uint8_t>& app_icon,
                                      bool active, bool warm) const;
  bool GrabKeys();
  void ReleaseKeys();
  void Relay(const char* method, flutter::EncodableValue arguments);
  void BecameActive(int64_t session_id, Panel* panel);
  void Commit(int64_t session_id, const flutter::EncodableMap* args,
              Panel* panel, bool save);
  void Reveal(Panel& panel, const char* why);
  void Cloak(Panel& panel, bool on);
  void ArmFrame(Panel& panel);
  void OnFramePresented(Panel& panel, uint64_t shows);
  bool AwaitsFrame(const Panel& panel) const;
  void Warm(Panel& panel);
  void EndWarm(Panel& panel, uint64_t shows, const char* why);
  void NoteReady();

  HINSTANCE instance_;
  HWND host_;
  Forward forward_;
  UINT reconcile_message_;

  // Owned for the life of the set: parked, never freed, so a Panel* held by a
  // callback or a session stays valid until the destructor.
  std::vector<std::unique_ptr<Panel>> panels_;
  int next_index_ = 0;

  bool reconcile_posted_ = false;
  const char* reconcile_reason_ = "launch";
  bool reconciling_ = false;
  bool reconcile_again_ = false;
  ULONGLONG hold_until_ = 0;  // no attach starts before this tick
  double hold_press_ = 0;     // the hotkey press that hold is for, or 0
  bool menu_open_ = false;
  bool commands_running_ = false;
  ULONGLONG commands_since_ = 0;  // the tick they started running
  bool commands_ceiling_logged_ = false;
  bool engines_started_ = false;
  bool attach_retry_set_ = false;
#ifdef ORTHANT_DEV_BUILD
  // How many attaches still to fail on purpose (ORTHANT_DEBUG_FAIL_ATTACHES),
  // so the acceptance can watch a failed attach be retried.
  int attaches_to_fail_ = 0;
#endif
  LARGE_INTEGER started_{};
  bool announced_ready_ = false;

  std::optional<Session> session_;
  bool showing_ = false;  // inside Show, which a resize can re-enter
  HWINEVENTHOOK foreground_hook_ = nullptr;
  std::vector<int> grabbed_;

  int cols_ = 6;
  int rows_ = 6;
  double gap_ = 0;
  bool save_hint_ = false;
};

#endif  // RUNNER_WINDOWS_OVERLAY_SET_H_
