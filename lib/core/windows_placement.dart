import 'geometry.dart';
import 'windows_window_ops.dart';

/// How long placement waits, at most, and how often it looks. Each poll is a
/// non-blocking read, so the worst case for a placement is the restore
/// deadline plus two pass deadlines, about 1.1 s, against a target that never
/// answers. A placement that crosses a DPI boundary can add two waits of
/// [dpiSettleMs] (for the window's DPI to change, then for its own resize)
/// and runs its correction to [crossingPassDeadlineMs]: about 2.2 s in all.
class PlacementTiming {
  const PlacementTiming({
    this.pollMs = 15,
    this.restoreDeadlineMs = 500,
    this.passDeadlineMs = 300,
    this.dpiSettleMs = 300,
    this.crossingPassDeadlineMs = 800,
  });

  final int pollMs;
  final int restoreDeadlineMs;
  final int passDeadlineMs;
  final int dpiSettleMs;

  /// The correction pass's deadline after an observed DPI crossing. Measured
  /// on the W1 rig: Notepad took 220 to 290 ms to process a write posted
  /// after its own DPI relayout, which with the two reads that settle it does
  /// not fit in [passDeadlineMs]. Every other pass keeps [passDeadlineMs].
  final int crossingPassDeadlineMs;
}

enum PlacementOutcome {
  placed,

  /// Refused by UIPI: the target runs at a higher integrity level. The system
  /// beep has sounded, as macOS beeps at a fullscreen window (spec §7.4).
  elevated,

  /// Did not land: gone, unreadable, restore refused or timed out, or never
  /// arrived. Silent, as on macOS.
  failed,
}

class PlacementResult {
  const PlacementResult(this.outcome, this.trace);

  final PlacementOutcome outcome;

  /// Space-separated `key=value` tokens for the debug log, one per stage.
  final String trace;

  bool get placed => outcome == PlacementOutcome.placed;
}

/// How far a landed frame may sit from the requested one and still count:
/// macOS's two points, as physical pixels.
const int kPlacementTolerancePx = 2;

/// The rect to ask Windows for: [target]'s edges rounded to whole pixels, half
/// away from zero, so two windows placed side by side share an edge rather
/// than overlapping or leaving a gap.
PxRect pxRectFor(WinRect target) => PxRect(
      target.x.round(),
      target.y.round(),
      (target.x + target.width).round(),
      (target.y + target.height).round(),
    );

/// Whether the window arrived where asked. Origin only: a target at its own
/// minimum size never matches on size, and that is still a working snap
/// (macOS's rule, `WindowControl.originMatches`).
bool originMatches(PxRect landed, PxRect want) =>
    (landed.left - want.left).abs() <= kPlacementTolerancePx &&
    (landed.top - want.top).abs() <= kPlacementTolerancePx;

/// Origin and size. Only decides whether a correction pass runs.
bool frameMatches(PxRect landed, PxRect want) =>
    originMatches(landed, want) &&
    (landed.width - want.width).abs() <= kPlacementTolerancePx &&
    (landed.height - want.height).abs() <= kPlacementTolerancePx;

