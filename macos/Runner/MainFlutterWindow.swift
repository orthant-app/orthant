import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var windowControl = WindowControl()
  private var hotkeys: HotkeyManager?
  private var channel: FlutterMethodChannel?

  /// The grid overlay's panels and session. Built at launch and kept resident —
  /// a warm engine and a pre-built window are what make the summon perceptually
  /// instant (spec §4). It lives here rather than on AppDelegate because
  /// FlutterAppDelegate's own applicationDidFinishLaunching is not exposed in
  /// its header: overriding it from Swift would either not compile or silently
  /// shadow the engine's lifecycle-delegate forwarding. Nib loading also runs
  /// earlier.
  private(set) var overlays: OverlayPanelSet?

  override func awakeFromNib() {
    // Sized **before** the Flutter view is attached.
    //
    // Flutter's macOS view blocks the platform thread on a resize until the
    // engine commits a frame at the new size, and the first such resize waits
    // on the engine's whole start-up rasterisation — measured at **1.19 s**.
    // Doing it before there is a Flutter view to synchronise with means the
    // resize is a plain AppKit call with nothing to wait for.
    //
    // It is cheap precisely because nothing is attached yet.
    //
    // What this does **not** do is decide the frame the user ends up seeing.
    // Measured on 2026-08-08: attaching the view below discards this outright —
    // 560 x 620 becomes 1 x 32, origin and all. The frame that survives comes
    // from `setFrameAutosaveName` if there is a saved one, and from
    // `showConfigWindow`'s placement if there is not. Whether this sizing still
    // buys anything now that the restore follows it has not been re-measured, so
    // it is left alone rather than removed on the strength of one probe.
    self.setFrame(
      NSRect(origin: self.frame.origin,
             size: NSSize(width: AppShell.configWidth,
                          height: AppShell.configOpeningHeight)),
      display: false)

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let channel = FlutterMethodChannel(
      name: "app.orthant/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    let hotkeys = HotkeyManager(channel: channel)
    self.hotkeys = hotkeys
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "showConfigWindow":
        AppShell.showConfigWindow(self)
        result(nil)
      // The pane has painted, so the window can stop being transparent.
      case "configFirstFrame":
        AppShell.revealConfigWindow(self)
        result(nil)
      case "hideConfigWindow":
        AppShell.hideConfigWindow(self)
        result(nil)
      case "checkForUpdates":
        Updater.checkForUpdates()
        result(nil)
      case "openAccessibilitySettings":
        AppShell.openAccessibilitySettings()
        result(nil)
      // Swap the entire hotkey set, and answer with the ids macOS **refused** —
      // it says so once, at registration, and a rejected chord is otherwise
      // indistinguishable from a live one.
      //
      // One call rather than an unregister plus a register per binding. Dart
      // had to await each of those separately, so a second caller could begin
      // its own replacement in the gaps and the two would interleave, leaving
      // shortcuts registered that the settings list already showed as unset.
      // Everything below runs inside this one handler invocation on the main
      // thread, so there are no gaps to interleave in.
      case "replaceHotkeys":
        result(self.hotkeys?.replaceAll(call.arguments) ?? [])
      case "unregisterAllHotkeys":
        self.hotkeys?.unregisterAll()
        result(nil)
      case "setOverlayGrid":
        if let a = call.arguments as? [String: Any],
           let cols = a["cols"] as? Int,
           let rows = a["rows"] as? Int,
           let gap = a["gap"] as? Double {
          // saveHint defaults rather than being required: an older Dart side
          // that does not send it still gets a working grid.
          self.overlays?.setGrid(cols: cols, rows: rows, gap: gap,
                                 saveHint: a["saveHint"] as? Bool ?? false)
        }
        result(nil)
      case "showOverlay":
        self.overlays?.show()
        result(nil)
      case "hideOverlay":
        self.overlays?.dismiss()
        result(nil)
      // Launch-at-login. Every one of these answers from SMAppService rather
      // than from anything we store: the user can change it in System Settings
      // without telling us.
      // Both answer from a background queue — see LoginItem.queue. These are the
      // only handlers here that do not reply inline, because they are the only
      // ones that wait on another process we did not write.
      case "loginItemStatus":
        LoginItem.statusAsync(result)
      case "setLoginItem":
        LoginItem.setAsync(call.arguments as? Bool ?? false, result)
      case "openLoginItemsSettings":
        LoginItem.openLoginItemsSettings()
        result(nil)
      // Read from the running bundle, never from a Dart constant or a build-time
      // define: those drift from what actually shipped, and a version display that
      // can be wrong about itself is worse than none. `Bundle.main` is the only
      // source that cannot disagree with the binary being asked.
      //
      // A pre-release label is deliberately absent. CFBundleShortVersionString is
      // three integers by Apple's rule, so "1.0.0-beta.2" lives only in the tag,
      // the DMG name and the release title. The build number is what actually
      // distinguishes one beta from the next, which is why both halves are
      // returned rather than the marketing string alone.
      case "appVersion":
        let info = Bundle.main.infoDictionary
        result([
          "shortVersion": info?["CFBundleShortVersionString"] as? String ?? "",
          "buildNumber": info?["CFBundleVersion"] as? String ?? "",
          // Written by tool/release.sh from the tag it is building, so it is the
          // only value here that can carry a pre-release label. Absent from
          // every locally-built bundle, which is why Dart treats "" as "fall
          // back to short version and build number" rather than as an error.
          "releaseName": info?["ORTHANTReleaseName"] as? String ?? "",
        ])
      default:
        self.windowControl.handle(call, result: result)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Built last, so the config window's engine is fully wired first.
    overlays = OverlayPanelSet(control: windowControl, hotkeys: hotkeys)
    hotkeys.onOverlayDismiss = { [weak self] in self?.overlays?.dismiss() }
    hotkeys.onOverlayCommit  = { [weak self] in self?.overlays?.commitCurrent() }
    hotkeys.onOverlaySave    = { [weak self] in self?.overlays?.saveCurrent() }
    hotkeys.onOverlayArrow   = { [weak self] direction, extend in
      self?.overlays?.moveSelection(direction: direction, extend: extend)
    }
    // Route a failed grid placement to Dart, which owns permission recovery —
    // the same path a failed direct shortcut takes.
    overlays?.onPlacementFailed = {
      channel.invokeMethod("onPlacementFailed", arguments: nil)
    }
    // ⌘S on the grid: the window has already been placed, and the block now
    // needs a name and a combo — neither of which a non-key panel can collect.
    overlays?.onSaveRegion = { block in
      channel.invokeMethod("onSaveRegion", arguments: block)
    }

    super.awakeFromNib()

    // Give the (normally hidden) window a native title bar so the onboarding /
    // settings surface looks right when it is shown.
    self.title = "Orthant"
    // Not .miniaturizable, deliberately. Minimizing does not go through
    // windowShouldClose, so the yellow button and ⌘M would strand the app in
    // .regular — Dock icon and all — with any in-progress shortcut recording
    // still suspending every hotkey, until the user restored the window and
    // cancelled. Routing windowDidMiniaturize through the same teardown would
    // also mean "minimizing" silently hid the window instead, which is worse
    // than not offering it. A menu-bar agent has nowhere to minimize *to*.
    // `.resizable` is on because this window no longer sizes itself to its
    // content.
    self.styleMask = [.titled, .closable, .resizable]
    // Content sizes, and they share a width — that pair is what makes AppKit
    // offer a vertical drag only.
    self.contentMinSize = AppShell.configMinContentSize
    self.contentMaxSize = AppShell.configMaxContentSize
    // Set **after** the style mask: AppKit applies any saved frame when the
    // autosave name is assigned, and a frame restored into a non-resizable
    // window is discarded.
    //
    // And **after the Flutter view is attached — do not move it earlier.** It
    // looks like it belongs up with the other window configuration, and a review
    // asked for exactly that on the reasoning that restoring a frame with the
    // engine attached repeats the 1.19 s resize below. Both halves were measured
    // on 2026-08-08 and both are wrong:
    //
    //  * Restoring here costs **5.3 ms**, not 1.19 s. The engine has not
    //    rasterised anything yet, so `setFrame` has no committed frame to wait
    //    on. That is a different situation from a resize at first *show*.
    //  * Moving it earlier **destroys the saved size on every launch.** Attaching
    //    the view collapses the window (to 1 x 32, or to `contentMinSize` if that
    //    is already set), and with an autosave name live that collapse is written
    //    straight back to `NSUserDefaults`. Observed: a saved 560 x 700 came back
    //    560 x 532 — the minimum — and stayed there.
    //
    // The restore is what rescues the window from the attach, so it has to
    // follow it. There is nothing to gain by reordering and a remembered size to
    // lose.
    self.setFrameAutosaveName(AppShell.configAutosaveName)
    self.isReleasedWhenClosed = false
    // Don't let macOS re-show this window via state restoration on relaunch:
    // on a permission-granted launch the Flutter surface is empty (SizedBox.shrink),
    // so a restored window paints solid black. The window is shown only on demand.
    self.isRestorable = false
    self.delegate = self

    // Menu-bar app: never show the main window; the tray drives everything.
    self.orderOut(nil)
  }

  /// The red button and ⌘W must land in exactly the same state as a Dart-driven
  /// hide, so we hide and refuse the close rather than let AppKit close the
  /// window. Two reasons, both load-bearing:
  ///
  /// * Without this, `showConfigWindow`'s `.regular` activation policy is never
  ///   undone and Orthant keeps a Dock icon and a ⌘-Tab slot for the rest of the
  ///   session — the opposite of a menu-bar agent.
  /// * Returning false keeps the window in the one state that show/hide has
  ///   always exercised. An actually-closed window (`isReleasedWhenClosed` is
  ///   false, so it would survive) is a state this app has never re-shown from,
  ///   and it hosts a live FlutterViewController.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    AppShell.hideConfigWindow(self)
    // Dart owns what is on screen and owns the hotkey registrations that
    // recording suspends; neither can be resolved from here.
    channel?.invokeMethod("onConfigWindowClosed", arguments: nil)
    return false
  }
}
