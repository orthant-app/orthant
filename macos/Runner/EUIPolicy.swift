import AppKit
import ApplicationServices
import Darwin

/// Everything about the `AXEnhancedUserInterface` dance that does not need a
/// running app to decide — so that the part most likely to be wrong is the part
/// a test can execute.
///
/// `applyFrame` turns that flag off around the position/size writes, because
/// Chromium and Electron mis-set frames while it is on (spec §5), and turns it
/// back on afterwards. Every complication below comes from the target being able
/// to stop answering in the middle.

// MARK: - Which process, exactly

/// A process *incarnation*, not a process slot.
///
/// pids are reused. A debt keyed on the number alone could outlive the app that
/// incurred it and be inherited by whatever next holds it — and inheriting one
/// means believing that app wants `AXEnhancedUserInterface` on, so we would
/// switch it on for a process that never asked.
///
/// The kernel's process start time is what separates the two. `NSRunningApplication.launchDate`
/// was the obvious candidate and is not usable: Apple only fills it in for apps
/// launched through Launch Services, and sampling the running applications on
/// this machine found it **nil for every one of the first six**.
struct AppIncarnation: Hashable {
  let pid: pid_t
  /// Seconds since the epoch, from the kernel's own record of the process.
  let startedAt: TimeInterval

  init(pid: pid_t, startedAt: TimeInterval) {
    self.pid = pid
    self.startedAt = startedAt
  }

  /// Nil only when the kernel will not describe the process — which in practice
  /// means it has already gone. Callers must treat that as "no stable identity"
  /// and leave the flag alone rather than change something they cannot promise
  /// to change back.
  init?(pid: pid_t) {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
      return nil
    }
    self.init(pid: pid,
              startedAt: TimeInterval(info.pbi_start_tvsec)
                + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
  }

  init?(_ app: NSRunningApplication?) {
    guard let app else { return nil }
    self.init(pid: app.processIdentifier)
  }
}

// MARK: - What an AX call actually told us

/// What an `AXError` means for a call we needed to have *landed*.
///
/// The point of the three cases is the third. Code that checks only for
/// `.cannotComplete` treats every other failure as success — and `kAXErrorFailure`
/// exists precisely to say "this did not work" without saying why. Acting on
/// that as though the write had landed is how a flag gets left switched off
/// forever.
enum AXOutcome: Equatable {
  /// It worked. A value read alongside it can be trusted.
  case ok
  /// The element or the attribute does not exist and will not start existing:
  /// the app quit, or it never supported this. Nothing to retry, nothing owed.
  case gone
  /// It did not land, and might if tried again. `.cannotComplete` for an app
  /// that has stopped answering — and **everything unrecognised**, because an
  /// unexplained failure is not evidence of success.
  case unavailable

  init(_ error: AXError) {
    switch error {
    case .success:
      self = .ok
    case .invalidUIElement, .invalidUIElementObserver,
         .attributeUnsupported, .parameterizedAttributeUnsupported,
         .actionUnsupported, .notificationUnsupported,
         .noValue, .notImplemented:
      self = .gone
    default:
      self = .unavailable
    }
  }
}

// MARK: - What a placement should do about the flag

/// The decision a placement makes before it touches a window.
enum EUIPlan: Equatable {
  /// The app does not want the flag on. Place the window and touch nothing.
  case placeOnly
  /// It is on. Turn it off, place, then put it back.
  case disableThenRestore
  /// It is already off *because we turned it off* and never managed to undo it.
  /// Place, then put it back — no write needed first.
  case restoreAfter
  /// Do not place. We cannot see the flag's state, so we cannot promise the
  /// frame writes will not run against it.
  ///
  /// [reDefer] when a debt we had just taken on has to be handed back to a retry
  /// rather than dropped.
  case abandon(reDefer: Bool)
}