/// Move [hwnd] so the frame the user sees is [target], and say truthfully
/// whether it got there (Windows design §5.2, the apply-frame row).
///
/// 1. A write that changes nothing, first: UIPI refuses every write from a
///    lower integrity level, and says so, so an elevated target is recognised
///    before anything is posted to it, and beeped at.
/// 2. If maximized, `ShowWindowAsync(SW_RESTORE)` and a bounded wait for the
///    restore: a maximized window's invisible border is not a restored one's.
/// 3. A pass: measure the border now, write the target grown by it with an
///    asynchronous `SetWindowPos`, and poll DWM's frame until it is stable.
///    A border that cannot be measured means no write at all: a correction
///    pass that could not measure is not placed, whatever the frame is now.
/// 4. If the frame does not match, one correction pass with a re-measured
///    border. A window crossing to a monitor of another scale resizes itself
///    after the first write (`WM_DPICHANGED`), with a different border.
/// 4a. A crossing onto a monitor of another scale is predicted before pass 1,
///    from the target's monitor DPI and the window's per-monitor awareness,
///    and observed after it, when the window's DPI changes. The change can
///    trail the frame landing by tens of milliseconds, so a predicted crossing
///    whose pass 1 moved the window waits, bounded, for it. A window that did
///    not move cannot have crossed, so a hung one waits for nothing.
/// 4b. A window that crossed (its DPI changed) is given a bounded wait for
///    its own `WM_DPICHANGED` resize, whether pass 1 matched or not, and the
///    correction starts from the frame it settled on, with the longer
///    [PlacementTiming.crossingPassDeadlineMs]. Only a window that matched on
///    pass 1 and kept that frame through the wait is placed without a
///    correction.
/// 5. Placed if the final frame matches, or if the window demonstrably moved
///    and the final origin is where it was asked to be. Without a crossing,
///    moved means its frame changed at any point during the placement. After
///    a crossing it means the correction pass itself moved the window: the
///    window's own resize keeps its origin within tolerance of the target,
///    so a change before the correction says nothing about it.
///
/// Never blocks on the target and never reports a frame it did not read. A
/// window whose frame never changed and does not match is not placed even if
/// it already sits at the target's origin: from outside, a hung window there
/// and one already pressed against its own minimum size there look identical,
/// and a false "placed" is the worse error (the zero-rect lesson). The cost is
/// a silent "not placed" for re-snapping a window to the spot it already
/// occupies at its minimum size.
Future<PlacementResult> placeWindow(
  Win32Placer placer,
  int hwnd,
  PxRect target, {
  required PlacementClock clock,
  PlacementTiming timing = const PlacementTiming(),
}) async {
  final trace = StringBuffer('target=$target');
  PlacementResult done(PlacementOutcome outcome, [String? token]) {
    if (token != null) trace.write(' $token');
    return PlacementResult(outcome, trace.toString());
  }

  PlacementResult elevated() =>
      done(PlacementOutcome.elevated, 'beep=${placer.beep()}');

  if (!placer.isWindow(hwnd)) {
    return done(PlacementOutcome.failed, 'why=window-gone');
  }

  final touch = placer.setWindowPosAsync(hwnd, 0, 0, 0, 0, touchOnly: true);
  if (!touch.ok) {
    if (touch.error == kErrorAccessDenied) return elevated();
    return done(PlacementOutcome.failed, 'why=write-refused-${touch.error}');
  }

  if (placer.isZoomed(hwnd)) {
    if (!placer.restoreAsync(hwnd)) {
      return done(PlacementOutcome.failed, 'why=restore-not-posted');
    }
    final started = clock.elapsedMs;
    while (placer.isZoomed(hwnd)) {
      if (clock.elapsedMs - started >= timing.restoreDeadlineMs) {
        return done(PlacementOutcome.failed, 'restored=timeout');
      }
      await clock.sleep(timing.pollMs);
    }
    trace.write(' restored=${clock.elapsedMs - started}ms');
  } else {
    trace.write(' restored=no');
  }

  final before = placer.extendedFrame(hwnd);
  if (before == null) {
    return done(PlacementOutcome.failed, 'why=frame-unreadable');
  }
  final dpiBefore = placer.windowDpi(hwnd);
  // A crossing predicted from the target: a per-monitor-aware window bound
  // for a monitor of another DPI will be sent WM_DPICHANGED.
  final targetDpi = placer.monitorDpi(target);
  final expectCrossing = dpiBefore != 0 &&
      targetDpi != 0 &&
      targetDpi != dpiBefore &&
      placer.perMonitorAware(hwnd);

  final first = await _pass(placer, hwnd, target, before, clock, timing,
      deadlineMs: timing.passDeadlineMs, originSettles: false);
  if (first.denied) {
    trace.write(' pass1=denied');
    return elevated();
  }
  if (first.error != null) {
    return done(PlacementOutcome.failed, 'pass1=error${first.error}');
  }
  final firstLanded = first.landed;
  // Whether the window has shown it is processing our writes at all. Only
  // then can an unchanged frame at the target's origin mean "pressed against
  // its own minimum size" rather than "never moved", and only a window that
  // moved can have crossed onto another monitor.
  final responded = firstLanded != null && firstLanded != before;
  // A per-monitor-aware window that moved onto a monitor of another scale has
  // been sent WM_DPICHANGED and resizes itself in its own handler: a frame
  // that matched a moment ago is not necessarily the frame that stays. Its
  // DPI changes before that resize, which is what makes the crossing visible
  // here, but not when its frame lands: Notepad's frame landed with its DPI
  // unchanged, the DPI changed 30 to 50 ms later, and the resize followed
  // (measured on the W1 rig). Pass 1 can settle in that gap, so when a
  // crossing was predicted and pass 1 moved the window, placement waits,
  // bounded, for the change; a window that did not move waits for nothing.
  var dpiAfter = placer.windowDpi(hwnd);
  if (expectCrossing && responded && dpiAfter == dpiBefore) {
    final started = clock.elapsedMs;
    while (dpiAfter == dpiBefore &&
        clock.elapsedMs - started < timing.dpiSettleMs) {
      await clock.sleep(timing.pollMs);
      dpiAfter = placer.windowDpi(hwnd);
    }
    trace.write(dpiAfter == dpiBefore
        ? ' dpiflip=timeout'
        : dpiAfter == 0
            ? ' dpiflip=unreadable'
            : ' dpiflip=${clock.elapsedMs - started}ms');
  }
  final crossed = dpiBefore != 0 && dpiAfter != 0 && dpiAfter != dpiBefore;
  if (crossed) trace.write(' dpi=$dpiBefore->$dpiAfter');
  // Pass 1 is a hit only on the whole frame: a size miss is what the
  // correction pass is for.
  final firstHit = firstLanded != null && frameMatches(firstLanded, target);
  trace.write(' pass1=${firstLanded == null ? 'unreadable' : firstHit ? 'hit' : 'miss'}');
  // GetDpiForWindow answers 0 only for a window that is not there, whether
  // it went before the read after pass 1 or during the wait for its DPI to
  // change. That is not "did not cross", which a hit would report placed.
  if (dpiAfter == 0) {
    return done(PlacementOutcome.failed, 'final=none why=window-gone');
  }
  if (firstHit && !crossed) {
    return done(PlacementOutcome.placed, 'final=$firstLanded');
  }
  var correctFrom = firstLanded ?? before;
  if (crossed) {
    // Wait, bounded, for the window's own resize, then correct after it,
    // whatever pass 1 said: a pass that missed (settled on the app's minimum
    // size, say) can still be followed by that resize, which the correction
    // would otherwise take for its own movement. With no frame from pass 1,
    // the wait is from the frame before it, the only one there is.
    final settle = await _awaitChange(placer, hwnd, correctFrom, clock, timing);
    if (settle.kept) {
      // It kept the frame: nothing to correct after a hit.
      if (firstHit) {
        return done(PlacementOutcome.placed, 'dpiwait=none final=$firstLanded');
      }
      trace.write(' dpiwait=none');
    } else {
      final resized = settle.frame;
      if (resized == null) {
        return done(PlacementOutcome.failed,
            'dpiwait=unreadable final=none why=frame-unreadable');
      }
      trace.write(' dpiwait=resized');
      correctFrom = resized;
    }
  }

  // Origin settles the correction only from a window that [responded]. After
  // a crossing, the starting frame is the one the window settled on after
  // it, and an origin within tolerance of the target there is not this
  // pass's write landing, so the pass waits for it, and for longer: a window
  // still busy with its DPI relayout can take a while to get to the write.
  final second = await _pass(placer, hwnd, target, correctFrom, clock, timing,
      deadlineMs:
          crossed ? timing.crossingPassDeadlineMs : timing.passDeadlineMs,
      originSettles: responded && !crossed);
  if (second.denied) {
    trace.write(' correction=denied');
    return elevated();
  }
  if (second.unmeasured) {
    // The correction wrote nothing, so whatever the window's frame is now is
    // its own doing: after a crossing its own resize would pass for this
    // pass's movement, and without one pass 1's response, or any change of
    // its own since the placement began, would. An unmeasured pass 1 is
    // different: it wrote nothing either, and the correction is a genuine
    // retry.
    return done(PlacementOutcome.failed,
        'correction=unreadable final=none why=frame-unreadable');
  }
  final landed = second.landed ?? placer.extendedFrame(hwnd);
  // Origin is enough only from a window that moved, macOS's rule for a target
  // at its own minimum size; a whole-frame match is enough from any window.
  // After a crossing the movement has to be this pass's: the window's own DPI
  // resize keeps its origin within tolerance of the target, so pass 1's change
  // says nothing about whether the correction landed.
  final moved = crossed
      ? (landed != null && landed != correctFrom)
      : responded || (landed != null && landed != before);
  final arrived = landed != null &&
      (frameMatches(landed, target) || (moved && originMatches(landed, target)));
  trace.write(' correction=${second.error != null ? 'error${second.error}' : landed == null ? 'unreadable' : arrived ? 'hit' : 'miss'}');
  if (landed == null) {
    return done(PlacementOutcome.failed, 'final=none why=frame-unreadable');
  }
  return done(arrived ? PlacementOutcome.placed : PlacementOutcome.failed,
      'final=$landed');
}

