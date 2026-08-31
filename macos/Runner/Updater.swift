import Cocoa
import Sparkle

/// Sparkle, and the activation-policy dance an agent app needs around it.
///
/// Orthant runs as `.accessory` with no Dock icon, and a window shown from an
/// accessory app cannot take keyboard focus properly — the same problem the
/// settings window solved in M7, with the same answer. Restoring `.accessory`
/// afterwards is the part that bites: leave it in `.regular` and the app keeps a
/// Dock icon it should not have, indefinitely, with nothing on screen to explain
/// why.
///
/// This does **not** violate "Orthant must never become the frontmost window".
/// That invariant is about the *placement* path, where a target window is
/// captured before any UI appears. An update check is user-initiated and has no
/// captured window to lose.
enum Updater {
  /// Notices when Sparkle's own UI session is over, so something can call
  /// `Updater.finished()`. `SPUStandardUserDriverDelegate` is `@optional`
  /// throughout — this implements only the one callback that marks a
  /// session's end. It is the *primary* trigger, not the only one — see
  /// `closeObserver` below for why a second one exists.
  private final class SessionDelegate: NSObject, SPUStandardUserDriverDelegate {
    /// Sparkle is about to run a modal alert. This is the **only** hook that
    /// covers an *error* alert: `standardUserDriverWillHandleShowingUpdate`
    /// below fires for an update Sparkle found, but a failure — a bad
    /// signature, an unreachable feed — never takes that path. Without this,
    /// `showUpdaterError:` closes the preceding status window one line before
    /// building its `NSAlert`, the session-end hook below fires on that close,
    /// and its deferred `finished()` drops the app to `.accessory` while the
    /// alert does not exist yet. The alert then appears in an app with no Dock
    /// icon and no ⌘-Tab entry, reachable only by minimising every other
    /// window — reproduced by the tamper test on 2026-08-31, and the answer to
    /// the question M12 Task 9 left open.
    ///
    /// Fires strictly before `[alert runModal]` (verified in
    /// `SPUStandardUserDriver.m` `-showAlert:secondaryAction:`), so the policy
    /// is already `.regular` when the window appears. A fix by construction
    /// rather than by timing: nothing here depends on when the alert registers
    /// in `NSApp.windows`, which is the actual bug.
    func standardUserDriverWillShowModalAlert() {
      sparkleModalAlertOnScreen = true
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    }

    /// Fires after `runModal` **returns** — after the user dismissed the alert,
    /// not when it appeared. The name reads like the latter; the source says
    /// otherwise, and the pair brackets the whole modal session. Clearing the
    /// flag and re-asking `finished()` is what restores `.accessory`: any
    /// deferred call that ran mid-session was correctly refused, so something
    /// has to ask again once the alert is gone.
    func standardUserDriverDidShowModalAlert() {
      sparkleModalAlertOnScreen = false
      DispatchQueue.main.async { Updater.finished() }
    }

    func standardUserDriverWillFinishUpdateSession() {
      // Fires while Sparkle's own status/alert window can still be on
      // screen — the method is "will finish", not "did finish". Calling
      // `finished()` synchronously from here would let its "no visible
      // windows" guard see that window and bail. Deferring to the next
      // run-loop turn lets the window finish closing first — measured
      // (fix round, Task 4) against a real check-error alert (the
      // production feed 404s): reliable whenever this is the *only* modal
      // session active, because a queued `.main.async` block runs the
      // moment the current `NSAlert -runModal` loop it was queued behind
      // exits, not before. It is not a substitute for `closeObserver`
      // below, which does not depend on this one delegate call being
      // reached for every session-end shape Sparkle has.
      DispatchQueue.main.async {
        Updater.finished()
      }
    }

