import Cocoa
import XCTest

// The app target's Swift module is named after PRODUCT_NAME (Configs/AppInfo.xcconfig),
// not after the Xcode target — so it is `orthant`, not `Runner`. @testable, because
// everything reached below is internal.
@testable import Orthant

// Headless tests for the parts of the native core that are pure.
//
// Most of this target is not: the Accessibility API needs another app's live
// window, and the overlay needs a real display arrangement and real input.
// Those are verified by manual acceptance instead. What *can* be tested here
// is the arithmetic that no amount of clicking would reliably expose, because
// it only goes wrong on display layouts a given machine may not have.

/// AppKit puts the origin at the primary display's bottom-left and grows y
/// upward; CoreGraphics and the Accessibility API put it at the top-left and
/// grow y downward. Every rect that crosses into Dart goes through one
/// conversion, and mixing the two spaces is the single most likely correctness
/// bug in this category of app.
final class CoordinateSpaceTests: XCTestCase {
  /// The height of the primary display in the arrangement used below.
  private let primaryHeight: CGFloat = 1080

  func testPrimaryVisibleFrameDropsByTheMenuBar() {
    let r = WindowControl.toTopLeft(NSRect(x: 0, y: 0, width: 1920, height: 1050),
                                    primaryHeight: primaryHeight)
    XCTAssertEqual(r.origin.x, 0)
    // The 30pt the menu bar takes off the top in AppKit's space comes back as
    // an offset from the top in ours — not as a shorter rect still at y = 0.
    XCTAssertEqual(r.origin.y, 30)
    XCTAssertEqual(r.width, 1920)
    XCTAssertEqual(r.height, 1050)
  }

  func testDisplayLeftOfAndAboveThePrimary() {
    // Negative x survives untouched; y is the part that flips.
    let r = WindowControl.toTopLeft(NSRect(x: -1147, y: 21, width: 1147, height: 719),
                                    primaryHeight: primaryHeight)
    XCTAssertEqual(r.origin.x, -1147)
    XCTAssertEqual(r.origin.y, 340)
  }

  func testDisplayBelowThePrimary() {
    // A display *below* the primary has negative AppKit y and a top-left y past
    // the bottom of the primary. These numbers, and the ones above, are this
    // machine's real three-display layout as reported independently by the
    // acceptance probe — so a sign flip here shows up as a disagreement with a
    // live system rather than only with my arithmetic.
    let r = WindowControl.toTopLeft(NSRect(x: 335, y: -720, width: 1280, height: 690),
                                    primaryHeight: primaryHeight)
    XCTAssertEqual(r.origin.y, 1110)
  }

  func testConversionIsItsOwnInverse() {
    // Both spaces measure the same distance from opposite edges, so converting
    // twice must return the original. A test that only ever converts one way
    // would pass just as happily with the height term dropped.
    let original = NSRect(x: -1147, y: 21, width: 1147, height: 719)
    let back = WindowControl.toTopLeft(
      WindowControl.toTopLeft(original, primaryHeight: primaryHeight),
      primaryHeight: primaryHeight)
    XCTAssertEqual(back, original)
  }
}

/// `applyFrame` asks for a rect, then reads back what the app actually did with
/// it. The comparison is deliberately lopsided — see the doc comments on
/// `originMatches` and `frameMatches`.
final class PlacementToleranceTests: XCTestCase {
  private let want = CGRect(x: 100, y: 200, width: 800, height: 600)

  func testExactPlacementMatches() {
    XCTAssertTrue(WindowControl.frameMatches(want, want))
    XCTAssertTrue(WindowControl.originMatches(want, want))
  }

  func testRoundingOnARetinaDisplayStillMatches() {
    let landed = CGRect(x: 101, y: 198, width: 801, height: 602)
    XCTAssertTrue(WindowControl.frameMatches(landed, want))
  }

  func testAMissByMoreThanTheToleranceDoesNotMatch() {
    XCTAssertFalse(WindowControl.frameMatches(
      CGRect(x: 103, y: 200, width: 800, height: 600), want))
    XCTAssertFalse(WindowControl.frameMatches(
      CGRect(x: 100, y: 203, width: 800, height: 600), want))
    XCTAssertFalse(WindowControl.frameMatches(
      CGRect(x: 100, y: 200, width: 800, height: 597), want))
  }