/// What [hwnd]'s frame did while a crossing's own resize was awaited: kept
/// [from] to the end ([kept]), or ended on [frame], which is null when the
/// last read failed.
typedef _Settle = ({bool kept, PxRect? frame});

/// Waits, at most [PlacementTiming.dpiSettleMs], for [hwnd] to leave [from]
/// and hold a new frame for three reads in a row: the app's own layout after
/// WM_DPICHANGED can take more than one step, so two equal reads are not
/// enough here.
Future<_Settle> _awaitChange(Win32Placer placer, int hwnd, PxRect from,
    PlacementClock clock, PlacementTiming timing) async {
  final started = clock.elapsedMs;
  PxRect? last = from;
  PxRect? previous;
  var repeats = 0;
  while (clock.elapsedMs - started < timing.dpiSettleMs) {
    await clock.sleep(timing.pollMs);
    final now = placer.extendedFrame(hwnd);
    last = now;
    if (now == null || now == from) {
      previous = null;
      repeats = 0;
      continue;
    }
    repeats = now == previous ? repeats + 1 : 0;
    if (repeats >= 2) return (kept: false, frame: now);
    previous = now;
  }
  return last == from ? (kept: true, frame: from) : (kept: false, frame: last);
}

class _Pass {
  const _Pass(
      {this.landed, this.denied = false, this.error, this.unmeasured = false});

