import Cocoa
import FlutterMacOS

/// The grid overlay's window: a resident, non-activating, transparent panel.
///
/// It is created once at launch and merely hidden between summons — tearing it
/// down and rebuilding it is what creates lag and first-frame flash (spec §4).
final class OverlayPanel: NSPanel {
  private let engine: FlutterEngine
  private let flutterVC: FlutterViewController
  private(set) var channel: FlutterMethodChannel!

  /// Set by OverlayPanelSet, which owns the session all of these validate against.
  weak var owner: OverlayPanelSet?

  /// Bumped by every show(). fadeOut() captures it at entry and only runs its
  /// completion if it still matches, so a re-summon that lands during a fade
  /// wins over the stale dismissal it interrupted, rather than being hidden
  /// by it a moment later.
  private var showGeneration = 0

  /// The last payload sent to this panel's engine, kept so `ready` can replay
  /// it. Dart installs its handler asynchronously in `overlay_main.dart`, and a
  /// message that arrives before that is dropped by the engine — leaving the
  /// panel on screen with nothing drawn in it. Narrow but real: it needs a
  /// summon inside the engine's own startup, which is exactly what happens
  /// when you relaunch and immediately press the shortcut, or hot-plug a
  /// display and summon onto it.
  private var lastSummon: [String: Any]?

  /// Send a summon, remembering it in case Dart was not listening yet.
  func summon(_ payload: [String: Any]) {
    lastSummon = payload
    channel.invokeMethod("summon", arguments: payload)
  }

  init() {
    // A second engine: the first one's view lives in the focusable config
    // window, and the overlay must never activate the app.
    engine = FlutterEngine(name: "orthant.overlay", project: nil,
                           allowHeadlessExecution: true)
    engine.run(withEntrypoint: "overlayMain")
    flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
      // .nonactivatingPanel is mandatory: clicking a regular NSWindow owned by
      // a background app activates that app, invalidating the captured window.
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false)

    isFloatingPanel = true
    level = .floating
    // .transient is what actually keeps the panel out of Mission Control and
    // Exposé (Rectangle relies on it for its drag-snap footprint); the other
    // flags only govern Spaces and full-screen behaviour.
    collectionBehavior =
      [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .transient]
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    isRestorable = false
    isMovableByWindowBackground = false
    hasShadow = false

    // Flutter's view is opaque by default — a naive transparent window renders
    // solid black. BOTH of these must be cleared (spec §4).
    isOpaque = false
    backgroundColor = .clear
    flutterVC.backgroundColor = .clear

    // Hover events require a tracking area, and the default mode only installs
    // one for the *key* window. This panel refuses key status by design (see
    // canBecomeKey below), and Orthant is a background LSUIElement app that is
    // never the active app either — so anything short of .always means Flutter
    // receives no hover at all. Clicks were unaffected, which is what made this
    // look like "hover is broken" rather than "tracking is off".
    flutterVC.mouseTrackingMode = .always

    // No NSVisualEffectView. As the panel's contentView it would frost the
    // entire screen rather than the compact grid, and M4 measured its cost at
    // 2.6-12.2 % CPU for as long as the overlay is visible — which M5 pays for
    // the length of every drag. The grid draws its own translucent fill, which
    // is also what Divvy does.
    contentView = flutterVC.view