    /// The activation-policy dance's other half. `checkForUpdates()` below
    /// only runs for a session the user *started* from the tray — a
    /// scheduled session lives entirely inside Sparkle's own background
    /// scheduler and never puts that method on the call stack, so without
    /// this hook a background check that finds an update would show
    /// Sparkle's alert while Orthant is still `.accessory` — a window that
    /// cannot take keyboard focus properly (see the doc comment atop this
    /// file, and `ActivationPolicy.swift`).
    ///
    /// Confirmed in the modern driver we use, `SPUStandardUserDriver.m` —
    /// the deprecated `SUUpdater` shim implements same-named delegate
    /// methods of its own, which are not this app's path. The
    /// scheduled-branch call physically fires inside
    /// `setUpActiveUpdateAlertForScheduledUpdate:state:` (lines 304/314,
    /// deferred and immediate), reached from
    /// `showUpdateFoundWithAppcastItem:state:reply:` rather than firing
    /// inside it directly. Either way it fires strictly before the
    /// corresponding alert becomes visible, whether that is immediate,
    /// ordered to the back, or deferred until the app is next active — so
    /// setting policy here always lands ahead of the window it is for. It
    /// also fires **unconditionally for a user-initiated session**
    /// (`state.userInitiated && [delegate respondsToSelector:...]`, a few
    /// lines above the scheduled branch in that same method) — always with
    /// `handleShowingUpdate == YES`, since this delegate does not implement
    /// `standardUserDriverShouldHandleShowingScheduledUpdate:
    /// andInImmediateFocus:` to ever decline showing one. That is why the
    /// branch below is a documented no-op rather than an assumption that
    /// this method only ever sees scheduled sessions.
    func standardUserDriverWillHandleShowingUpdate(
      _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
      state: SPUUserUpdateState
    ) {
      // Armed here too, not only from `checkForUpdates()`'s manual path:
      // this hook is the one checkpoint every session that can show UI
      // passes through before showing it, so forcing the backstop here
      // makes it armed ahead of *any* Sparkle window regardless of which
      // path constructed `controller` first — including a scheduled
      // session that is the first Sparkle activity the process has had.
      // Reading an already-initialised `static let` a second time is a
      // no-op, so this costs nothing when the manual path forced it first.
      _ = Updater.closeObserver

      if state.userInitiated {
        // This hook also fires, unconditionally, for a user-initiated
        // session (always with `handleShowingUpdate == YES` — see the doc
        // comment above). `checkForUpdates()` already set `.regular` and
        // activated before Sparkle could show anything on this path, and
        // Sparkle's own driver activates the app again regardless
        // (`setUpActiveUpdateAlertForScheduledUpdate:state:`, its
        // `updateItem == nil` branch). Calling
        // `setActivationPolicy(.regular)` again here would just repeat the
        // call `checkForUpdates()` already made — safe, but redundant —
        // so this returns early instead.
        return
      }

      // Scheduled: nobody asked, so unlike the manual path this must not
      // activate. `.regular` alone is expected to let the imminent alert
      // take keyboard focus like any other window, without pulling focus
      // away from whatever the user is doing — expected, not measured.
      // Every other `.regular` set in this app (`AppShell`'s onboarding
      // window, and `checkForUpdates()` below) pairs it with `activate`, so
      // a `.regular`-only window taking key focus on its own has no
      // precedent here, and there is no live scheduled session yet to
      // check it against. Task 15's re-acceptance battery is where this
      // gets its first real test; until then this paragraph is reasoning,
      // not a measurement. The top-of-file doc comment argues manual
      // checks don't violate "Orthant must never become the
      // frontmost window" because there is no captured target window to
      // lose — that argument does not extend to a check nobody asked for;
      // silently grabbing focus for it would violate the invariant's
      // spirit even though nothing was captured. If the user notices the
      // window and engages it, macOS activates the app the ordinary way
      // from there. Restoring `.accessory` afterwards needs no new
      // teardown: `finished()` — reached either via
      // `standardUserDriverWillFinishUpdateSession` above or via
      // `closeObserver` — already restores behind any session shape, this
      // one included, since neither call site cares how `.regular` got set.
      NSApp.setActivationPolicy(.regular)
    }
  }

  /// Retained here because `SPUStandardUpdaterController` only holds its
  /// `userDriverDelegate` **weakly** (it doubles as an Interface Builder
  /// outlet) — nothing else in the app would keep this instance alive.
  private static let driverDelegate = SessionDelegate()