/// The whole decision, as a function of what we owe and what we can see.
///
/// - [owed]: a restore was outstanding for this app, so its *own* setting is on
///   however the flag currently reads.
/// - [read]: what the live read of the flag managed to tell us.
/// - [isOn]: what it read, meaningful only when [read] is `.ok`.
/// - [identified]: whether the app has a stable incarnation. Without one we
///   cannot record a debt, so we must not create one — see [AppIncarnation].
func euiPlan(owed: Bool, read: AXOutcome, isOn: Bool, identified: Bool) -> EUIPlan {
  switch read {
  case .unavailable:
    // The app is not talking. Anything we were carrying is still carried.
    return .abandon(reDefer: owed)
  case .gone:
    // No such attribute — the app quit, or never had one. There is nothing to
    // turn off and any debt is moot, so do not re-defer it.
    return .placeOnly
  case .ok:
    break
  }

  if isOn {
    // Someone put it back while we owed it, which discharges the debt; it is
    // simply on, and has to come off for the frame writes.
    guard identified else {
      // We could turn it off and then be unable to record that we owe it back.
      // Leaving another app's accessibility flag off forever is a worse outcome
      // than one window landing a few points wrong.
      return .placeOnly
    }
    return .disableThenRestore
  }

  // Off. Ours to put back only if we are the reason.
  return owed ? .restoreAfter : .placeOnly
}

/// What the result of a restore attempt means for the debt.
enum RestoreVerdict: Equatable {
  /// Put back, or there is nothing left to put back. Nothing further owed.
  case settled
  /// Did not land. The debt stands and the retry keeps its generation.
  case retry
}

func restoreVerdict(_ outcome: AXOutcome) -> RestoreVerdict {
  switch outcome {
  case .ok, .gone: return .settled
  case .unavailable: return .retry
  }
}

// MARK: - Who owes what

/// Who owes an app its `AXEnhancedUserInterface` back.
///
/// When the target stops answering mid-placement the restore cannot happen there
/// and then — a write into a hung app spends the full messaging timeout and
/// fails — so it is deferred to a retry.
///
/// That deferral is what this exists for. A retry that simply wrote `true` when
/// it eventually fired could land **inside a later placement**: that placement
/// would have read the `false` we left behind, concluded the app never had the
/// flag on, skipped disabling it — and then had it switched on underneath its
/// frame writes, which is exactly the state the whole dance avoids.
///
/// So the debt is owned. `claim` hands it to a starting placement and leaves any
/// scheduled retry holding a generation that is no longer current, so the retry
/// finds itself off the hook rather than racing for the write.
///
/// **What this deliberately does not record is whether the flag is currently
/// off.** Only a live read can say that — see [euiPlan], where the two are kept
/// apart.
struct EUIRestoreLedger {
  /// Who owes a restore, and which generation owns it. Absent means nothing.
  private var owed: [AppIncarnation: Int] = [:]
  /// The last generation handed out per incarnation, so no two collide. Only
  /// [owe] writes here, and only an abandoned placement calls that, so this
  /// stays a handful of entries however long Orthant runs.
  private var latest: [AppIncarnation: Int] = [:]

  /// A placement is starting on [app]. Returns whether a restore was already
  /// owed — meaning the app's own setting is *on*, whatever the flag currently
  /// reads, and this caller now carries the duty to leave it that way.
  ///
  /// Clearing the entry is what makes any scheduled retry stale: it checks
  /// [owns] before writing and will no longer match.
  mutating func claim(_ app: AppIncarnation) -> Bool {
    let wasOwed = owed[app] != nil
    owed[app] = nil
    return wasOwed
  }

  /// A placement gave up with the flag still off. Returns the generation the
  /// retry should carry.
  mutating func owe(_ app: AppIncarnation) -> Int {
    latest[app, default: 0] += 1
    let generation = latest[app]!
    owed[app] = generation
    return generation
  }

  /// Whether [generation] is still the one on the hook for [app].
  func owns(_ app: AppIncarnation, generation: Int) -> Bool {
    return owed[app] == generation
  }

  /// The debt is paid, or given up on. A no-op if it has already changed hands,
  /// so a late retry cannot clear a newer owner's entry.
  mutating func settle(_ app: AppIncarnation, generation: Int) {
    if owed[app] == generation { owed[app] = nil }
  }
}