  func testAnAppAtItsMinimumSizeStillCountsAsPlaced() {
    // Finder will not shrink below ~633x252. The window is exactly where it was
    // asked to go, so the snap worked; only the size was refused. Judging
    // success on size would report that as a failure — and judging the *retry*
    // on origin alone would skip the second attempt a cross-DPI move needs.
    let landed = CGRect(x: 100, y: 200, width: 633, height: 252)
    XCTAssertTrue(WindowControl.originMatches(landed, want))
    XCTAssertFalse(WindowControl.frameMatches(landed, want))
  }
}

/// Hotkey ids are shared with Dart by convention, and nothing enforces it: Dart
/// sends a `RegionCommand` index, and these reserved ids have to stay clear of
/// that range and of each other. A collision is silent — one grab shadows the
/// other, and the losing key simply stops working.
final class ReservedHotkeyIdTests: XCTestCase {
  /// Every reserved id, including the eight arrow-selection grabs — four
  /// directions, each bare and ⇧-extended.
  private let reserved: [UInt32] =
    [HotkeyManager.overlayDismissId,
     HotkeyManager.overlayCommitId,
     HotkeyManager.overlayCommitKeypadId]
    + (0..<4).flatMap { [HotkeyManager.overlayArrowId($0, extend: false),
                         HotkeyManager.overlayArrowId($0, extend: true)] }

  func testArrowIdsAreDistinctFromEachOtherAndFromTheModalKeys() {
    // The handler recovers the direction and the ⇧ flag by *subtracting* the
    // base id, so an overlap would silently steer one key's press into another
    // key's branch rather than failing.
    let arrows = (0..<4).flatMap {
      [HotkeyManager.overlayArrowId($0, extend: false),
       HotkeyManager.overlayArrowId($0, extend: true)]
    }
    XCTAssertEqual(Set(arrows).count, 8)
    XCTAssertFalse(arrows.contains(HotkeyManager.overlayDismissId))
    XCTAssertFalse(arrows.contains(HotkeyManager.overlayCommitId))
    XCTAssertFalse(arrows.contains(HotkeyManager.overlayCommitKeypadId))
  }

  func testArrowIdsEncodeDirectionAndExtendRecoverably() {
    for i in 0..<4 {
      let bare = HotkeyManager.overlayArrowId(i, extend: false)
      let shifted = HotkeyManager.overlayArrowId(i, extend: true)
      let base = HotkeyManager.overlayArrowBaseId
      XCTAssertEqual(Int(bare - base), i, "bare index must round-trip")
      XCTAssertEqual(Int(shifted - base) - 4, i, "⇧ index must round-trip")
    }
  }

  func testReservedIdsAreDistinct() {
    XCTAssertEqual(Set(reserved).count, reserved.count)
  }

  func testReservedIdsClearDartsRange() {
    // kSummonHotkeyId in lib/shortcuts/hotkey_service.dart is 900, and every id
    // below it is a RegionCommand index.
    for id in reserved { XCTAssertGreaterThan(id, 900) }
  }
}

/// The `replaceHotkeys` payload arrives from Dart, which read it from a
/// preferences file, on the launch path. Every field crosses to Carbon as a
/// `UInt32`, whose initialiser **traps** on a negative number — so this parse is
/// the difference between one bad integer costing a shortcut and costing every
/// launch. It is also what decides which ids Dart is told were refused, and a
/// refusal it never hears about is a shortcut that silently never fires.
final class HotkeyRequestParsingTests: XCTestCase {
  private func entry(_ id: Int, _ keyCode: Int, _ modifiers: Int) -> [String: Any] {
    ["id": id, "keyCode": keyCode, "modifiers": modifiers]
  }

  func testAWellFormedPayloadParsesInOrder() {
    let (valid, invalid) = HotkeyManager.parseRequests(
      ["bindings": [entry(0, 31, 6144), entry(1, 123, 6144)]])
    XCTAssertEqual(valid, [HotkeyManager.Request(id: 0, keyCode: 31, modifiers: 6144),
                           HotkeyManager.Request(id: 1, keyCode: 123, modifiers: 6144)])
    XCTAssertTrue(invalid.isEmpty)
  }

