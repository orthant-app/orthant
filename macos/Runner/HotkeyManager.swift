import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

/// Registers system-wide hotkeys via Carbon and forwards each press to Dart as
/// `onHotkey(id)` over the app.orthant/window channel.
final class HotkeyManager {
  private let channel: FlutterMethodChannel
  private var refs: [UInt32: EventHotKeyRef] = [:]
  private var handlerRef: EventHandlerRef?
  private let signature: OSType = 0x4F525448 // 'ORTH'

  /// Wall-clock ms of the most recent hotkey press. M4 measures summon latency
  /// from the *physical* trigger, which happens here — not from the later
  /// `showOverlay` call, which only arrives after a Dart round trip that the
  /// user waits through too.
  private(set) var lastPressAtMs: Double = 0

  /// Reserved id for the overlay's Esc grab, handled natively and never
  /// forwarded to Dart. Dart's ids are RegionCommand indices, so the ranges
  /// cannot meet. Esc-to-dismiss is a fixed property of a modal overlay rather
  /// than a user-rebindable binding, and only this side knows when the panel is
  /// actually on screen — a bare-Esc grab that outlived it would take Esc away
  /// from every other app.
  static let overlayDismissId: UInt32 = 901

  /// Invoked instead of forwarding to Dart when `overlayDismissId` fires.
  var onOverlayDismiss: (() -> Void)?

  /// Reserved ids handled natively, never forwarded to Dart. Dart's ids are
  /// RegionCommand indices, so the ranges cannot meet.
  static let overlayCommitId: UInt32 = 902

  /// Invoked instead of forwarding when `overlayCommitId` fires.
  var onOverlayCommit: (() -> Void)?

  /// Reserved id for the overlay's keypad-Enter commit grab, alongside
  /// `overlayCommitId`'s regular-Return grab. Named explicitly so a future
  /// reserved id cannot collide with the un-named `overlayCommitId + 1` this
  /// replaces.
  static let overlayCommitKeypadId: UInt32 = overlayCommitId + 1

  /// Reserved id for ⌘S — "save this shape as a shortcut".
  ///
  /// The most commonly-pressed chord any of these grabs takes, so the scoping
  /// matters more here than anywhere: it is registered with the panel and
  /// released through the single exit in `dismissOverlay()`, exactly as Return
  /// is. Held a moment longer than the overlay exists, it would take Save from
  /// every other app.
  static let overlaySaveId: UInt32 = 904

  /// Invoked instead of forwarding when `overlaySaveId` fires.
  var onOverlaySave: (() -> Void)?

  /// Reserved ids for the overlay's arrow-key selection: four directions, each
  /// bare and ⇧-extended.
  ///
  /// Grabbed rather than handled in Flutter for the same reason Esc and Return
  /// are: `OverlayPanel.canBecomeKey` is false, deliberately — a key panel
  /// resigns the target window's key status and dims its title bar — so no key
  /// event ever reaches the overlay's own engine.
  ///
  /// These are the only grabs here that take a **bare, unmodified** key that
  /// applications ordinarily use, which is why they are registered strictly
  /// alongside the panel and released the instant it goes away. `grabOverlayKeys`
  /// already aborts the whole summon if the modal keys cannot be taken.
  static let overlayArrowBaseId: UInt32 = 910

  /// direction index 0…3 = left, right, up, down; +4 for the ⇧ variant.
  static func overlayArrowId(_ index: Int, extend: Bool) -> UInt32 {
    overlayArrowBaseId + UInt32(index) + (extend ? 4 : 0)
  }

  /// Invoked with the direction name and whether ⇧ was held.
  var onOverlayArrow: ((String, Bool) -> Void)?

  /// The four arrows, in the order the ids above encode.
  private static let arrowKeys: [(name: String, code: Int)] = [
    ("left", kVK_LeftArrow), ("right", kVK_RightArrow),
    ("up", kVK_UpArrow), ("down", kVK_DownArrow),
  ]

