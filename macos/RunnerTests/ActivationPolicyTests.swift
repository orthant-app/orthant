import XCTest

@testable import Orthant

/// `mayReturnToAccessory(windows:)` — the decision behind "may we drop back
/// to `.accessory`?", shared by `AppShell.hideConfigWindow` and
/// `Updater.finished` (Task 8, M12). The AppKit half that gathers
/// `NSApp.windows` into `[WindowActivationFact]` needs a running application
/// and is not tested here — only the classification, which is where both of
/// this task's two defects actually lived.
final class ActivationPolicyTests: XCTestCase {
  private func fact(_ className: String, visible: Bool) -> WindowActivationFact {
    WindowActivationFact(className: className, isVisible: visible)
  }

  func testNothingOpenAtAllPermitsAccessory() {
    XCTAssertTrue(mayReturnToAccessory(windows: []))
  }

  /// The exact state that produced the 2026-08-31 defect: Sparkle is about to
  /// put an error alert on screen, so nothing is in the window list *yet*, and
  /// the window-based rule alone says "safe to drop the Dock icon". It is not.
  /// Dropping to `.accessory` here leaves the alert with no Dock icon, no
  /// ⌘-Tab entry and a disabled menu — reachable only by minimising every
  /// other window on screen.
  ///
  /// An empty list is deliberate rather than incidental: it is what makes this
  /// case unreachable by the window rule, so the flag is the only thing that
  /// can refuse it. Delete the `modalAlertOnScreen` guard and this is the test
  /// that fails.
  func testModalAlertRefusesAccessoryEvenWithNoWindowsYetOnScreen() {
    XCTAssertFalse(mayReturnToAccessory(windows: [], modalAlertOnScreen: true))
  }

  /// …and it must not become a one-way latch. Once the alert is dismissed the
  /// app has to get back to `.accessory`, or a single failed update check
  /// leaves a menu-bar app showing a Dock icon until it is relaunched.
  func testAccessoryIsPermittedAgainOnceTheModalAlertIsGone() {
    XCTAssertTrue(mayReturnToAccessory(windows: [], modalAlertOnScreen: false))
  }

  /// The flag outranks the window list rather than being merged with it: a
  /// visible, exempt window would otherwise still permit `.accessory` while an
  /// alert owns the screen.
  func testModalAlertOutranksAnOtherwisePermittedWindowSet() {
    XCTAssertFalse(mayReturnToAccessory(windows: [
      fact("NSStatusBarWindow", visible: true),
    ], modalAlertOnScreen: true))
  }

  func testEveryWindowHiddenPermitsAccessoryRegardlessOfClass() {
    // Mirrors what `hideConfigWindow` actually sees: measured (Task 8), its
    // own window's `isVisible` already reads false immediately after
    // `orderOut(nil)`, in the same synchronous call — so an unrecognised
    // class here must not block on visibility alone.
    XCTAssertTrue(mayReturnToAccessory(windows: [
      fact("MainFlutterWindow", visible: false),
      fact("OverlayPanel", visible: false),
      fact("NSStatusBarWindow", visible: false),
      fact("SomeWindowClassThisFileHasNeverHeardOf", visible: false),
    ]))
  }

  func testTheStatusItemsOwnWindowAloneStillPermitsAccessory() {
    // The measurement this task was built on: `NSStatusBarWindow` is present
    // in `NSApp.windows` and reports `isVisible == true` for this app's
    // entire life — observed both a second after launch and at the exact
    // moment `hideConfigWindow` restores `.accessory`. Without this
    // exclusion the predicate could never return true at all, which was
    // `Updater.finished`'s shipped defect: `allSatisfy { !$0.isVisible }`
    // with no exclusion never passes on a menu-bar app.
    XCTAssertTrue(mayReturnToAccessory(windows: [
      fact("NSStatusBarWindow", visible: true),
    ]), "the status item's own window must never read as \"still needs .regular\"")
  }

  func testAVisibleSummonedOverlayPanelStillPermitsAccessory() {
    // The regression the brief calls out as worse than the defect being
    // fixed: nothing on the overlay's dismiss path touches activation
    // policy, so counting a summoned panel would strand the app in
    // `.regular` after every grid summon.
    XCTAssertTrue(mayReturnToAccessory(windows: [
      fact("OverlayPanel", visible: true),
      fact("NSStatusBarWindow", visible: true),
    ]), "a summoned overlay must never pin the app in .regular")
  }

  func testAVisibleSettingsWindowRefusesAccessory() {
    // The ordinary case `hideConfigWindow` restores behind every day:
    // Settings itself still on screen.
    XCTAssertFalse(mayReturnToAccessory(windows: [
      fact("MainFlutterWindow", visible: true),
      fact("NSStatusBarWindow", visible: true),
    ]))
  }

  func testAVisibleUnrecognisedWindowRefusesAccessory() {
    // The exclusion-based half of the design: a window class this predicate
    // has never seen — a future window type, or Sparkle's own alert, which
    // this task deliberately did not enumerate — counts as still needing
    // `.regular` rather than being silently ignored. Understating the risk
    // here reproduces defect 1 (a focus-dead window under `.accessory`);
    // overstating it costs one extra Dock icon, undone by the next close of
    // anything at all.
    XCTAssertFalse(mayReturnToAccessory(windows: [
      fact("SUUpdateAlert", visible: true), // illustrative name, not measured
      fact("NSStatusBarWindow", visible: true),
    ]))
  }

  func testAnUnrecognisedVisibleWindowRefusesEvenAlongsideExemptOnes() {
    // The exclusion applies per window, not as an aggregate: one blocking
    // window outvotes any number of exempt ones rather than being averaged
    // away by them.
    XCTAssertFalse(mayReturnToAccessory(windows: [
      fact("OverlayPanel", visible: true),
      fact("NSStatusBarWindow", visible: true),
      fact("SomeUpdaterWindow", visible: true),
    ]))
  }

  func testSettingsClosingWhileAnUpdateWindowIsStillUpRefusesAccessory() {
    // Defect 1, reproduced directly: Settings closes (its own window already
    // hidden, per the ordering `hideConfigWindow` measures) while Sparkle's
    // window is still on screen.
    XCTAssertFalse(mayReturnToAccessory(windows: [
      fact("MainFlutterWindow", visible: false),
      fact("NSStatusBarWindow", visible: true),
      fact("SUStatusController", visible: true), // illustrative name, not measured
    ]))
  }
}