  func testANegativeValueIsRefusedRatherThanTrapping() {
    // UInt32(-2) traps. Every one of these used to reach it.
    for bad in [entry(-2, 31, 6144), entry(3, -2, 6144), entry(4, 31, -2)] {
      let (valid, invalid) = HotkeyManager.parseRequests(["bindings": [bad]])
      XCTAssertTrue(valid.isEmpty)
      // id -2 is unreportable-but-harmless; the other two must be reported.
      XCTAssertEqual(invalid, (bad["id"] as! Int) < 0 ? [-2] : [bad["id"] as! Int])
    }
  }

  func testAMalformedEntryIsSkippedWithoutLosingTheRest() {
    let (valid, invalid) = HotkeyManager.parseRequests(
      ["bindings": [entry(0, 31, 6144), ["id": 1], ["keyCode": 9], entry(2, 8, 6144)]])
    XCTAssertEqual(valid.map(\.id), [0, 2])
    XCTAssertEqual(invalid, [1], "an entry with no id cannot be reported against")
  }

  func testAPayloadOfTheWrongShapeYieldsNothingRatherThanCrashing() {
    for junk: Any? in [nil, "bindings", ["bindings": 7], [String: Any]()] {
      let (valid, invalid) = HotkeyManager.parseRequests(junk)
      XCTAssertTrue(valid.isEmpty)
      XCTAssertTrue(invalid.isEmpty)
    }
  }

  func testAnEmptySetIsRepresentable() {
    // Every command unbound is a legitimate state, and must not read as "the
    // payload was unparseable".
    let (valid, invalid) = HotkeyManager.parseRequests(["bindings": [[String: Any]]()])
    XCTAssertTrue(valid.isEmpty)
    XCTAssertTrue(invalid.isEmpty)
  }
}

/// Deferred `AXEnhancedUserInterface` restores, and the race that made them
/// need an owner.
///
/// `applyFrame` turns the flag off around its writes and back on after. When the
/// target stops answering the restore is deferred to a retry — and a retry that
/// just wrote `true` on a timer could land inside a *later* placement, which had
/// read the `false` we left behind, concluded the app never had the flag on, and
/// skipped disabling it. The frame writes would then run with it on, which is
/// the one state the whole dance exists to avoid.
///
/// None of that needs a running app to check, which is the point of the ledger
/// being separate from the AX calls.
final class EUIRestoreLedgerTests: XCTestCase {
  private let chrome = AppIncarnation(pid: 501, startedAt: 1000)
  private let electron = AppIncarnation(pid: 502, startedAt: 1000)
  /// Same pid, started later — a different process wearing a recycled number.
  private lazy var chromeRelaunched =
    AppIncarnation(pid: chrome.pid, startedAt: chrome.startedAt + 60)

  func testNothingIsOwedToBeginWith() {
    var ledger = EUIRestoreLedger()
    XCTAssertFalse(ledger.claim(chrome))
  }

  func testAPlacementThatGivesUpLeavesADebtItsSuccessorInherits() {
    var ledger = EUIRestoreLedger()
    _ = ledger.claim(chrome)
    _ = ledger.owe(chrome)
    XCTAssertTrue(ledger.claim(chrome),
                  "the next placement must learn the app's own setting was on")
  }

  func testClaimingTakesTheRetryOffTheHook() {
    // The race itself, and the mechanism is `claim` clearing the entry: a retry
    // that fired after the second placement began would otherwise switch the
    // flag on under that placement's frame writes.
    var ledger = EUIRestoreLedger()
    let scheduled = ledger.owe(chrome)
    XCTAssertTrue(ledger.owns(chrome, generation: scheduled))

    XCTAssertTrue(ledger.claim(chrome), "the placement takes the debt over")
    XCTAssertFalse(ledger.owns(chrome, generation: scheduled),
                   "so the retry must find itself no longer responsible")
  }

  func testEachDebtGetsADistinctGeneration() {
    // Two abandoned placements in a row must not share a generation, or the
    // first retry would satisfy the second's ownership check and write at the
    // wrong moment.
    var ledger = EUIRestoreLedger()
    let first = ledger.owe(chrome)
    _ = ledger.claim(chrome)
    let second = ledger.owe(chrome)
    XCTAssertNotEqual(first, second)
    XCTAssertFalse(ledger.owns(chrome, generation: first))
    XCTAssertTrue(ledger.owns(chrome, generation: second))
  }

