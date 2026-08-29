import Cocoa
import ServiceManagement

/// Launch-at-login, via `SMAppService` (macOS 13+).
///
/// The OS owns this state and we never cache it. The user can turn the item off
/// in System Settings ▸ General ▸ Login Items and macOS does not tell us, so a
/// copy on our side would start lying the moment they did — a checkbox reading
/// ON while doing nothing is the failure shape this project keeps finding.
/// Every read goes to `SMAppService.mainApp.status`.
enum LoginItem {
  /// Where every `SMAppService` call runs — **never the main thread**.
  ///
  /// This app runs with its UI and platform threads *merged*, so a synchronous
  /// channel handler does not merely stall AppKit: it stalls Dart, and every
  /// click and keystroke queued behind it. `SMAppService` is IPC to a system
  /// daemon, which means its latency is not ours to bound — the same shape of
  /// hazard as the AX path, where a hung target app once froze Orthant for
  /// 25.6 s before a timeout was added. Measured here at 5 ms for a status read
  /// and unmeasured for a registration, which is precisely the point: 5 ms
  /// today is not a guarantee, and the fix costs a queue hop.
  ///
  /// **Serial, and that is load-bearing.** A status read must not overtake a
  /// registration the user just asked for, or the checkbox settles on the state
  /// from *before* their click — the "control that looks configured but isn't"
  /// failure this file already documents at length.
  private static let queue = DispatchQueue(label: "app.orthant.loginitem")

  /// Answer [reply] on the main thread once the daemon has spoken.
  static func statusAsync(_ reply: @escaping (String) -> Void) {
    queue.async {
      let value = AppShell.timed("loginItemStatus") { status() }
      DispatchQueue.main.async { reply(value) }
    }
  }

  static func setAsync(_ enabled: Bool, _ reply: @escaping (String) -> Void) {
    queue.async {
      let value = AppShell.timed("setLoginItem") { set(enabled) }
      DispatchQueue.main.async { reply(value) }
    }
  }

  /// The four states Dart knows about, as channel strings.
  ///
  /// `requiresApproval` is the one worth having. Registration succeeded, but
  /// the item is switched off in System Settings, so the app will *not* launch
  /// and nothing else in the system would ever say so. Collapsing it into
  /// "disabled" would be accurate about the outcome and useless about the
  /// remedy, which is a button that opens Login Items.
  ///
  /// **`.notFound` is "not registered", not "cannot register."** Its name reads
  /// like a failure and was first mapped to `unavailable`, which the settings
  /// pane rendered as a greyed-out checkbox — so on a fresh install, before any
  /// registration exists, launch-at-login could never be switched on. Measured
  /// on a real build: status is `.notFound` beforehand, `register()` succeeds,
  /// the app appears in System Settings ▸ General ▸ Login Items, and status
  /// becomes `.enabled`. It is simply the state where no login-item record
  /// exists yet, which is exactly what `disabled` means here.
  ///
  /// That leaves `unavailable` for `@unknown default` alone — a status from a
  /// future macOS that this build cannot interpret.
  static func status() -> String {
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .notRegistered: return "disabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "disabled"
    @unknown default: return "unavailable"
    }
  }

  /// Returns the status *after* the attempt, so a refusal surfaces rather than
  /// being reported back as the state the user asked for.
  ///
  /// A throw here is normal rather than exceptional in development:
  /// `SMAppService` registers the bundle at its current path with its current
  /// signature, and a debug rebuild changes both. Logged and swallowed — the
  /// returned status is what the UI believes.
  static func set(_ enabled: Bool) -> String {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      NSLog("[orthant] login item %@ failed: %@",
            enabled ? "register" : "unregister", error.localizedDescription)
    }
    return status()
  }

  /// Open System Settings ▸ General ▸ Login Items.
  ///
  /// The only remedy for `requiresApproval`: the switch lives there and no API
  /// can set it on the user's behalf.
  static func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
