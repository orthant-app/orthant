import Cocoa
import ApplicationServices
import FlutterMacOS

/// All rects here are in top-left-origin global points (CoreGraphics / AX space).
final class WindowControl {
  /// How long one AX message may block this process, in seconds.
  ///
  /// Every call below is **synchronous IPC to the target application**, made on
  /// the main thread, and macOS's own default cap is ~1.5 s per message. A
  /// capture plus a placement is seventeen of them: measured against a
  /// deliberately suspended TextEdit (`kill -STOP`), the sequence blocked for
  /// **25.6 s** — during which Orthant is frozen, the overlay cannot fade, and
  /// its natively-grabbed Esc cannot dismiss it. AX answers this case with
  /// `kAXErrorCannotComplete`, which is what makes it detectable at all.
  ///
  /// One second is far above a healthy app (tens of milliseconds, under load
  /// too) and comfortably below the default, so it never turns a slow answer
  /// into a failure. It is only half the fix: bounding one message means little
  /// when seventeen are queued behind it, so every read below reports
  /// `cannotComplete` up rather than collapsing it into a plain "no", and the
  /// caller stops at the first one. A placement into a hung app costs one
  /// timeout, not one per message.
  static let messagingTimeout: Float = 1.0

  init() {
    // On the system-wide element, which — unlike setting it per element — makes
    // it this *process's* timeout, inherited by app and window elements created
    // later. Verified by measurement: a fresh app element created afterwards
    // times out at this value, not the system default.
    AXUIElementSetMessagingTimeout(
      AXUIElementCreateSystemWide(), WindowControl.messagingTimeout)
  }

  private var capturedWindow: AXUIElement?
  private var capturedApp: AXUIElement?
  /// The app whose window is captured. Exposed so callers building UI from the
  /// capture (the overlay's app-name/icon chip) read *this* app rather than
  /// re-querying NSWorkspace.shared.frontmostApplication themselves — between
  /// two separate queries the frontmost app can change, which would describe
  /// a different app than the one actually captured.
  private(set) var capturedApplication: NSRunningApplication?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkAccessibilityPermission":
      result(Accessibility.isTrusted())
    case "requestAccessibilityPermission":
      Accessibility.requestTrust()
      result(nil)
    case "captureFrontmostWindow":
      result(captureFrontmost())
    case "getActiveScreenFrame":
      result(activeScreenFrame())
    case "getScreenFrames":
      result(screenFrames())
    case "applyFrameToCapturedWindow":
      guard let a = call.arguments as? [String: Any],
            let x = a["x"] as? Double, let y = a["y"] as? Double,
            let w = a["w"] as? Double, let h = a["h"] as? Double else {
        result(false); return
      }
      result(applyFrame(CGRect(x: x, y: y, width: w, height: h)) == .placed)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Capture

  /// Capture the frontmost app's focused window. Returns whether a window is now held.
  ///
  /// Clearing both handles first is load-bearing: every early return below must leave
  /// *nothing* captured, or a later applyFrame would move whichever window was captured
  /// on a previous, successful attempt.
  @discardableResult
  func captureFrontmostWindow() -> Bool {
    capturedWindow = nil
    capturedApp = nil
    capturedApplication = nil

    guard let app = NSWorkspace.shared.frontmostApplication else { return false }

    // Never capture ourselves. Orthant is frontmost only while its settings or
    // onboarding window is focused, and capturing that would put "orthant" in
    // the overlay's app chip and offer to snap the very window being
    // configured. Refusing here means show()'s capture-or-abort guard handles
    // it — nothing appears, no keys are grabbed.
    //
    // The invariant lives here rather than in Dart deliberately. Dart's version
    // of this was "is our window open?", which is a different question: leaving
    // the settings window open in the background silently killed the summon in
    // every other app. What actually matters is who is frontmost *now*, and
    // this is the only place that knows without a round trip.
    guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return false }

    let appEl = AXUIElementCreateApplication(app.processIdentifier)

    var winRef: CFTypeRef?
    var err = AXUIElementCopyAttributeValue(
      appEl, kAXFocusedWindowAttribute as CFString, &winRef)