  /// The frame the pass settled on, or the last one it read; null if DWM
  /// answered none of its reads, or not the last one, and null when the pass
  /// could not measure the border, in which case it wrote nothing.
  final PxRect? landed;
  final bool denied;
  final int? error;

  /// Nothing was written, because the border could not be measured: a read
  /// failed, or no outer rect and frame agreed in [_measure]'s three tries.
  final bool unmeasured;
}

/// [hwnd]'s outer rect and DWM frame as one consistent pair, or null if a read
/// fails or no pair is consistent in three tries.
///
/// The border is the difference of two reads, and a window that resizes
/// itself between them (its own WM_DPICHANGED layout, say) tears it: an outer
/// rect from before and a frame from after give borders hundreds of pixels
/// off, and a write built on them is garbage that origin alone can call
/// placed. So the outer rect is read on both sides of the frame, and the pair
/// counts only when the two agree. A check on the deltas could not do this:
/// with the outer rect read first, only a resize that grows the window makes
/// one negative.
({PxRect outer, PxRect inner})? _measure(Win32Placer placer, int hwnd) {
  for (var tries = 0; tries < 3; tries++) {
    final outer = placer.windowRect(hwnd);
    final inner = placer.extendedFrame(hwnd);
    if (outer == null || inner == null) return null;
    if (placer.windowRect(hwnd) == outer) return (outer: outer, inner: inner);
  }
  return null;
}

Future<_Pass> _pass(Win32Placer placer, int hwnd, PxRect target,
    PxRect before, PlacementClock clock, PlacementTiming timing,
    {required int deadlineMs, required bool originSettles}) async {
  final measured = _measure(placer, hwnd);
  if (measured == null) return const _Pass(unmeasured: true);
  final (:outer, :inner) = measured;
  // The invisible border, per edge, as it is right now: it differs between a
  // maximized and a restored window and again across a DPI boundary (spec
  // §5.7), which is why each pass measures it afresh.
  final dl = inner.left - outer.left;
  final dt = inner.top - outer.top;
  final dr = outer.right - inner.right;
  final db = outer.bottom - inner.bottom;
  final set = placer.setWindowPosAsync(hwnd, target.left - dl,
      target.top - dt, target.width + dl + dr, target.height + dt + db);
  if (!set.ok) {
    return set.error == kErrorAccessDenied
        ? const _Pass(denied: true)
        : _Pass(error: set.error);
  }
  // Settled means two equal reads in a row that moved off the frame the pass
  // started from, or that match the target, or (only once the window has
  // shown it responds, [originSettles]) sit at the target's origin. Otherwise
  // an unchanged frame is not settled: the target may not have processed the
  // asynchronous write yet, and a hung one never will, which the deadline
  // decides. Two reads 15 ms apart can in principle both catch a frame just
  // before a WM_DPICHANGED resize, which is why [placeWindow] waits for a
  // crossing's own resize before it trusts a pass; the acceptance's
  // independent read-back, later, is still the backstop for an app that
  // resizes more than once.
  final started = clock.elapsedMs;
  PxRect? previous;
  PxRect? last;
  while (clock.elapsedMs - started < deadlineMs) {
    await clock.sleep(timing.pollMs);
    final now = placer.extendedFrame(hwnd);
    if (now == null) {
      // A failed read clears what the pass last saw, too: a window that
      // vanished after one good poll has landed nowhere.
      previous = null;
      last = null;
      continue;
    }
    last = now;
    if (now == previous &&
        (now != before ||
            frameMatches(now, target) ||
            (originSettles && originMatches(now, target)))) {
      return _Pass(landed: now);
    }
    previous = now;
  }
  return _Pass(landed: last);
}
