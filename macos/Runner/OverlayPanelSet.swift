import Cocoa

/// Owns the overlay's panels and the session that binds one summon together.
///
/// One panel is resident per display, always (`reconcilePanels()`). Task 7
/// only ever *shows* the one under the cursor (`screensToCover()`); Task 8
/// widens that to every display — nothing else here changes shape.
final class OverlayPanelSet {
  private final class Session {
    let id: Int
    var activePanel: OverlayPanel?
    var pressLockedPanel: OverlayPanel?
    init(id: Int) { self.id = id }
  }

  private let control: WindowControl
  private let hotkeys: HotkeyManager
  private var panels: [CGDirectDisplayID: OverlayPanel] = [:]

  /// Monotonic, incremented on every summon. Three fields rather than one flag
  /// because "is this fade still wanted?" and "is this session current?" are
  /// different questions — the session is invalidated the instant dismissal
  /// begins, so a fade completion asking the latter would always answer no.
  private var latestGeneration = 0
  private var session: Session?
  private var fadingGeneration: Int?

  private var globalMonitor: Any?
  private var localMonitor: Any?

  init(control: WindowControl, hotkeys: HotkeyManager) {
    self.control = control
    self.hotkeys = hotkeys
    reconcilePanels()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  // MARK: - Panels (resident; never rebuilt per summon)

  private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
  }

  /// Create panels for added displays, release them for removed ones. Panels
  /// and their engines stay resident *whether or not this summon shows them*
  /// — reconciling against `screensToCover()` instead of every screen would
  /// tear down and cold-start an engine each time the set of covered displays
  /// changed (e.g. the cursor moving to a display with no resident panel yet),
  /// throwing away M4's 44.5 ms result and risking a summon landing on an
  /// engine whose channel handler hasn't registered yet — a blank grid with
  /// keys already grabbed.
  private func reconcilePanels() {
    var seen = Set<CGDirectDisplayID>()
    for screen in NSScreen.screens {
      let id = OverlayPanelSet.displayID(of: screen)
      seen.insert(id)
      if panels[id] == nil {
        let panel = OverlayPanel()
        panel.owner = self
        // Size before first raster so it inherits this display's scale.
        panel.setFrame(screen.visibleFrame, display: false)
        panels[id] = panel
      }
    }
    for (id, panel) in panels where !seen.contains(id) {
      // teardown(), not close(): closing the window and dropping this
      // dictionary's strong reference still leaves the FlutterEngine running,
      // because it owns threads and VM resources that no amount of releasing
      // Swift objects reclaims. Measured at ~5.7 MB leaked per detach/re-attach
      // cycle, growing linearly and never returned, until teardown() started
      // calling engine.shutDown().
      panel.teardown()
      panels.removeValue(forKey: id)
    }
  }

  /// The grid to render, pushed from Dart whenever the settings change and
  /// included in every summon payload. Defaults match `kDefaultGrid*` so a
  /// summon before Dart has ever pushed still draws a sensible grid.
  private var gridCols = 6
  private var gridRows = 6
  private var gap: Double = 0

  /// Whether the overlay should offer its ⌘S hint. Dart decides (it is
  /// `regions.isEmpty`); this only carries the answer to the panels.
  private var saveHint = false

  /// Set from the channel. Plain numbers, never a preferences read — Swift must
  /// not become a second reader of a Dart-owned schema.
  func setGrid(cols: Int, rows: Int, gap: Double, saveHint: Bool) {
    self.gridCols = cols
    self.gridRows = rows
    self.gap = gap
    self.saveHint = saveHint
  }

  /// Which resident panels are actually shown *this* summon — a subset of
  /// `panels`, which `reconcilePanels()` keeps resident for every display
  /// regardless of this. Task 7: the cursor's display only. Task 8 returns
  /// `NSScreen.screens` too, at which point this matches `panels` exactly.
  /// Every display gets a panel; the one under the cursor is active and the
  /// rest are dimmed indicators. Nothing relocates, so nothing flickers, and
  /// each panel inherits its own display's backing scale exactly once.
  private func screensToCover() -> [NSScreen] { NSScreen.screens }

  @objc private func screensChanged() {
    dismiss()
    reconcilePanels()
  }

  // MARK: - Summon