  private static let controller = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: driverDelegate)

  /// Self-healing backstop for `.accessory` restoration, armed on first use
  /// — from either `checkForUpdates()`'s `_ = closeObserver` line below (the
  /// manual path) or `SessionDelegate`'s
  /// `standardUserDriverWillHandleShowingUpdate` above (scheduled sessions,
  /// which never put `checkForUpdates()` on the call stack) — whichever a
  /// running process reaches first.
  ///
  /// `standardUserDriverWillFinishUpdateSession` is the *only* place Sparkle
  /// 2.9.5 invokes the delegate hook above — confirmed by reading
  /// `SPUUIBasedUpdateDriver.m` / `SPUStandardUserDriver.m` in the resolved
  /// SPM checkout, not assumed, and re-confirmed at this pin: the sole call
  /// site is `SPUStandardUserDriver.m:933`, inside `dismissUpdateInstallation`.
  /// One call site covering every session-end
  /// shape (happy path, check error, download error, no-update, user
  /// cancel) is a single point of failure for all of them, and a live
  /// Release 1.0.0 run against the real (unpublished) feed reproduced
  /// exactly that failure mode: `probe policy` stuck at `regular` with
  /// `probe windows` already empty, for 25+ minutes, after the user had
  /// dismissed Sparkle's error alert. Reproducing the *exact* stuck state
  /// on demand proved elusive here — every dismiss this investigation could
  /// force eventually reached `finished()` through the delegate alone, some
  /// only after a queued call sat behind another still-open modal session
  /// until that one was also dismissed — but nothing about the delegate
  /// path is self-correcting if Sparkle simply never reaches
  /// `dismissUpdateInstallation` for some session shape. This does not
  /// depend on that call happening at all.
  ///
  /// So: watch for the thing `finished()` actually cares about, rather than
  /// trust one callback to always tell us. Sparkle's alert, status and
  /// checking windows close through plain `NSWindow` machinery like any
  /// other window in the app, regardless of which internal path Sparkle took
  /// to get there — confirmed in isolation, with Sparkle never entering the
  /// picture at all: force `.regular`, open and close an unrelated window,
  /// and this alone restores `.accessory`. `finished()` is cheap and
  /// idempotent (it is already called from two places for the same reason),
  /// so firing it more often than strictly necessary costs nothing; the
  /// guard inside answers "not yet" on every window close that is not the
  /// last one.
  private static let closeObserver: NSObjectProtocol =
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: nil, queue: .main
    ) { _ in
      guard NSApp.activationPolicy() == .regular else { return }
      // Same deferral, and the same reason, as the delegate callback above:
      // this fires while the closing window can still report
      // `isVisible == true`, so the guard needs the next run-loop turn to
      // see it actually gone.
      DispatchQueue.main.async { finished() }
    }

  /// Whether Sparkle checks for updates on its own schedule.
  ///
  /// Answered by Sparkle rather than by anything we store. `Info.plist`'s
  /// `SUEnableAutomaticChecks` is only the *initial* value; Sparkle persists
  /// the user's choice in its own defaults from then on, so a cached copy here
  /// would start lying the first time it was changed. Same reasoning as
  /// `LoginItemStatus`: ask the owner.
  ///
  /// Main thread, per `SPUUpdater`'s header. Every caller is a channel handler,
  /// which is already on it.
  static var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set { controller.updater.automaticallyChecksForUpdates = newValue }
  }

  /// Set it, then answer with what Sparkle actually holds afterwards.
  ///
  /// Deliberately not echoing back what was asked for. The property is Sparkle's
  /// and nothing here guarantees it took the value; a checkbox that reports the
  /// request rather than the result is a checkbox that can claim a state the
  /// system never entered. `setLoginItem` has the same shape for the same
  /// reason.
  static func setAutomaticallyChecksForUpdates(_ enabled: Bool) -> Bool {
    automaticallyChecksForUpdates = enabled
    return automaticallyChecksForUpdates
  }

  static func checkForUpdates() {
    // Forces `closeObserver` to register before this session's windows can
    // open and close — a `static let` initialises on first access, and
    // nothing else in the app was guaranteed to have touched it yet.
    _ = closeObserver
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    controller.checkForUpdates(nil)
  }

  /// Called when the updater has no window left on screen.
  ///
  /// Not, in fact, `NSApp.windows.allSatisfy { !$0.isVisible }` — that was
  /// this method's shape until Task 8 (M12) measured what is actually in
  /// `NSApp.windows` for a menu-bar app: the tray's own status-item window
  /// (`NSStatusBarWindow`), present and `isVisible == true` for the app's
  /// entire life. An `allSatisfy` with no exclusion for it can never pass, so
  /// `.accessory` was never restored after the first update check — a
  /// permanent Dock icon, silently, which is the activation-policy sibling of
  /// "the one failure this milestone exists to avoid." `mayReturnToAccessory()`
  /// is the same predicate `AppShell.hideConfigWindow` restores behind, so a
  /// Settings window left open through an update check also keeps the app in
  /// `.regular` rather than being missed by this call and dropped from under it.
  static func finished() {
    guard mayReturnToAccessory() else { return }
    NSApp.setActivationPolicy(.accessory)
  }
}
