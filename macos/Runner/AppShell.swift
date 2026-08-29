import Cocoa

/// App-self UI helpers: show/hide the config window and open the Accessibility pane.
/// (Distinct from WindowControl, which manipulates *other* apps' windows.)
enum AppShell {
  /// The window's width, at every size it can be dragged to.
  ///
  /// Locked rather than merely initial: `configMinContentSize` and
  /// `configMaxContentSize` share it, which is how AppKit is told to offer a
  /// vertical drag only. Every pane, shortcut row, region glyph and the picker
  /// sheet were laid out against 560 pt, and revalidating them at other widths
  /// is a separate piece of work.
  static let configWidth: CGFloat = 560

  /// The **frame** height used only when there is no saved frame — a first run,
  /// or after the autosave entry is cleared. Every later open uses whatever
  /// AppKit restored, so this is not a size the app maintains.
  ///
  /// 620 fits the smallest display this was designed against (690 pt visible)
  /// with room to spare, and sits above `configMinContentSize` so AppKit has no
  /// correction to make on the first frame.
  static let configOpeningHeight: CGFloat = 620

  /// The resize limits, as a **content** size — `NSWindow.contentMinSize` and
  /// `contentMaxSize` are content sizes, unlike `configWidth`/`configOpeningHeight`
  /// which describe a frame. Feeding one to the other is how the settings window
  /// oscillated across six sizes on 2026-07-28; each API gets the unit it expects.
  ///
  /// **Equal widths are the mechanism, not a coincidence.** That is how AppKit is
  /// told to offer a vertical drag only, which keeps every pane at the 560 pt they
  /// were laid out against.
  ///
  /// The 500 pt floor is what the region picker needs: ~430 pt of fixed content —
  /// a 264 × 168 grid plus the name field, the shortcut field and the buttons —
  /// and both panes pin a footer that has to stay reachable.
  static let configMinContentSize = NSSize(width: configWidth, height: 500)
  static let configMaxContentSize =
    NSSize(width: configWidth, height: CGFloat.greatestFiniteMagnitude)

  /// Where macOS persists this window's frame. Using AppKit's own mechanism
  /// means no preferences key, no channel call and no Dart involvement — the
  /// size stops being something this app maintains at all.
  static let configAutosaveName = "OrthantConfigWindow"

  /// Whether showing the config window must establish its frame first.
  ///
  /// The question is only ever **"does this window have a real frame yet?"**,
  /// and the one state that does not is the launch sliver: assigning Flutter's
  /// initially zero-sized view collapses the nib window, measured here at
  /// `(1, 32)` with a content layout rect of `(1, 0)`. Something has to put a
  /// frame on that, or a first-run user gets an invisible onboarding window.
  ///
  /// **Visibility is deliberately not an input, and that is the fix of
  /// 2026-08-08.** This used to read `!isVisible || …`, from a time when
  /// "hidden" meant "has no frame worth keeping". `hideConfigWindow` is
  /// `orderOut`, which leaves the frame exactly as it was, so once the window
  /// gained an autosave name that term made **every reopen** re-place it: the
  /// user's dragged height was replaced by `configOpeningHeight` centred, and —
  /// because `setFrame` on a window with an autosave name writes through to
  /// `NSUserDefaults` — the size they chose was destroyed rather than merely
  /// ignored. A window that was merely ordered out is left exactly as they left
  /// it.
  ///
  /// A visible window with real content must not be reframed either.
  /// `showConfigWindow` is also used to bring an already-open Settings window
  /// forward; changing its frame with `display: false` lets Flutter adopt the
  /// new geometry while AppKit keeps presenting the old pixels. The picker is
  /// then drawn somewhere other than where it is hit-tested.
  ///
  /// **Deliberately a threshold rather than `isEmpty`.** `NSRect.isEmpty` is only
  /// true at height ≤ 0, so a sliver left with a single point of content area —
  /// one title-bar metric away, and not ours to control — would report "already
  /// placed" and leave a first-run user an invisible onboarding window. That is
  /// the failure this guard exists to prevent, so it degrades toward *placing*
  /// the window: the cost of an unnecessary placement is a window that lands
  /// centred, and the cost of a missed one is a window nobody can see.
  ///
  /// The gap is not close. Every real pane is at least the General tab's 446 pt,
  /// and the launch sliver is 0.
  static let minimumRealContentHeight: CGFloat = 100

  static func configWindowNeedsPlacement(contentLayoutRect: NSRect) -> Bool {
    contentLayoutRect.height < minimumRealContentHeight
  }