  func show() {
    // Re-entrancy guard: a second show() while a session is already live would
    // re-run everything below, including installMonitors(), which overwrites
    // globalMonitor/localMonitor without removing the previous ones first —
    // leaking two monitors per extra call.
    guard session == nil else { return }

    // Nothing to show (e.g. every display asleep): grabbing Esc and Return
    // system-wide with no panel on screen would strand the user with only Esc
    // as a way out. Bail exactly like the capture-failure path below.
    guard !NSScreen.screens.isEmpty else {
      NSSound.beep()
      return
    }

    // Capture first, and abort entirely if it fails: showing a grid that would
    // move a *previously* captured window is worse than showing nothing.
    //
    // Failing here is reported the same way a failed *commit* is. Capture is
    // the first thing a revoked Accessibility grant breaks, and until this was
    // wired the grid answered a revocation with a beep and nothing else — while
    // the direct shortcuts, which route every failure through Dart, recovered
    // and re-showed onboarding. Two paths, one grant, opposite behaviour.
    //
    // Deliberately not a structured reason code: this side does not know one.
    // captureFrontmostWindow returns false for a lost grant, an empty Desktop
    // and Orthant itself being frontmost alike, and only the OS can say which.
    // Dart asks it (`_recoverIfPermissionLost`), which is the same question the
    // shortcut path asks, in the same place, from one answer.
    guard control.captureFrontmostWindow() else {
      NSSound.beep()
      onPlacementFailed?()
      return
    }

    // Grab the modal keys BEFORE anything is on screen, so a failure can abort
    // cleanly. This used to run at the very end of show(), where a failed Esc
    // grab had no way to refuse without tearing a live session back down.
    // Suppressing region hotkeys a few milliseconds early is harmless — a
    // region command firing mid-summon is precisely what suppression is for.
    guard hotkeys.grabOverlayKeys() else {
      hotkeys.releaseOverlayKeys()
      NSSound.beep()
      return
    }

    latestGeneration += 1
    let gen = latestGeneration
    let s = Session(id: gen)
    session = s
    reconcilePanels()

    let reduceMotion = Accessibility.reduceMotionEnabled()
    let now = Date().timeIntervalSince1970 * 1000.0
    let pressed = hotkeys.lastPressAtMs
    let triggerMs = (now - pressed) < 1000 ? pressed : now
    // Read from the capture itself, not a fresh NSWorkspace query: the
    // frontmost app can change between the two calls, and this chip's whole
    // job is naming the window that was actually captured.
    let app = control.capturedApplication
    let icon = AppIconCache.pngData(for: app)

    // Computed once: NSEvent.mouseLocation is a live read, and the loop below
    // spans milliseconds (setFrame/orderFront/invokeMethod per panel). Reading
    // it inside the loop risked the cursor crossing a display bezel mid-summon,
    // sending "active: true" to two panels while session.activePanel held only
    // the last match — the other's beginDrag/commit would then be silently
    // rejected on release, with the overlay stuck on screen.
    let activeID = OverlayPanelSet.displayID(of: WindowControl.activeScreen())
    for screen in screensToCover() {
      let id = OverlayPanelSet.displayID(of: screen)
      guard let panel = panels[id] else { continue }
      let topLeft = WindowControl.toTopLeft(screen.visibleFrame)
      let isActive = (id == activeID)
      if isActive { s.activePanel = panel }
      panel.show(onBottomLeftFrame: screen.visibleFrame, reduceMotion: reduceMotion)
      var payload: [String: Any] = [
        "sessionId": gen,
        "triggerMs": triggerMs,
        "x": topLeft.origin.x, "y": topLeft.origin.y,
        "w": topLeft.width, "h": topLeft.height,
        "appName": app?.localizedName ?? "",
        "active": isActive,
        // The grid the user configured. Pushed per summon rather than read by
        // the overlay: it runs on its own Flutter engine, which cannot see the
        // main isolate's preferences — and sending it every time means there is
        // nowhere for a stale grid to be cached.
        "cols": gridCols,
        "rows": gridRows,
        "gap": gap,
        "saveHint": saveHint,
      ]
      // No "scale" or "reduceMotion" here: Dart reads neither. The first died
      // with M4's DPI probe, the second with the Flutter-side scale entrance
      // that was never built. Dead fields in a hand-written protocol are how it
      // drifts — re-add them alongside whatever reads them.
      // Only set when present: an Optional wrapped in Any does not survive the
      // standard codec, and a missing icon is a supported state (name only).
      if let icon = icon { payload["appIcon"] = icon }
      panel.summon(payload)
    }

    installMonitors()
  }

