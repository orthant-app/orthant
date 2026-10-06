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

  // A message posted to the host window. True if it was this set's.
  bool HandleHostMessage(UINT message);

  // A WM_HOTKEY. True if the overlay consumed it: one of its grabs, or any
  // other hotkey while a session is live (macOS suppressesRegionHotkeys), so
  // nothing can capture anew underneath an open grid.
  bool HandleHotkey(int id);

  // A summon's WM_HOTKEY arrived. `message_time` is its GetMessageTime, so the
  // session's trigger is the press, not the dispatch, and a summon that
  // reaches Show long after its press is refused as stale.
  void StampTrigger(LONG message_time);

  // A summon that will not reach Show (Dart found nothing to capture, never
  // heard of it, or sent no readable captureId): its press must not be taken
  // for the next summon's.
  void ForgetTrigger() { pending_trigger_ms_ = 0; }

  void SetGrid(int cols, int rows, double gap, bool save_hint);
  ShowResult Show(int64_t session_id, const std::string& app_name);
  void Dismiss(const char* why);
  bool live() const { return session_.has_value(); }

#ifdef ORTHANT_DEV_BUILD
  // Parks every panel and reconciles, which reuses them all: an attach and
  // detach of every monitor through the real reconcile path, for the
  // acceptance's memory measurement (a real detach is not scriptable).
  void DebugCyclePanels();
#endif

  struct Panel;

 private:
  struct Session {
    int64_t id;
    double trigger_ms;
    Panel* active = nullptr;
    Panel* press_locked = nullptr;
  };

  static LRESULT CALLBACK PanelProc(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam);
  LRESULT HandlePanelMessage(Panel& panel, HWND hwnd, UINT message,
                             WPARAM wparam, LPARAM lparam);

  // Panels.
  Panel* CreatePanel(HMONITOR monitor);
  void Reconcile(const char* reason);
  void Fit(Panel& panel);
  void ScheduleAttach();
  void AttachNext();
  void AttachEngine(Panel& panel);
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
                                      const std::string& app_name, bool active,
                                      bool warm) const;
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
  UINT attach_message_;

  // Owned for the life of the set: parked, never freed, so a Panel* held by a
  // callback or a session stays valid until the destructor.
  std::vector<std::unique_ptr<Panel>> panels_;
  int next_index_ = 0;

  bool reconcile_posted_ = false;
  const char* reconcile_reason_ = "launch";
  bool reconciling_ = false;
  bool reconcile_again_ = false;
  bool attach_posted_ = false;
  LARGE_INTEGER started_{};
  bool announced_ready_ = false;

  std::optional<Session> session_;
  bool showing_ = false;  // inside Show, which a resize can re-enter
  double pending_trigger_ms_ = 0;  // the last summon hotkey, until Show
  std::vector<int> grabbed_;

  int cols_ = 6;
  int rows_ = 6;
  double gap_ = 0;
  bool save_hint_ = false;
};

#endif  // RUNNER_WINDOWS_OVERLAY_SET_H_