  func testALateRetryCannotClearANewerOwnersDebt() {
    // The first retry giving up must not settle the second one's debt on its
    // way out, or the flag stays off for good.
    var ledger = EUIRestoreLedger()
    let first = ledger.owe(chrome)
    _ = ledger.claim(chrome)
    let second = ledger.owe(chrome)

    ledger.settle(chrome, generation: first)
    XCTAssertTrue(ledger.owns(chrome, generation: second))
  }

  func testSettlingClearsTheDebt() {
    var ledger = EUIRestoreLedger()
    let generation = ledger.owe(chrome)
    ledger.settle(chrome, generation: generation)
    XCTAssertFalse(ledger.owns(chrome, generation: generation))
    XCTAssertFalse(ledger.claim(chrome), "nothing left to inherit")
  }

  func testAppsAreTrackedIndependently() {
    // Two Chromium apps hung at once is not exotic — Chrome and any Electron
    // app qualify, and one paying its debt must not clear the other's.
    var ledger = EUIRestoreLedger()
    let a = ledger.owe(chrome)
    let b = ledger.owe(electron)
    ledger.settle(chrome, generation: a)
    XCTAssertFalse(ledger.owns(chrome, generation: a))
    XCTAssertTrue(ledger.owns(electron, generation: b))
    XCTAssertTrue(ledger.claim(electron))
  }

  func testARecycledPidDoesNotInheritTheDebt() {
    // Inheriting means believing the app wants the flag *on*, so a debt that
    // outlived its owner would have us switch it on for a process that never
    // asked for it.
    var ledger = EUIRestoreLedger()
    _ = ledger.owe(chrome)
    XCTAssertFalse(ledger.claim(chromeRelaunched),
                   "same pid, different process")
  }

  func testARecycledPidDoesNotSettleTheOriginalsDebt() {
    var ledger = EUIRestoreLedger()
    let generation = ledger.owe(chrome)
    ledger.settle(chromeRelaunched, generation: generation)
    XCTAssertTrue(ledger.owns(chrome, generation: generation))
  }
}


/// The two decisions the `AXEnhancedUserInterface` dance turns on, as pure
/// functions — which is the only reason they can be tested at all. Everything
/// around them needs a live app and a hung one, and is manual acceptance.
final class EUIPlanTests: XCTestCase {
  func testAnAppThatNeverWantedItIsLeftAlone() {
    XCTAssertEqual(
      euiPlan(owed: false, read: .ok, isOn: false, identified: true), .placeOnly)
  }

  func testAFlagThatIsOnGetsTurnedOffAndPutBack() {
    XCTAssertEqual(
      euiPlan(owed: false, read: .ok, isOn: true, identified: true),
      .disableThenRestore)
  }

  func testADebtWeStillOweIsRestoredWithoutAnotherWrite() {
    // We turned it off and never managed to undo it. It is already where the
    // frame writes need it, so there is nothing to write — only to put back.
    XCTAssertEqual(
      euiPlan(owed: true, read: .ok, isOn: false, identified: true),
      .restoreAfter)
  }

  func testADebtDoesNotProveTheFlagIsStillOff() {
    // **The regression.** Another accessibility client, or the app itself, can
    // set the flag between our giving up and our next attempt. Reading the debt
    // as proof of the state skipped the disable and ran the frame writes with
    // the flag on — the one condition they exist to avoid.
    XCTAssertEqual(
      euiPlan(owed: true, read: .ok, isOn: true, identified: true),
      .disableThenRestore,
      "owed says what the app wants; only the read says what is true")
  }

  func testAnAppThatIsNotAnsweringIsAbandonedWithTheDebtIntact() {
    XCTAssertEqual(
      euiPlan(owed: true, read: .unavailable, isOn: false, identified: true),
      .abandon(reDefer: true))
    XCTAssertEqual(
      euiPlan(owed: false, read: .unavailable, isOn: false, identified: true),
      .abandon(reDefer: false))
  }

  func testAMissingAttributeIsNotADebt() {
    // The app quit, or never supported it. Nothing to turn off, nothing owed —
    // re-deferring here would leave a debt nobody can ever pay.
    XCTAssertEqual(
      euiPlan(owed: true, read: .gone, isOn: false, identified: true),
      .placeOnly)
  }