  // MARK: - Dart -> native

  func beginDrag(sessionId: Int, from panel: OverlayPanel) {
    guard let s = session, s.id == sessionId, panel === s.activePanel else { return }
    s.pressLockedPanel = panel
  }

  /// A drag interrupted rather than released (the pointer left the app).
  /// Without this, `pressLockedPanel` stays set for the rest of the session
  /// and `becameActive` is suppressed permanently — invisible with one panel,
  /// a stuck lock the moment a second one exists.
  func endDrag(sessionId: Int, from panel: OverlayPanel) {
    guard let s = session, s.id == sessionId, panel === s.pressLockedPanel else { return }
    s.pressLockedPanel = nil
    // The pointer may already be sitting on a *different* display: any
    // becameActive it sent while the lock was held was discarded above, and
    // Flutter will not send another onEnter without an exit and re-entry. So
    // recompute from the cursor. Without this, cancelling a drag that had
    // crossed a bezel left the display under the pointer dim and inert until
    // the user moved off it and back.
    let id = OverlayPanelSet.displayID(of: WindowControl.activeScreen())
    if let target = panels[id], target !== s.activePanel {
      becameActive(sessionId: sessionId, panel: target)
    }
  }

  func becameActive(sessionId: Int, panel: OverlayPanel) {
    guard let s = session, s.id == sessionId else { return }
    // Suppressed while a drag is locked, or dragging from A onto B would dim A
    // underneath the user's own gesture.
    guard s.pressLockedPanel == nil else { return }
    s.activePanel = panel
    for (_, p) in panels where p !== panel {
      p.channel.invokeMethod("setActive", arguments: false)
    }
    panel.channel.invokeMethod("setActive", arguments: true)
  }

  /// Invoked when the grid fails to move a window — whether it never captured
  /// one (`show()`) or the commit did not land (`commit()`).
  ///
  /// The grid path is entirely native, so unlike the direct shortcuts it never
  /// reaches Dart's `_runCommand`, where a failed placement is what surfaces a
  /// revoked Accessibility grant. Without this hook a revocation produced a
  /// perfect preview, no movement, and no explanation — or, on the capture
  /// side, a bare beep.
  var onPlacementFailed: (() -> Void)?

  /// A block the user asked to keep, on its way to the main isolate's picker.
  var onSaveRegion: (([String: Any]) -> Void)?

  func commit(sessionId: Int, rect: CGRect, from panel: OverlayPanel) {
    guard let s = session, s.id == sessionId else { return }
    guard panel === (s.pressLockedPanel ?? s.activePanel) else { return }
    let outcome = control.applyFrame(rect)
    dismiss()
    switch outcome {
    case .placed:
      break
    case .fullscreen:
      // applyFrame beeped already, and the read that detected fullscreen
      // proves the permission is intact — beeping again and pinging Dart's
      // permission recovery added nothing but a double beep.
      break
    case .failed:
      // Beep so "nothing happened" is never silent, then let Dart decide
      // whether this was a permission loss.
      NSSound.beep()
      onPlacementFailed?()
    }
  }

  /// ⌘S: place the window *and* hand the block to Dart to become a shortcut.
  ///
  /// Ordering is the same as [commit] and for the same reason — `dismiss()`
  /// invalidates the session that owns the captured window, so the frame must
  /// be applied before it, never after.
  func saveRegion(sessionId: Int, block: [String: Any], rect: CGRect,
                  from panel: OverlayPanel) {
    guard let s = session, s.id == sessionId else { return }
    guard panel === (s.pressLockedPanel ?? s.activePanel) else { return }
    let outcome = control.applyFrame(rect)
    dismiss()
    switch outcome {
    case .placed:
      onSaveRegion?(block)
    case .fullscreen:
      // Beeped in applyFrame; nothing was placed, so nothing is offered for
      // saving — same rule as .failed, minus the second beep and the
      // permission ping that fullscreen provably is not.
      break
    case .failed:
      NSSound.beep()
      onPlacementFailed?()
    }
  }

