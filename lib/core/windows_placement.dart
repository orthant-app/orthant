import 'geometry.dart';
import 'windows_window_ops.dart';

/// How long placement waits, at most, and how often it looks. Each poll is a
/// non-blocking read, so the worst case for a placement is the restore
/// deadline plus two pass deadlines, about 1.1 s, against a target that never
/// answers.
class PlacementTiming {
  const PlacementTiming({
    this.pollMs = 15,
    this.restoreDeadlineMs = 500,
    this.passDeadlineMs = 300,
  });

  final int pollMs;
  final int restoreDeadlineMs;
  final int passDeadlineMs;
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
/// 4. If the frame does not match, one correction pass with a re-measured
///    border. A window crossing to a monitor of another scale resizes itself
///    after the first write (`WM_DPICHANGED`), with a different border.
/// 5. Placed if the final frame matches, or if the window demonstrably
///    responded (its frame changed during the placement) and the final
///    origin is where it was asked to be.
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

  final first = await _pass(placer, hwnd, target, before, clock, timing,
      originSettles: false);
  if (first.denied) {
    trace.write(' pass1=denied');
    return elevated();
  }
  if (first.error != null) {
    return done(PlacementOutcome.failed, 'pass1=error${first.error}');
  }
  final firstLanded = first.landed;
  // Pass 1 is a hit only on the whole frame: a size miss is what the
  // correction pass is for.
  final firstHit = firstLanded != null && frameMatches(firstLanded, target);
  trace.write(' pass1=${firstLanded == null ? 'unreadable' : firstHit ? 'hit' : 'miss'}');
  if (firstHit) return done(PlacementOutcome.placed, 'final=$firstLanded');

  // Whether the window has shown it is processing our writes at all. Only
  // then can an unchanged frame at the target's origin mean "pressed against
  // its own minimum size" rather than "never moved".
  final responded = firstLanded != null && firstLanded != before;
  final second = await _pass(
      placer, hwnd, target, firstLanded ?? before, clock, timing,
      originSettles: responded);
  if (second.denied) {
    trace.write(' correction=denied');
    return elevated();
  }
  final landed = second.landed ?? placer.extendedFrame(hwnd);
  // Origin is enough only from a window that moved, macOS's rule for a target
  // at its own minimum size; a whole-frame match is enough from any window.
  final moved = responded || (landed != null && landed != before);
  final arrived = landed != null &&
      (frameMatches(landed, target) || (moved && originMatches(landed, target)));
  trace.write(' correction=${second.error != null ? 'error${second.error}' : landed == null ? 'unreadable' : arrived ? 'hit' : 'miss'}');
  if (landed == null) {
    return done(PlacementOutcome.failed, 'final=none why=frame-unreadable');
  }
  return done(arrived ? PlacementOutcome.placed : PlacementOutcome.failed,
      'final=$landed');
}

class _Pass {
  const _Pass({this.landed, this.denied = false, this.error});

  /// The frame the pass settled on, or the last one it read; null if DWM
  /// answered none of its reads.
  final PxRect? landed;
  final bool denied;
  final int? error;
}

Future<_Pass> _pass(Win32Placer placer, int hwnd, PxRect target,
    PxRect before, PlacementClock clock, PlacementTiming timing,
    {required bool originSettles}) async {
  final outer = placer.windowRect(hwnd);
  final inner = placer.extendedFrame(hwnd);
  if (outer == null || inner == null) return const _Pass();
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
  // before a WM_DPICHANGED resize; the acceptance reads every frame back
  // independently, later, for that reason.
  final started = clock.elapsedMs;
  PxRect? previous;
  PxRect? last;
  while (clock.elapsedMs - started < timing.passDeadlineMs) {
    await clock.sleep(timing.pollMs);
    final now = placer.extendedFrame(hwnd);
    if (now == null) {
      previous = null;
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