  func testAnUnidentifiableAppIsNeverDisabled() {
    // **The other regression.** Without a stable incarnation we cannot record
    // that we owe a restore — so disabling would strand the flag off for good if
    // the app then hung. `launchDate` was nil for every one of the first six
    // running apps on this machine, so this is not a corner.
    XCTAssertEqual(
      euiPlan(owed: false, read: .ok, isOn: true, identified: false),
      .placeOnly,
      "better a frame that lands wrong than an app left without accessibility")
  }
}

/// `AXError` is wider than the one case the code used to check for.
final class AXOutcomeTests: XCTestCase {
  func testSuccessIsTheOnlySuccess() {
    XCTAssertEqual(AXOutcome(.success), .ok)
  }

  func testAnAppThatStoppedAnsweringIsRetryable() {
    XCTAssertEqual(AXOutcome(.cannotComplete), .unavailable)
  }

  func testAnUnexplainedFailureIsNotSuccess() {
    // The heart of it: `kAXErrorFailure` says the call did not work and does not
    // say why. Code that checked only for `cannotComplete` treated it — and
    // every other error — as though the write had landed, which is how a flag
    // gets left switched off forever.
    XCTAssertEqual(AXOutcome(.failure), .unavailable)
    XCTAssertEqual(AXOutcome(.apiDisabled), .unavailable)
    XCTAssertEqual(AXOutcome(.illegalArgument), .unavailable)
  }

  func testAThingThatNoLongerExistsIsTerminal() {
    // Retrying these repeats them forever.
    XCTAssertEqual(AXOutcome(.invalidUIElement), .gone)
    XCTAssertEqual(AXOutcome(.attributeUnsupported), .gone)
    XCTAssertEqual(AXOutcome(.noValue), .gone)
    XCTAssertEqual(AXOutcome(.notImplemented), .gone)
  }

  func testOnlyAnUnavailableRestoreIsRetried() {
    XCTAssertEqual(restoreVerdict(.ok), .settled)
    XCTAssertEqual(restoreVerdict(.gone), .settled,
                   "nothing left to put it back on")
    XCTAssertEqual(restoreVerdict(.unavailable), .retry)
  }
}

/// The incarnation identity, which is what keeps a debt from outliving its owner.
final class AppIncarnationTests: XCTestCase {
  func testThisProcessIsIdentifiable() {
    // The nil case has to be genuinely rare, because the plan refuses to touch
    // the flag without an identity. `NSRunningApplication.launchDate` was not
    // good enough: nil for every one of the first six apps sampled here.
    let me = AppIncarnation(pid: ProcessInfo.processInfo.processIdentifier)
    XCTAssertNotNil(me)
    XCTAssertGreaterThan(me?.startedAt ?? 0, 0)
  }

  func testTheSameProcessIdentifiesTheSameWayTwice() {
    let pid = ProcessInfo.processInfo.processIdentifier
    XCTAssertEqual(AppIncarnation(pid: pid), AppIncarnation(pid: pid))
  }

  func testAPidThatIsNotRunningHasNoIdentity() {
    // pid 0 is the kernel's own; proc_pidinfo will not describe it as a BSD
    // process, which is the "cannot vouch for this" path the plan guards on.
    XCTAssertNil(AppIncarnation(pid: 0))
  }
}

/// The settings window's frame: when a show establishes one, and the limits the
/// user can drag it between.
///
/// The window's size is AppKit's — the user drags it, `setFrameAutosaveName`
/// remembers it, and nothing in this app computes it. What is left to get wrong
/// is the one moment a show must *impose* a frame, because the window has never
/// had a real one.
final class ConfigWindowFrameTests: XCTestCase {
  /// A window that already has a real frame is left exactly as it is. This is
  /// the **reopen** case and the reason the predicate no longer asks whether the
  /// window is visible.
  ///
  /// `hideConfigWindow` is `orderOut`, which leaves the frame untouched, so a
  /// hidden window reports this same rect. While the rule read `!isVisible || …`
  /// every reopen re-placed it — dropping the user back to `configOpeningHeight`
  /// centred and, because `setFrame` on a window with an autosave name writes
  /// through to `NSUserDefaults`, *destroying* the size they had chosen rather
  /// than merely ignoring it.
  ///
  /// It is also the bring-forward case: `showConfigWindow` is called on an
  /// already-open window to switch panes, and reframing it there is the direct
  /// cause of the region picker's hit-test offset. One rule now covers both,
  /// which is the point — visibility never distinguished them.
  func testARealFrameIsKeptWhetherTheWindowIsHiddenOrOnScreen() {
    XCTAssertFalse(AppShell.configWindowNeedsPlacement(
      contentLayoutRect: NSRect(x: 0, y: 0, width: 560, height: 752)))
  }