    // The app is not answering (see `messagingTimeout`). Give up rather than
    // fall through to the second read below, which would block for another full
    // timeout to learn the same thing.
    if err == .cannotComplete { return false }

    // Not every focused element is a window. With Finder frontmost and no
    // Finder windows open, this attribute answers with the *Desktop*: an
    // AXScrollArea spanning every display whose size is not settable. Accepting
    // it made capture "succeed", so show()'s capture-or-abort guard never fired
    // and the grid appeared over an empty Desktop — where a drag then ended in
    // silence, because applyFrame cannot resize it.
    if err != .success || winRef == nil || !WindowControl.isWindow(winRef) {
      // Fallback: first *window* in kAXWindows. Filtering here too, since the
      // desktop can appear in that list for the same reason.
      var windowsRef: CFTypeRef?
      winRef = nil
      err = AXUIElementCopyAttributeValue(
        appEl, kAXWindowsAttribute as CFString, &windowsRef)
      if err == .success, let arr = windowsRef as? [AXUIElement],
         let first = arr.first(where: { WindowControl.isWindow($0 as CFTypeRef) }) {
        winRef = first
      }
    }

    guard let ref = winRef else { return false }
    capturedWindow = (ref as! AXUIElement)
    capturedApp = appEl
    capturedApplication = app
    return true
  }

  /// Whether an accessibility element is a real window we could place.
  ///
  /// Deliberately a role check only. Also demanding that position/size be
  /// settable would reject legitimate targets — a full-screen or otherwise
  /// constrained window — and this same capture feeds the direct region
  /// shortcuts, so over-tightening it here would regress those too.
  private static func isWindow(_ ref: CFTypeRef?) -> Bool {
    guard let ref = ref else { return false }
    var roleRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
            (ref as! AXUIElement), kAXRoleAttribute as CFString, &roleRef) == .success
    else { return false }
    return (roleRef as? String) == (kAXWindowRole as String)
  }

  /// The captured window's owning app name and current frame, for the channel.
  private func captureFrontmost() -> [String: Any] {
    // An unreadable frame fails the capture rather than reporting zeros: Dart
    // picks the target display from this rect, so a bogus one would compute the
    // region against the wrong screen and fling the window there.
    guard captureFrontmostWindow(), let window = capturedWindow,
          let frame = frameOf(window) else {
      return ["ok": false]
    }
    return [
      "ok": true,
      "appName": capturedApplication?.localizedName ?? "",
      "frame": ["x": frame.origin.x, "y": frame.origin.y,
                "w": frame.size.width, "h": frame.size.height],
    ]
  }

  /// The window's current frame, or nil if AX would not tell us.
  ///
  /// Optional on purpose. This used to fall back to a zero rect, which is a
  /// *plausible* frame rather than an obviously absent one: a failed read then
  /// compared equal to a target at the origin — the top-left of a display
  /// stacked above the primary, for instance — and `applyFrame` reported a
  /// placement that had not happened.
  private func frameOf(_ window: AXUIElement) -> CGRect? {
    return frameAndError(window).frame
  }

  /// The same read, **keeping the error** — see `boolAttribute` for why every AX
  /// call in the placement path has to. `nil` alone cannot distinguish "this
  /// window has no position" from "this app stopped answering a second ago",
  /// and only the second means every call after it is another second wasted.
  private func frameAndError(_ window: AXUIElement) -> (frame: CGRect?, error: AXError) {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    let posErr = AXUIElementCopyAttributeValue(
      window, kAXPositionAttribute as CFString, &posRef)
    // Short-circuited on purpose: a second read into an app that just timed out
    // costs another full timeout to be told the same thing.
    if posErr == .cannotComplete { return (nil, posErr) }
    let sizeErr = AXUIElementCopyAttributeValue(
      window, kAXSizeAttribute as CFString, &sizeRef)
    guard posErr == .success, sizeErr == .success, let posRef, let sizeRef else {
      return (nil, posErr == .success ? sizeErr : posErr)
    }
    var pos = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
          AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
      return (nil, .success)
    }
    return (CGRect(origin: pos, size: size), .success)
  }

  // MARK: - Active screen (top-left conversion, done once, here)

  /// The display under the cursor. Every accessor below shares it, so the
  /// overlay panel and the placement geometry can never disagree about *which*
  /// screen is active.
  static func activeScreen() -> NSScreen {
    let mouse = NSEvent.mouseLocation // bottom-left global
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main ?? NSScreen.screens.first!
  }

  /// AppKit's bottom-left rect → top-left global points. **The** conversion:
  /// every rect that crosses into Dart goes through here and nowhere else.
  static func toTopLeft(_ frame: NSRect) -> CGRect {
    return toTopLeft(frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
  }

  /// The conversion itself, with the origin height passed in. Split out only so
  /// it can be exercised headlessly — mixing the two coordinate spaces is the
  /// most likely correctness bug in a window manager, and a test needs to pose
  /// display arrangements the machine running it may not have.
  static func toTopLeft(_ frame: NSRect, primaryHeight: CGFloat) -> CGRect {
    return CGRect(x: frame.origin.x,
                  y: primaryHeight - frame.origin.y - frame.height,
                  width: frame.width, height: frame.height)
  }

  /// The active display's visible frame in AppKit's BOTTOM-LEFT space, for
  /// positioning our own NSWindow/NSPanel. Window *placement* math stays in
  /// top-left space; this exists only because NSWindow.setFrame speaks AppKit
  /// coordinates, and it is co-located with the conversion so the two spaces
  /// still meet in exactly one file.
  static func activeScreenFrameAppKit() -> NSRect {
    return activeScreen().visibleFrame
  }

  /// The same frame in top-left global points — the one coordinate system all
  /// placement geometry uses. Sent to Dart in the summon payload, so the panel
  /// and the geometry are sized from byte-identical numbers.
  static func activeScreenFrameTopLeft() -> CGRect {
    return toTopLeft(activeScreenFrameAppKit())
  }

  private func activeScreenFrame() -> [String: Any] {
    return WindowControl.dict(WindowControl.activeScreenFrameTopLeft())
  }

  /// Every display's visible frame, top-left origin — same space as
  /// `activeScreenFrame`. Dart decides *which* one to use (see
  /// `screenContaining`); this only enumerates, so the choosing logic stays
  /// pure, testable, and reusable by the future Windows backend.
  private func screenFrames() -> [[String: Any]] {
    return NSScreen.screens.map {
      WindowControl.dict(WindowControl.toTopLeft($0.visibleFrame))
    }
  }

  private static func dict(_ rect: CGRect) -> [String: Any] {
    return ["x": rect.origin.x, "y": rect.origin.y,
            "w": rect.width, "h": rect.height]
  }

  // MARK: - Apply (with AXEnhancedUserInterface handling)

  /// What a placement attempt actually did. Three-way rather than Bool because
  /// the two failures need different handling at the overlay's call sites:
  /// `.fullscreen` has already beeped here — that beep is the direct-shortcut
  /// path's only feedback, so it cannot move to the callers — and the
  /// successful AXFullScreen read that produced it proves the Accessibility
  /// grant is intact. Folding it into `.failed` cost a second beep and a
  /// pointless permission check on every fullscreen grid commit. Dart still
  /// receives a Bool; the distinction exists for native callers.
  enum PlacementOutcome {
    case placed
    /// Refused because the window is native-fullscreen. A beep was emitted.
    case fullscreen
    /// Did not land — nothing captured, the app not answering, or the frame
    /// did not take. Not yet signalled to anyone.
    case failed
  }

  func applyFrame(_ rect: CGRect) -> PlacementOutcome {
    guard let window = capturedWindow, let appEl = capturedApp else { return .failed }

    // Native-fullscreen windows can't be repositioned via AX (spec §5). Beep —
    // the macOS convention for "can't do that" — instead of appearing broken.
    //
    // This read is also the *first* message of the placement, which makes it
    // the cheapest place to notice the app is not answering: bailing here costs
    // one timeout, where falling through to the two messages below cost three.
    let fullscreen = boolAttribute(window, "AXFullScreen" as CFString)
    if fullscreen.error == .cannotComplete { return .failed }
    if fullscreen.value {
      NSSound.beep()
      return .fullscreen
    }

    // Identified by pid *and* kernel start time: a debt keyed on the pid alone
    // could be inherited by whatever next holds the number. Nil means the kernel
    // will not describe the process, and the plan below then refuses to touch
    // the flag at all — we must not change something we cannot record owing.
    let incarnation = AppIncarnation(capturedApplication)
    let euiKey = "AXEnhancedUserInterface" as CFString

    // Take over any restore still owed to this app, and leave the retry that
    // owed it holding a stale generation. Without this, a retry firing during
    // the writes below would switch AXEnhancedUserInterface back **on**
    // mid-placement — precisely the state those writes exist to avoid.
    let owedRestore = incarnation.map { WindowControl.euiLedger.claim($0) } ?? false

    /// Hand the debt to a retry. Only ever called with the flag actually off.
    func deferRestore() {
      if let incarnation { WindowControl.deferEUIRestore(incarnation, appEl) }
    }

    // The decision itself is a pure function — `euiPlan` — because it is the
    // part most likely to be wrong and the only part a test can execute. What it
    // keeps apart is what conflating them got wrong twice: a debt says what the
    // app *wants*, and only a live read says what is *true*.
    let eui = boolAttribute(appEl, euiKey)
    var mustRestore = false
    switch euiPlan(owed: owedRestore,
                   read: AXOutcome(eui.error),
                   isOn: eui.value,
                   identified: incarnation != nil) {
    case .abandon(let reDefer):
      if reDefer { deferRestore() }
      return .failed
    case .placeOnly:
      break
    case .restoreAfter:
      mustRestore = true
    case .disableThenRestore:
      switch AXOutcome(setBool(appEl, euiKey, false)) {
      case .ok:
        mustRestore = true
      case .gone:
        // It stopped existing between the read and the write. Nothing to work
        // around and nothing to put back.
        break
      case .unavailable:
        // We could not turn it off, so the frame writes below would run against
        // it — which is the whole thing they exist to avoid. Placing a window
        // wrongly is worse than not placing it. Nothing changed, nothing owed.
        return .failed
      }
    }

    /// Give up on this placement, leaving the target as we found it.
    ///
    /// The foreground never waits on the restore — a write into an app that is
    /// not answering spends the full timeout and fails, so it would cost a
    /// second and change nothing. But it is not ours to abandon either: an app
    /// that stops answering usually starts again, and Chromium reads a
    /// *sustained* false as "no assistive technology is watching" and shuts its
    /// accessibility support down. So the debt is handed to a retry.
    func abandon() -> PlacementOutcome {
      if mustRestore { deferRestore() }
      return .failed
    }

    // Stop at the first sign the app has stopped answering. Everything below —
    // a verify read, a second four-set pass, a restore, a final read — would each
    // pay the messaging timeout over again for a window that is not going to
    // move. Bounding one message is worthless while five queue behind it: that
    // is the whole reason `messagingTimeout` alone was only half the fix.
    if setFrameOnce(window, rect) == .cannotComplete { return abandon() }

    // Verify, and re-assert once if the frame did not take.
    //
    // Moving a window ONTO a display with a different backing scale makes macOS
    // run its own size adjustment after the position lands, which clobbers the
    // size set microseconds earlier. Measured on a genuine 1x/2x pair: a window
    // at [-640,1465,1280,710] on the 1x display, sent to [640,205,640,525] on
    // the 2x display, arrived at [640,205,640,710] — origin and width exact, the
    // height still the *source* height. Committing a second time landed it
    // exactly, which is what this pass automates.
    //
    // Bounded at one retry on purpose: an app at its minimum size can never
    // match, so looping until it does would spin on every Finder commit.
    // A frame we could not read is not a frame that matched — re-assert rather
    // than assume the first pass took.
    let afterFirst = frameAndError(window)
    if afterFirst.error == .cannotComplete { return abandon() }
    let tookFirstPass =
      afterFirst.frame.map { WindowControl.frameMatches($0, rect) } ?? false
    if !tookFirstPass, setFrameOnce(window, rect) == .cannotComplete {
      return abandon()
    }

    if mustRestore {
      switch restoreVerdict(AXOutcome(setBool(appEl, euiKey, true))) {
      case .settled: mustRestore = false
      case .retry: return abandon()
      }
    }

    // Report what actually landed. Apps with a minimum size (or that otherwise
    // refuse a frame) are accepted rather than fought — we only claim success
    // when the window moved somewhere near where we asked.
    guard let landed = frameAndError(window).frame else { return .failed }
    return WindowControl.originMatches(landed, rect) ? .placed : .failed
  }

  /// One size → pos → size → pos pass.
  ///
  /// The *leading* size set is what makes a shrink land. Moving first while the
  /// window is still large can push it past the target display's bottom edge —
  /// a 1920×1050 window sent to y=380 would reach y=1430 — and macOS clamps
  /// that, leaving a height nobody asked for. Measured against Finder,
  /// reproducibly and independently of Orthant: `pos → size` for
  /// [0,380,1280,700] yields 754, `size → pos → size` yields exactly 700.
  /// Shrinking before moving means there is nothing to clamp.
  ///
  /// The trailing position is also not redundant: some apps (Chrome, Electron)
  /// only land correctly when position is set after size.
  ///
  /// Returns `.cannotComplete` the moment the target stops answering, so the
  /// caller can abandon the rest instead of paying four messaging timeouts to
  /// discover the same thing four times. Any *other* error is ignored, as
  /// before: an app refusing a size below its minimum is an ordinary outcome
  /// this pass is designed to absorb, not a reason to stop.
  @discardableResult
  private func setFrameOnce(_ window: AXUIElement, _ rect: CGRect) -> AXError {
    var pos = rect.origin
    var size = rect.size

    func setSize() -> AXError {
      guard let v = AXValueCreate(.cgSize, &size) else { return .success }
      return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
    }
    func setPos() -> AXError {
      guard let v = AXValueCreate(.cgPoint, &pos) else { return .success }
      return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
    }

    for step in [setSize, setPos, setSize, setPos] {
      if step() == .cannotComplete { return .cannotComplete }
    }
    return .success
  }

  /// How far a landed frame may sit from the requested one and still count.
  /// Two points absorbs the rounding a 2x backing scale introduces without
  /// hiding a placement that genuinely went somewhere else.
  static let placementTolerance: CGFloat = 2

  /// Whether the window arrived where we asked. Origin only: an app at its
  /// minimum size legitimately never matches on size, and refusing to call that
  /// a success would report a working snap as a failure.
  static func originMatches(_ landed: CGRect, _ want: CGRect) -> Bool {
    abs(landed.origin.x - want.origin.x) <= placementTolerance &&
      abs(landed.origin.y - want.origin.y) <= placementTolerance
  }

  /// Whether a landed frame matches what was asked, origin *and* size. Only
  /// used to decide whether to re-assert — success is still judged by
  /// `originMatches`, for the reason above.
  static func frameMatches(_ landed: CGRect, _ want: CGRect) -> Bool {
    originMatches(landed, want) &&
      abs(landed.width - want.width) <= placementTolerance &&
      abs(landed.height - want.height) <= placementTolerance
  }

  /// True if the window is in native macOS fullscreen (AXFullScreen == true).
  /// Read a boolean attribute, **keeping the error**.
  ///
  /// A hung app answers every read with `kAXErrorCannotComplete`, one full
  /// messaging timeout at a time, and that error is the only signal there is
  /// that it has stopped talking. A read that collapses it into `false` costs a
  /// second and tells the caller nothing, so the next read pays it again.
  private func boolAttribute(_ element: AXUIElement, _ key: CFString)
    -> (value: Bool, error: AXError)
  {
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, key, &ref)
    return (err == .success && (ref as? Bool == true), err)
  }

  @discardableResult
  private func setBool(_ element: AXUIElement, _ key: CFString, _ value: Bool) -> AXError {
    AXUIElementSetAttributeValue(element, key, value ? kCFBooleanTrue : kCFBooleanFalse)
  }

  /// Where the *waiting* happens. See `deferEUIRestore` for why the write does
  /// not.
  private static let euiRestoreQueue =
    DispatchQueue(label: "app.orthant.eui-restore", qos: .utility)

  /// Delays between attempts to hand `AXEnhancedUserInterface` back, in seconds.
  ///
  /// A ramp rather than a single retry: the apps this flag exists for are the
  /// heavy ones, and "stopped answering" spans a stalled frame and a multi-second
  /// garbage collection. Bounded, because an app that is still silent after
  /// twenty seconds is hung or gone, and retrying forever is a worse bargain
  /// than a flag left off.
  private static let euiRestoreDelays: [Double] = [1, 5, 15]

  /// Which apps we owe an `AXEnhancedUserInterface` restore to, and who owns it.
  ///
  /// **Main-thread only**, and that is what makes it safe without a lock:
  /// `applyFrame` runs on the main thread (the Flutter channel and the overlay's
  /// commit both call it there), and the retry below hops back to main before it
  /// reads this or writes the flag.
  private static var euiLedger = EUIRestoreLedger()

  /// Record that [app] is still owed a restore, and start trying.
  ///
  /// Orthant turns this flag off around a placement because Chromium and
  /// Electron mis-set frames while it is on (spec §5), and the spec's rule is
  /// *then restore*. Leaving it off is not merely untidy: Chromium treats a
  /// sustained false as "no assistive technology is watching" and disables its
  /// accessibility support after a grace period. Handing back a browser with
  /// accessibility silently switched off, because a window snap timed out, is a
  /// far worse outcome than the snap failing.
  private static func deferEUIRestore(_ app: AppIncarnation, _ appEl: AXUIElement) {
    retryEUIRestore(appEl, app: app, generation: euiLedger.owe(app))
  }

  /// Wait off the main thread; decide and write on it.
  ///
  /// The split is the whole point. Probing a still-hung app blocks for the
  /// messaging timeout, which is why the wait cannot be on the main thread — and
  /// the write cannot be *off* it, because placements run on main and a `true`
  /// landing in the middle of one restores exactly the state those frame writes
  /// exist to avoid. So the background queue only establishes that the app is
  /// answering again, and the write follows on main, where it is both fast and
  /// unable to interleave.
  private static func retryEUIRestore(
    _ appEl: AXUIElement, app: AppIncarnation, generation: Int, attempt: Int = 0
  ) {
    let euiKey = "AXEnhancedUserInterface" as CFString
    guard attempt < euiRestoreDelays.count else {
      DispatchQueue.main.async { euiLedger.settle(app, generation: generation) }
      return
    }
    euiRestoreQueue.asyncAfter(deadline: .now() + euiRestoreDelays[attempt]) {
      var ref: CFTypeRef?
      // Any answer at all means the app is talking again — including one that
      // says the attribute is gone, which a quit app gives as
      // `.invalidUIElement` and which settles below rather than retrying.
      let answering =
        AXUIElementCopyAttributeValue(appEl, euiKey, &ref) != .cannotComplete
      guard answering else {
        retryEUIRestore(appEl, app: app, generation: generation,
                        attempt: attempt + 1)
        return
      }
      DispatchQueue.main.async {
        // Someone else took this on — a placement that started while we waited.
        // It read the flag as ours and is responsible for it now.
        guard euiLedger.owns(app, generation: generation) else { return }
        let err = AXUIElementSetAttributeValue(appEl, euiKey, kCFBooleanTrue)
        // The probe said the app was answering; it can have stopped again in
        // the moment since, in which case that write just cost the main thread
        // a full timeout **and did not land**. Settling on it would leave the
        // flag off for good — the exact failure this path exists to prevent —
        // and `kAXErrorFailure` says "did not work" without saying why, so it
        // must not count as success either. Same policy as the foreground.
        switch restoreVerdict(AXOutcome(err)) {
        case .retry:
          retryEUIRestore(appEl, app: app, generation: generation,
                          attempt: attempt + 1)
        case .settled:
          euiLedger.settle(app, generation: generation)
        }
      }
    }
  }
}