  // MARK: - Return, relayed

  /// The panel is non-key, so a natively-grabbed Return has no route into
  /// Flutter — and Dart, not native, owns the current selection.
  func commitCurrent() {
    guard let s = session else { return }
    let target = s.pressLockedPanel ?? s.activePanel
    target?.channel.invokeMethod("commitCurrent", arguments: s.id)
  }

  /// ⌘S, relayed for the same reason as Return: Dart owns the selection.
  func saveCurrent() {
    guard let s = session else { return }
    let target = s.pressLockedPanel ?? s.activePanel
    target?.channel.invokeMethod("saveCurrent", arguments: s.id)
  }

  /// An arrow key, relayed for the same reason as Return: Dart owns the
  /// selection, and this panel never sees a key event of its own.
  func moveSelection(direction: String, extend: Bool) {
    guard let s = session else { return }
    let target = s.pressLockedPanel ?? s.activePanel
    target?.channel.invokeMethod("moveSelection", arguments: [
      "sessionId": s.id, "direction": direction, "extend": extend,
    ])
  }

  // MARK: - Dismiss

  /// The Dart-driven "hide" message — validated against the session, like
  /// every other Dart -> native call on this channel. Native-triggered
  /// dismissal (Esc, click-away, screens changing) has no foreign session id
  /// to check and calls the bare dismiss() below directly.
  func dismiss(sessionId: Int) {
    guard let s = session, s.id == sessionId else { return }
    dismiss()
  }

  func dismiss() {
    guard let s = session else { return }
    let gen = s.id
    session = nil                 // invalidate immediately
    fadingGeneration = gen
    hotkeys.releaseOverlayKeys()
    removeMonitors()

    let reduceMotion = Accessibility.reduceMotionEnabled()
    for (_, panel) in panels {
      // panel is captured weak: if screensChanged() -> reconcilePanels() closes
      // and drops this same panel while the fade is still in flight (~100 ms),
      // it must not be resurrected by a "hidden" message after removal. A
      // strong capture would keep it alive for the message and only free it
      // once this closure finished — delaying the deallocation reconcilePanels()
      // just performed.
      panel.fadeOut(reduceMotion: reduceMotion) { [weak self, weak panel] in
        guard let self = self, let panel = panel else { return }
        // Not "is my session current" — it never is by now. The question is
        // whether a *newer summon* has happened.
        guard self.fadingGeneration == self.latestGeneration else { return }
        panel.hideNow()
        panel.channel.invokeMethod("hidden", arguments: gen)
      }
    }
  }

  // MARK: - Monitors (live only while a session exists)

  private func installMonitors() {
    // Global: clicks that go to *other* applications — the menu bar and the
    // Dock, which visibleFrame excludes.
    globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        self?.dismiss()
      }
    // Local: clicks delivered to *Orthant itself* — above all our own status
    // item, which no global monitor can see and which would otherwise open its
    // menu on top of a live overlay.
    localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
        guard let self = self else { return event }
        let isOverlay = self.panels.values.contains { $0 === event.window }
        if !isOverlay { self.dismiss() }
        return event
      }
  }

  private func removeMonitors() {
    if let m = globalMonitor { NSEvent.removeMonitor(m) }
    if let m = localMonitor { NSEvent.removeMonitor(m) }
    globalMonitor = nil
    localMonitor = nil
  }
}

/// App icons are read and PNG-encoded on the pre-show critical path, so they
/// are cached by bundle identifier rather than paid for on every summon.
enum AppIconCache {
  private static var cache: [String: Data] = [:]

  static func pngData(for app: NSRunningApplication?) -> Data? {
    guard let app = app else { return nil }
    let key = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
    if let hit = cache[key] { return hit }
    guard let icon = app.icon else { return nil }
    let size = NSSize(width: 32, height: 32) // 16 pt at 2x
    let resized = NSImage(size: size)
    resized.lockFocus()
    icon.draw(in: NSRect(origin: .zero, size: size))
    resized.unlockFocus()
    guard let tiff = resized.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
      return nil
    }
    cache[key] = png
    return png
  }
}