  /// The launch sliver, which is the only state that genuinely needs a frame.
  ///
  /// Assigning FlutterViewController's initially zero-sized view collapses the
  /// nib window to 1 × 32 pt — measured, not assumed — leaving the title bar
  /// consuming all 32 and no usable content. It reaches `showConfigWindow` both
  /// ordered out (the normal path) and visible (the nib orders it front), so the
  /// answer must not depend on which.
  func testTheTitleBarOnlyLaunchSliverNeedsPlacement() {
    XCTAssertTrue(AppShell.configWindowNeedsPlacement(
      contentLayoutRect: NSRect(x: 0, y: 0, width: 1, height: 0)))
  }

  /// The case an `isEmpty` check would get wrong, and the reason this is a
  /// threshold instead.
  ///
  /// `NSRect.isEmpty` is only true at height ≤ 0, so a sliver left with a single
  /// point of content area would report "already placed" and skip the opening
  /// frame — leaving a first-run user an onboarding window they cannot see. The
  /// exact height depends on the title-bar metric, which is not ours to control,
  /// so the guard must not be balanced on it being precisely zero.
  func testASliverWithANonZeroContentHeightStillNeedsPlacement() {
    XCTAssertTrue(AppShell.configWindowNeedsPlacement(
      contentLayoutRect: NSRect(x: 0, y: 0, width: 1, height: 1)))
  }

  /// And the threshold must stay far below any real pane, so a genuinely open
  /// window is never re-placed under the user. The shortest pane is General's.
  func testTheShortestRealPaneIsWellAboveTheThreshold() {
    XCTAssertLessThan(
      AppShell.minimumRealContentHeight, 446,
      "General's pane is 446.5 pt; the threshold must not approach it")
  }

  /// The limits are a pair, not two numbers: equal widths are how AppKit is told
  /// to offer a vertical drag only, and a floor below the region picker's ~430 pt
  /// of fixed content would let the window be dragged into a broken state.
  func testTheResizeLimitsLockWidthAndFloorTheHeight() {
    XCTAssertEqual(AppShell.configMinContentSize.width,
                   AppShell.configMaxContentSize.width,
                   "equal widths are what makes the resize vertical-only")
    XCTAssertEqual(AppShell.configMinContentSize.width, AppShell.configWidth)
    XCTAssertGreaterThanOrEqual(
      AppShell.configMinContentSize.height, 500,
      "the region picker is ~430 pt and both panes pin a footer")
    XCTAssertGreaterThan(AppShell.configMaxContentSize.height,
                         AppShell.configMinContentSize.height,
                         "the height must actually be draggable")
  }

  /// The default frame is only ever used on a first run, and it has to fit the
  /// smallest display this was designed against (690 pt visible).
  func testTheOpeningFrameFitsASmallDisplayAndClearsTheFloor() {
    XCTAssertLessThanOrEqual(AppShell.configOpeningHeight, 690,
                             "the smallest display designed against shows 690 pt")
    // `configOpeningHeight` is a FRAME height and `configMinContentSize` a
    // CONTENT size. Comparing them directly is exactly the unit mix that made
    // this window oscillate across six sizes on 2026-07-28, so AppKit converts
    // one to the other rather than a hardcoded title-bar guess doing it.
    let floorAsFrame = NSWindow.frameRect(
      forContentRect: NSRect(origin: .zero, size: AppShell.configMinContentSize),
      styleMask: [.titled, .closable, .resizable]).height
    XCTAssertGreaterThan(
      AppShell.configOpeningHeight, floorAsFrame,
      "opening below the floor would make AppKit correct it immediately")
  }
}