    channel = FlutterMethodChannel(
      name: "app.orthant/overlay",
      binaryMessenger: engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any]
      let sid = args?["sessionId"] as? Int ?? (call.arguments as? Int ?? -1)
      switch call.method {
      case "ready":
        // Dart's handler is live. Replay the summon if one was sent before it
        // was installed: the engine drops a message with no handler, and the
        // result is this panel on screen with nothing drawn in it — an empty
        // rectangle over the user's desktop. A duplicate summon is idempotent
        // (same sessionId, same payload), so replaying unconditionally while
        // visible is safe.
        if self.isVisible, let payload = self.lastSummon {
          self.channel.invokeMethod("summon", arguments: payload)
        }
      case "firstFrame":
        // Instrumentation from M4's latency gate. The gate is closed, so this
        // stays out of Release rather than logging on every summon for the rest
        // of the app's life — but the wiring stays, because re-measuring after
        // a renderer or engine change is exactly when it is wanted again.
        #if DEBUG
        if let ms = call.arguments as? Double {
          NSLog("[orthant] summon → first frame: %.1f ms", ms)
        }
        #endif
      case "beginDrag":
        self.owner?.beginDrag(sessionId: sid, from: self)
      case "endDrag":
        self.owner?.endDrag(sessionId: sid, from: self)
      case "becameActive":
        self.owner?.becameActive(sessionId: sid, panel: self)
      case "commit":
        if let a = args,
           let x = a["x"] as? Double, let y = a["y"] as? Double,
           let w = a["w"] as? Double, let h = a["h"] as? Double {
          self.owner?.commit(sessionId: sid,
                             rect: CGRect(x: x, y: y, width: w, height: h),
                             from: self)
        }
      case "saveRegion":
        if let a = args,
           let cols = a["cols"] as? Int, let rows = a["rows"] as? Int,
           let c0 = a["c0"] as? Int, let c1 = a["c1"] as? Int,
           let r0 = a["r0"] as? Int, let r1 = a["r1"] as? Int,
           let x = a["x"] as? Double, let y = a["y"] as? Double,
           let w = a["w"] as? Double, let h = a["h"] as? Double {
          self.owner?.saveRegion(
            sessionId: sid,
            block: ["cols": cols, "rows": rows,
                    "c0": c0, "c1": c1, "r0": r0, "r1": r1],
            rect: CGRect(x: x, y: y, width: w, height: h),
            from: self)
        }
      case "hide":
        self.owner?.dismiss(sessionId: sid)
      default:
        break
      }
      result(nil)
    }

    // Deliberately NOT RegisterGeneratedPlugins(registry: flutterVC): that would
    // stand up a *second* TrayManagerPlugin and SharedPreferencesPlugin on this
    // engine. overlayMain uses neither, and this engine is resident — duplicate
    // plugin instances are pure idle cost on the one milestone that measures it.
  }

  /// Size to the target display *before* showing, so the panel inherits that
  /// display's backingScaleFactor. Never move a visible window between screens.
  func show(onBottomLeftFrame frame: NSRect, reduceMotion: Bool) {
    showGeneration += 1 // this show must outrank any fade already in flight
    if self.frame != frame { setFrame(frame, display: true) } // skip no-op resizes
    alphaValue = reduceMotion ? 1 : 0
    orderFront(nil) // NEVER makeKeyAndOrderFront: — that activates Orthant.
    guard !reduceMotion else { return }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.10
      animator().alphaValue = 1
    }
  }

  /// Fade out, then hand back to the caller to decide whether to hide.
  ///
  /// The window fade is native on purpose. A `dismiss -> Dart animates ->
  /// dismissFinished` round trip would make native teardown depend on a Dart
  /// reply — a wedged isolate would strand the overlay on screen — and it
  /// multiplies by panel count.
  func fadeOut(reduceMotion: Bool, completion: @escaping () -> Void) {
    // One guard covers both branches below: if show() bumps showGeneration
    // before this runs, a re-summon arrived during the fade and must win —
    // skip completion (callers use it to hideNow()) rather than hide the
    // panel a fresh show() just redisplayed.
    let generation = showGeneration
    let guardedCompletion: () -> Void = { [weak self] in
      guard let self, self.showGeneration == generation else { return }
      completion()
    }

    // Even with no animation, the hide must not happen synchronously inside
    // the dismissing event: hiding synchronously can wedge Flutter's
    // focus/shortcut state so the *next* summon's keys don't fire (spec §5).
    // This is what M4's hideAsync() was protecting against.
    guard !reduceMotion else {
      DispatchQueue.main.async(execute: guardedCompletion)
      return
    }
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.10
      animator().alphaValue = 0
    }, completionHandler: guardedCompletion)
  }

  /// Take the panel off screen. Callers must have validated the generation.
  func hideNow() {
    orderOut(nil)
    alphaValue = 1 // reset, so a later show is not invisible
  }

  /// Permanently dispose of this panel and the engine behind it.
  ///
  /// Closing the window and dropping every Swift reference is NOT enough: a
  /// FlutterEngine owns threads and VM resources that outlive the object graph
  /// until it is shut down explicitly. Measured before this existed, a
  /// detach/re-attach cycle leaked ~5.7 MB *per cycle*, linearly and forever —
  /// a docked laptop accumulates it daily.
  ///
  /// Order matters: unhook the channel handler and detach the view controller
  /// before shutting the engine down, so nothing is still routing messages into
  /// an engine that is tearing itself down.
  func teardown() {
    channel.setMethodCallHandler(nil)
    owner = nil
    hideNow()
    close()
    contentView = nil
    engine.viewController = nil
    engine.shutDownEngine()
  }

  // Esc and Return are global Carbon grabs, so the panel needs no key status
  // at all. Refusing it closes M4's open risk outright: a click in the overlay
  // can no longer resign the target window's key status and dim its title bar.
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