  static func showConfigWindow(_ window: NSWindow) {
    let tStart = CFAbsoluteTimeGetCurrent()
    // Set here rather than only in awakeFromNib: the nib-loaded title wins over
    // an assignment made during nib awakening, so the bar read a lowercase
    // "orthant". This runs immediately before the window is shown, which is the
    // one moment nothing can come after it.
    window.title = "Orthant"
    let wasVisible = window.isVisible
    if configWindowNeedsPlacement(contentLayoutRect: window.contentLayoutRect),
       let screen = NSScreen.main {
      let size = NSSize(width: configWidth, height: configOpeningHeight)
      let origin = NSPoint(
        x: screen.frame.midX - size.width / 2,
        y: screen.frame.midY - size.height / 2)
      // `display: false`: an ordinarily hidden window has nothing to display
      // into, and the launch-time sliver has no content pixels to preserve.
      // Forcing a display pass made this the moment the main Flutter view first
      // rasterised — Metal setup, pipelines and a full first frame — all
      // synchronously on the main thread, and it cost **1.2 s on the first
      // open**. Ordering the window front a few lines below displays it anyway.
      window.setFrame(NSRect(origin: origin, size: size), display: false)
    }
    let tPolicy = CFAbsoluteTimeGetCurrent()
    // Ordered front transparent, revealed once the pane has painted.
    //
    // Nothing has ever drawn this view — the window is `orderOut` from launch
    // and the app renders nothing until Settings is asked for — so the first
    // open pays a full build, layout and raster of the pane. Shown opaque, that
    // is **~230 ms of black window** before any widget appears, which reads as
    // broken rather than as a window still filling in. Same trick the overlay
    // uses, for the same reason.
    //
    // Only when it is not already up: `openSettings` is also called to switch
    // panes on a window that is already visible, and hiding that would be a
    // flash rather than a fix.
    if !wasVisible {
      awaitingFirstFrame = true
      window.alphaValue = 0
    }
    NSApp.setActivationPolicy(.regular)   // temporarily show in Dock/switcher while onboarding
    let tActivate = CFAbsoluteTimeGetCurrent()
    NSApp.activate(ignoringOtherApps: true)
    let tOrder = CFAbsoluteTimeGetCurrent()
    window.makeKeyAndOrderFront(nil)
    shownAt = CFAbsoluteTimeGetCurrent()
    if !wasVisible {
      // Never leave it invisible because Dart did not speak. A reveal that
      // depends on a reply needs a deadline — the same lesson the overlay's
      // fade recorded: a wedged isolate must not be able to strand native UI.
      revealGeneration += 1
      let generation = revealGeneration
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
        guard generation == revealGeneration else { return }
        revealConfigWindow(window)
      }
    }
    if timingEnabled {
      let tEnd = CFAbsoluteTimeGetCurrent()
      let ms = { (a: CFAbsoluteTime, b: CFAbsoluteTime) in
        String(format: "%.0f", (b - a) * 1000)
      }
      print("[orthant] showConfigWindow: frame \(ms(tStart, tPolicy)) ms, "
          + "setActivationPolicy \(ms(tPolicy, tActivate)) ms, "
          + "activate \(ms(tActivate, tOrder)) ms, "
          + "makeKeyAndOrderFront \(ms(tOrder, tEnd)) ms")
    }
  }

  /// Whether to print the open-path timings.
  ///
  /// An environment flag rather than `#if DEBUG`, because **the numbers that
  /// matter are not Debug's**: Flutter says outright that debug frame timings
  /// do not represent release performance, and gating on the build config makes
  /// the one configuration worth measuring the one that cannot be measured.
  /// `ORTHANT_TIMING=1 …/Orthant` works for Debug, Profile and Release alike,
  /// and costs a single environment read otherwise.
  static let timingEnabled =
    ProcessInfo.processInfo.environment["ORTHANT_TIMING"] != nil

  /// Time a synchronous handler and report it under [timingEnabled].
  ///
  /// Worth having for anything that talks to another process. This app runs
  /// with its **UI and platform threads merged**, so a slow call in a channel
  /// handler does not merely stall AppKit — it stalls Dart, and every click and
  /// keystroke queued behind it. "How long did the handler take" is therefore
  /// "how long was the app frozen", and that is not a number to guess at.
  static func timed<T>(_ label: String, _ body: () -> T) -> T {
    guard timingEnabled else { return body() }
    let started = CFAbsoluteTimeGetCurrent()
    let value = body()
    print(String(format: "[orthant] %@: %.0f ms",
                 label, (CFAbsoluteTimeGetCurrent() - started) * 1000))
    return value
  }

  /// When the config window was last ordered front, so the gap until Flutter's
  /// first frame can be measured rather than guessed at.
  static var shownAt: CFAbsoluteTime = 0

  /// Whether the window is on screen but still transparent, waiting for the
  /// pane's first frame.
  private static var awaitingFirstFrame = false

  /// Invalidates a pending fallback reveal, so an older one cannot un-hide a
  /// newer show.
  private static var revealGeneration = 0

  /// Show the window now that its content has painted.
  ///
  /// Called either by Dart's `configFirstFrame` or by the fallback below,
  /// whichever comes first, and harmless the second time.
  static func revealConfigWindow(_ window: NSWindow) {
    guard awaitingFirstFrame else { return }
    awaitingFirstFrame = false
    window.alphaValue = 1
    if timingEnabled, shownAt != 0 {
      let ms = (CFAbsoluteTimeGetCurrent() - shownAt) * 1000
      print(String(format: "[orthant] config window revealed after %.0f ms", ms))
    }
    shownAt = 0
  }

  static func hideConfigWindow(_ window: NSWindow) {
    // Reset the reveal state, or the next show would find `awaitingFirstFrame`
    // already false and never restore the alpha it is about to zero.
    awaitingFirstFrame = false
    revealGeneration += 1
    window.alphaValue = 1
    window.orderOut(nil)
    // Restored unconditionally until Task 8 (M12): this window closing used to
    // be the only way anything put the app in `.regular`, so nothing else
    // could still need it. Task 5 added a second way (the tray's *Check for
    // Updates…*), so Settings can now close while Sparkle's own window is
    // still up — and dropping to `.accessory` under a visible Sparkle window
    // leaves it unable to take keyboard focus properly (same problem this
    // window itself solved in M7). `mayReturnToAccessory()` is the same
    // predicate `Updater.finished()` restores behind; measured against a real
    // build (Task 8), `window.orderOut(nil)` above has already taken this
    // window itself out of contention by the time the predicate runs, so the
    // common case — Settings closes, nothing else up — keeps today's
    // unconditional behaviour without being special-cased for it.
    if mayReturnToAccessory() {
      NSApp.setActivationPolicy(.accessory) // back to menu-bar-only agent
    }
  }

  static func openAccessibilitySettings() {
    let url = URL(string:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
  }
}