  /// Set while the overlay is showing. Region shortcuts must not fire then:
  /// applyRegion would re-capture and overwrite the session's handles
  /// underneath an open grid.
  var suppressesRegionHotkeys = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    installHandler()
  }

  private func installHandler() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: OSType(kEventHotKeyPressed))
    let this = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
      guard let userData = userData, let event = event else { return noErr }
      let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
      mgr.lastPressAtMs = Date().timeIntervalSince1970 * 1000.0
      var hkID = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
      if hkID.id == HotkeyManager.overlayDismissId {
        mgr.onOverlayDismiss?()
        return noErr
      }
      if hkID.id == HotkeyManager.overlayCommitId ||
         hkID.id == HotkeyManager.overlayCommitKeypadId {
        mgr.onOverlayCommit?()
        return noErr
      }
      if hkID.id == HotkeyManager.overlaySaveId {
        mgr.onOverlaySave?()
        return noErr
      }
      let arrow = Int(hkID.id) - Int(HotkeyManager.overlayArrowBaseId)
      if arrow >= 0 && arrow < HotkeyManager.arrowKeys.count * 2 {
        let extend = arrow >= HotkeyManager.arrowKeys.count
        let index = extend ? arrow - HotkeyManager.arrowKeys.count : arrow
        mgr.onOverlayArrow?(HotkeyManager.arrowKeys[index].name, extend)
        return noErr
      }
      if mgr.suppressesRegionHotkeys { return noErr }
      mgr.channel.invokeMethod("onHotkey", arguments: Int(hkID.id))
      return noErr
    }, 1, &spec, this, &handlerRef)
  }

  /// keyCode = Carbon virtual key code; modifiers = Carbon modifier mask.
  ///
  /// Returns false when the OS refuses the chord, which it does when macOS or
  /// another app already owns it. That refusal is the *only* signal there is: a
  /// rejected hotkey is indistinguishable from a live one afterwards — it is
  /// simply never delivered. Swallowing it is how a combination can sit in the
  /// settings list looking configured and never once fire.
  @discardableResult
  func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
    if let existing = refs[id] { UnregisterEventHotKey(existing); refs[id] = nil }
    var ref: EventHotKeyRef?
    let hkID = EventHotKeyID(signature: signature, id: id)
    guard RegisterEventHotKey(keyCode, modifiers, hkID,
                              GetApplicationEventTarget(), 0, &ref) == noErr,
          let ref = ref else { return false }
    refs[id] = ref
    return true
  }

  /// Drop a single registration.
  func unregister(id: UInt32) {
    if let ref = refs[id] { UnregisterEventHotKey(ref); refs[id] = nil }
  }

  /// One entry of a `replaceHotkeys` payload, after validation.
  struct Request: Equatable {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
  }

  /// Split a `replaceHotkeys` payload into what can be registered and the ids
  /// that cannot — which the caller reports as refused, since from Dart's side
  /// "macOS would not take this chord" and "this chord is not representable"
  /// have the same consequence: the shortcut never fires.
  ///
  /// Separate from the channel handler so it can be tested. All three values
  /// cross to Carbon as `UInt32`, whose initialiser **traps** on a negative
  /// number: `UInt32(-2)` is not a bad shortcut but a hard crash. These values
  /// originate in a preferences file and are read on the launch path, so an
  /// unchecked one takes the app down on every start with no way out but
  /// deleting the file by hand. Dart validates them too; a channel boundary
  /// still must not be able to crash on whatever it is handed.
  static func parseRequests(_ arguments: Any?) -> (valid: [Request], invalid: [Int]) {
    guard let a = arguments as? [String: Any],
          let entries = a["bindings"] as? [[String: Any]] else { return ([], []) }
    var valid: [Request] = []
    var invalid: [Int] = []
    for entry in entries {
      // An entry with no readable id cannot be reported against, so it is
      // dropped rather than counted.
      guard let id = entry["id"] as? Int else { continue }
      guard let keyCode = entry["keyCode"] as? Int,
            let mods = entry["modifiers"] as? Int,
            let hotkeyId = UInt32(exactly: id),
            let code = UInt32(exactly: keyCode),
            let modifiers = UInt32(exactly: mods) else {
        invalid.append(id)
        continue
      }
      valid.append(Request(id: hotkeyId, keyCode: code, modifiers: modifiers))
    }
    return (valid, invalid)
  }

  /// Replace the whole hotkey set in one pass, returning the ids macOS refused.
  ///
  /// Atomic by construction: Dart used to unregister and then register each
  /// binding in a separately awaited call, so a second caller could begin its
  /// own replacement in the gaps and leave shortcuts registered that the
  /// settings list already showed as unset. There are no gaps here.
  func replaceAll(_ arguments: Any?) -> [Int] {
    unregisterAll()
    let (valid, invalid) = HotkeyManager.parseRequests(arguments)
    var refused = invalid
    for r in valid where !register(id: r.id, keyCode: r.keyCode, modifiers: r.modifiers) {
      refused.append(Int(r.id))
    }
    return refused
  }

  /// Grab the overlay's modal keys. Returns whether the two the overlay cannot
  /// honestly open without — **Esc and Return** — were both taken.
  ///
  /// Either one failing has the same shape: the key falls through to the
  /// application *behind* the overlay, so a press meant to cancel or commit a
  /// window placement instead closes that app's dialog or triggers whatever
  /// utility owns the chord — while the grid stays on screen looking like it
  /// ignored the keystroke. Esc additionally leaves no keyboard way out. The
  /// caller aborts on false.
  ///
  /// Return is included because it is not a convenience: the spec lists it as
  /// an MVP keyboard affordance ("`Esc` cancels; `Enter`/`Return` commits the
  /// current selection" — orthant-mvp-spec-revised.md), added precisely because
  /// being mouse-only is the most-cited weakness of this category of app.
  ///
  /// Keypad Enter is the one allowed to fail. It is an alias for Return rather
  /// than a distinct affordance, so losing it costs a user with a numeric
  /// keypad one of two ways to do the same thing — not worth refusing to show
  /// the grid over.
  @discardableResult
  func grabOverlayKeys() -> Bool {
    let canDismiss = register(id: HotkeyManager.overlayDismissId,
                              keyCode: UInt32(kVK_Escape), modifiers: 0)
    let canCommit = register(id: HotkeyManager.overlayCommitId,
                             keyCode: UInt32(kVK_Return), modifiers: 0)
    register(id: HotkeyManager.overlayCommitKeypadId,
             keyCode: UInt32(kVK_ANSI_KeypadEnter), modifiers: 0)
    // ⌘S is an accelerator, not a precondition. Esc and Return abort a summon
    // when refused because without them the overlay traps keys it has taken
    // from the app behind it; ⌘S takes nothing away, so losing it costs one
    // shortcut and nothing else — the same reasoning as the arrows below.
    register(id: HotkeyManager.overlaySaveId,
             keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey))
    // Arrow selection is an enhancement, not a precondition: a refusal costs
    // keyboard aiming and leaves the mouse working, so unlike Esc and Return it
    // must not abort the summon.
    for (i, key) in HotkeyManager.arrowKeys.enumerated() {
      register(id: HotkeyManager.overlayArrowId(i, extend: false),
               keyCode: UInt32(key.code), modifiers: 0)
      register(id: HotkeyManager.overlayArrowId(i, extend: true),
               keyCode: UInt32(key.code), modifiers: UInt32(shiftKey))
    }
    suppressesRegionHotkeys = true
    return canDismiss && canCommit
  }

  func releaseOverlayKeys() {
    unregister(id: HotkeyManager.overlayDismissId)
    unregister(id: HotkeyManager.overlayCommitId)
    unregister(id: HotkeyManager.overlayCommitKeypadId)
    unregister(id: HotkeyManager.overlaySaveId)
    // Released with the panel, without exception: these are bare arrow keys, and
    // holding them a moment longer than the overlay exists would take them from
    // every other app.
    for i in HotkeyManager.arrowKeys.indices {
      unregister(id: HotkeyManager.overlayArrowId(i, extend: false))
      unregister(id: HotkeyManager.overlayArrowId(i, extend: true))
    }
    suppressesRegionHotkeys = false
  }

  func unregisterAll() {
    for (_, ref) in refs { UnregisterEventHotKey(ref) }
    refs.removeAll()
  }
}
