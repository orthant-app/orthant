import Cocoa

/// One window's facts, exactly as needed to decide whether it still needs
/// `.regular` — deliberately not the `NSWindow` itself. Gathering these needs
/// a live window server; deciding from them does not, which is what makes
/// `mayReturnToAccessory(windows:)` below testable in RunnerTests.
struct WindowActivationFact: Equatable {
  /// `String(describing: type(of: window))` — the **bare** Swift type name,
  /// e.g. "OverlayPanel". Deliberately not `NSStringFromClass`, which bridges
  /// a Swift class to Objective-C as `"<ModuleName>.<ClassName>"` — measured
  /// (Task 8) as `"Orthant.OverlayPanel"`, `"Orthant.MainFlutterWindow"`.
  /// This app's module name already has to track `PRODUCT_NAME` for reasons
  /// documented in CLAUDE.md's Commands section; coupling this list to it too
  /// is one more place for the two to drift apart silently. AppKit's own
  /// private classes (`NSStatusBarWindow`) carry no such prefix either way,
  /// since they were never Swift types to begin with.
  let className: String
  let isVisible: Bool
}

/// Window classes known to work fine under `.accessory`, measured (Task 8)
/// against a real running build rather than assumed:
///
///  - `OverlayPanel`: Orthant's own grid panels. Resident for the app's whole
///    life and non-activating by design, and nothing on their dismiss path
///    touches activation policy — an *inclusive* predicate (one that has to
///    be taught every window type that is safe to ignore) would strand the
///    app in `.regular` after every summon the first time this list fell out
///    of date, which is worse than the defect this predicate exists to fix.
///  - `NSStatusBarWindow`: AppKit's private backing window for the tray's own
///    status item. Measured present in `NSApp.windows` with `isVisible ==
///    true` from under a second after launch and for the rest of the app's
///    life — it is never absent and never hidden. Without this exclusion the
///    predicate below could never return `true` at all, which is exactly
///    `Updater.finished`'s shipped defect: it checked
///    `NSApp.windows.allSatisfy { !$0.isVisible }` with no exclusion, so a
///    permanent Dock icon followed the very first update check.
private let windowClassesExemptFromRegular: Set<String> = [
  "OverlayPanel",
  "NSStatusBarWindow",
]

/// The decision, as a pure function of simple per-window facts: whether
/// nothing currently open still needs `.regular` — i.e. whether it is safe to
/// drop back to `.accessory`. See `mayReturnToAccessory()` for the thin
/// AppKit shim both `AppShell.hideConfigWindow` and `Updater.finished` call.
///
/// **Exclusion-based, deliberately.** A window class this does not recognise
/// counts as still needing `.regular`, so a future window type fails toward
/// *keeping* the Dock icon rather than toward stripping keyboard focus from a
/// window that cannot get it back under `.accessory`. The two costs are not
/// symmetric: one Dock icon too many is undone by the next close of anything
/// at all, anywhere in the app; a focus-dead settings or update window is not
/// undone by anything the user can do to it (M7's own settings-window comment
/// on this: a window shown from an `.accessory` app cannot take keyboard
/// focus properly).
///
/// **`modalAlertOnScreen` exists because the window list is not always enough.**
/// A window can be *about to appear* and therefore absent from `NSApp.windows`
/// at the instant this is asked. That is not hypothetical: it is the defect
/// reproduced on 2026-08-31 by the tamper test. Sparkle's `showUpdaterError:`
/// closes the preceding status window one line before building its `NSAlert`;
/// that close triggers the session-end hook, whose deferred `finished()` asks
/// this question while the alert **does not exist yet**, gets "yes, nothing is
/// visible", and strips the Dock icon out from under a window that appears a
/// moment later — leaving an error dialog with no Dock icon, no ⌘-Tab entry
/// and a disabled menu, reachable only by minimising every other window.
/// Sparkle brackets the whole modal session for us (`standardUserDriverWill/
/// DidShowModalAlert`, verified in `SPUStandardUserDriver.m` to fire either
/// side of `runModal`), so the flag answers "a modal alert owns the screen"
/// without depending on when its window registers.
func mayReturnToAccessory(windows: [WindowActivationFact],
                          modalAlertOnScreen: Bool = false) -> Bool {
  if modalAlertOnScreen { return false }
  return !windows.contains { $0.isVisible && !windowClassesExemptFromRegular.contains($0.className) }
}

/// Set while Sparkle owns the screen with a modal alert. Not `Updater`-private:
/// `AppShell.hideConfigWindow` shares this predicate, and closing the settings
/// window must not strip the Dock icon from an update alert either.
var sparkleModalAlertOnScreen = false

/// Whether it is safe to drop back to `.accessory` right now. The one
/// predicate both call sites share — deliberately untested: `NSApp.windows`
/// needs a running application, which is exactly what keeping the decision
/// above separate from this gathering step avoids requiring for the part
/// that is actually worth testing.
func mayReturnToAccessory() -> Bool {
  mayReturnToAccessory(windows: NSApp.windows.map {
    WindowActivationFact(className: String(describing: type(of: $0)),
                          isVisible: $0.isVisible)
  }, modalAlertOnScreen: sparkleModalAlertOnScreen)
}
