#ifndef RUNNER_CONFIG_WINDOW_H_
#define RUNNER_CONFIG_WINDOW_H_

#include <windows.h>

#include <cstdint>
#include <functional>

// The settings window's frame and its first paint: the twin of the macOS
// window's rules (macos/Runner/AppShell.swift, MainFlutterWindow.swift).
//
// The OS owns the frame, Dart owns the content, and the content scrolls.
// Nothing about the window's size ever crosses the channel, so there is no
// loop between a pane's measurement and the window's size to race. The width
// is pinned at the 560 every pane was laid out against and the height has the
// region picker's floor, both in device-independent pixels at the window's
// own DPI; the frame persists in the registry under the app's key and is put
// back before the window is first shown; a first open is centred on the
// monitor under the cursor. A show is cloaked until the screen has drawn and
// the engine has presented it, or a deadline passes, so the window never
// appears white when its frame comes.
//
// "Drawn" is Dart's configFirstFrame, sent after a screen's first frame is
// built, which on a cold engine is before that frame is on screen (measured:
// a reveal on the signal alone showed a 91 % white window at a first launch).
// So the signal arms the engine's next presented frame, and that reveals.
class ConfigWindow {
 public:
  // The client size every pane was laid out against, the floor that keeps
  // the region picker's fixed content on screen, and the height of a first
  // open: macOS's 620 pt frame less its title bar.
  static constexpr int kWidthDip = 560;
  static constexpr int kMinHeightDip = 500;
  static constexpr int kOpeningHeightDip = 592;

  // A native show never waits on Dart without a deadline. A screen that never
  // reports its first frame is revealed by the first; one whose reported frame
  // is never presented, by the second, counted from the report. Two, because
  // a slow first launch reported late (measured: its frame presented 40 ms
  // after a 750 ms deadline from the show had revealed a white window), and
  // an invisible window for a moment longer beats a white one.
  static constexpr UINT kShowDeadlineMs = 2000;
  static constexpr UINT kPresentDeadlineMs = 250;

  // A move or resize is kept this long after the window stops moving, so a
  // snap, a keyboard move or a monitor change is kept even if the app quits
  // with the window open (Quit exits without hiding it).
  static constexpr UINT kSaveDelayMs = 1000;

  // Asks the engine to report its next presented frame by posting
  // FramePresentedMessage() to the window with the given generation in
  // wparam, and to draw one; whether it could.
  using ArmFrame = std::function<bool(uint64_t generation)>;

  // Keeps other work off this thread while a show waits to be revealed.
  using Hold = std::function<void()>;

  // Takes the window as created, hidden and with no Flutter view yet: removes
  // its maximize box and places it, while a resize costs nothing.
  ConfigWindow(HWND hwnd, ArmFrame arm_frame, Hold hold);

  // The message an armed frame posts.
  static UINT FramePresentedMessage();

  ConfigWindow(const ConfigWindow&) = delete;
  ConfigWindow& operator=(const ConfigWindow&) = delete;

  // The channel's showConfigWindow. A hidden window is shown cloaked and
  // revealed by FirstFrame or the deadline; a window already up is only
  // brought forward. A window whose monitor went away while it was hidden is
  // placed again first.
  void Show();

  // The channel's hideConfigWindow and the window's own close: the frame is
  // saved while it is still a frame, then the window hides.
  void Hide();

  // The channel's configFirstFrame: the screen has drawn, so the next frame
  // the engine presents reveals the window.
  void FirstFrame();

  // The messages this class answers for the window: the size limits, the
  // edges' hit test, the end of a user's move or resize and any later move
  // (saved), the presented frame and the reveal's deadlines. True with
  // *result set when the message is handled here and must go no further.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam,
                     LRESULT* result);

 private:
  // Puts the window where it opens: the saved frame if its monitor is still
  // there, otherwise centred on the monitor under the cursor.
  void Place();
  void Save();
  void Reveal(const char* why);

  // Arms the engine's next presented frame for the current show, unless one
  // is armed already: an engine keeps one next-frame callback, and a second
  // registered while one is in flight can leave an empty one to be called.
  void Arm();

  // The window's outer size for a client of the given device-independent
  // size at dpi.
  SIZE OuterSize(int width_dip, int height_dip, UINT dpi) const;

  HWND hwnd_;
  ArmFrame arm_frame_;
  Hold hold_;
  bool awaiting_frame_ = false;
  // Whether the screen has reported its first frame for the current show.
  bool reported_ = false;
  // Whether the engine holds a next-frame callback of ours.
  bool frame_armed_ = false;
  // Which cloaked show a presented frame belongs to.
  uint64_t shows_ = 0;
  ULONGLONG shown_at_ = 0;
};

#endif  // RUNNER_CONFIG_WINDOW_H_
