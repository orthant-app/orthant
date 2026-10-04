import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/windows_placement.dart';
import 'package:orthant/core/windows_window_ops.dart';

import 'support/fake_win32.dart';

const timing = PlacementTiming();
const hwnd = 0x10;
const leftHalf = PxRect(0, 0, 960, 1040);

Future<PlacementResult> place(FakeWindow w, PxRect target, FakeClock clock) =>
    placeWindow(w, hwnd, target, clock: clock, timing: timing);

/// What placement said, checked against what the window does once placement
/// has stopped looking. The fake runs on, read past every delay knob (a
/// lagging write, a late or second DPI resize), and then:
/// - the frame the trace reports as `final=` is the frame that stays;
/// - `placed` means the frame that stays is at the target's origin;
/// - a placed window is a fixed point: placing it again moves nothing, so the
///   placement had nothing left to correct when it stopped. Without this, a
///   window that the app's own late resize carried to 1.5 times its minimum
///   width passes the first two, since its origin stays within tolerance.
Future<void> expectFrameStays(
    PlacementResult r, FakeWindow w, PxRect target, FakeClock clock) async {
  for (var i = 0; i < 64; i++) {
    await clock.sleep(timing.pollMs);
    w.extendedFrame(hwnd);
  }
  final real = w.frame;
  final reported = RegExp(r'final=(\S+)').firstMatch(r.trace)?.group(1);
  if (reported != 'none') {
    expect(reported, '$real', reason: 'the frame reported is the one that stays');
  }
  if (!r.placed) return;
  expect(originMatches(real, target), isTrue,
      reason: 'placed, so the frame that stays is at the target\'s origin');
  await place(w, target, clock);
  expect(w.frame, real,
      reason: 'placing a placed window again moves nothing');
}

void main() {
  test('a normal window lands in one pass, written through its border',
      () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700));
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.placed);
    expect(w.frame, leftHalf);
    expect(w.writes.single, const PxRect(-7, 0, 967, 1047),
        reason: 'the outer rect is the target grown by the invisible border');
    expect(r.trace, contains('pass1=hit'));
    expect(r.trace, contains('restored=no'));
  });

  test('a maximized window is restored first, then measured, then placed',
      () async {
    final w = FakeWindow(
        frame: const PxRect(0, 0, 1920, 1040), border: const Border(8, 8, 8, 8))
      ..zoomed = true
      ..restoredFrame = const PxRect(100, 100, 900, 700);
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.placed);
    expect(w.restoreRequested, isTrue);
    expect(w.writes.single, const PxRect(-7, 0, 967, 1047),
        reason: 'the restored border, not the maximized one, and in one pass');
    expect(r.trace, contains('pass1=hit'));
    expect(r.trace, matches(RegExp(r'restored=\d+ms')));
  });

  test('a restore that never completes fails at its deadline, writing nothing',
      () async {
    final w = FakeWindow(frame: const PxRect(0, 0, 1920, 1040))
      ..zoomed = true
      ..hung = true;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('restored=timeout'));
    expect(w.writes, isEmpty);
    expect(clock.elapsedMs,
        lessThanOrEqualTo(timing.restoreDeadlineMs + timing.pollMs));
  });

  test('a restore that cannot be posted fails at once', () async {
    final w = FakeWindow(frame: const PxRect(0, 0, 1920, 1040))
      ..zoomed = true
      ..restorePostable = false;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('why=restore-not-posted'));
  });

  test('crossing a DPI boundary takes the correction pass, re-measured',
      () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiBorder = const Border(10, 0, 10, 10);
    const target = PxRect(1920, 0, 3360, 1560);
    final clock = FakeClock();
    final r = await place(w, target, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(w.frame, target);
    expect(w.writes, hasLength(2));
    expect(w.writes.last, const PxRect(1910, 0, 3370, 1570),
        reason: 'the second write uses the border measured after the resize');
    expect(r.trace, contains('pass1=miss'));
    expect(r.trace, contains('dpiwait=none'),
        reason: 'a miss waits for the crossing to settle too; this one had '
            'already resized, so it corrects from where pass 1 landed');
    expect(r.trace, contains('correction=hit'));
    expect(r.trace, contains('dpi=96->144'));
    await expectFrameStays(r, w, target, clock);
  });

  test('after a crossing whose first pass missed, a late resize is waited for '
      'before the correction', () async {
    // Pass 1 settles on the window's own minimum width before its
    // WM_DPICHANGED resize arrives. Corrected at once, that resize lands
    // during the correction and is taken for the correction's own movement:
    // placed, at 1.5 times the window's minimum width.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..minOuterWidth = 1214
      ..dpiResize = 1.5
      ..dpiBorder = const Border(9, 0, 9, 9)
      ..dpiResizeDelayReads = 4;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('dpi=96->144'));
    expect(r.trace, contains('pass1=miss'));
    expect(r.trace, contains('dpiwait=resized'));
    expect(r.trace, contains('correction=hit'));
    expect(w.frame, const PxRect(0, 0, 1196, 1040),
        reason: 'corrected after the resize: back at its minimum width, '
            'written through the border the resize left');
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('a window that resizes itself late after crossing is waited for, then '
      'corrected', () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiBorder = const Border(10, 0, 10, 10)
      ..dpiResizeDelayReads = 4;
    const target = PxRect(1920, 0, 3360, 1560);
    final clock = FakeClock();
    final r = await place(w, target, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('pass1=hit'));
    expect(r.trace, contains('dpiwait=resized'));
    expect(r.trace, contains('correction=hit'));
    expect(w.writes, hasLength(2));
    // Let time pass: the frame that stays is the target, not the late resize.
    for (var i = 0; i < 10; i++) {
      w.extendedFrame(hwnd);
    }
    expect(w.frame, target);
    await expectFrameStays(r, w, target, clock);
  });

  // The app resizes once, holds that frame for k reads, then resizes again.
  // - k = 2: the wait's three equal reads carry it to the second step, and
  //   the correction starts from there. This case pins only the end state: a
  //   wait that ended after two reads would have the correction's border
  //   measurement straddle the second step, which _measure re-reads.
  // - k = 3: the wait ends on the first step, and the second lands on the
  //   correction's border measurement, which _measure re-reads. This is the
  //   case that pins the wait's third equal read: a wait that ended after two
  //   would let the second step land after the correction's write, where it
  //   passes for the correction's own movement, placed at 1.5 times the
  //   target.
  for (final k in [2, 3]) {
    test('after a crossing, a resize in two steps still lands on the target '
        '(first step held for $k reads)', () async {
      final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
        ..dpiResize = 1.5
        ..dpiBorder = const Border(9, 0, 9, 9)
        ..dpiResizeDelayReads = 4
        ..dpiSecondStepReads = k;
      final clock = FakeClock();
      final r = await place(w, leftHalf, clock);
      expect(r.outcome, PlacementOutcome.placed);
      expect(r.trace, contains('pass1=hit'));
      expect(r.trace, contains('dpiwait=resized'));
      expect(r.trace, contains('final=$leftHalf'));
      expect(w.frame, leftHalf);
      await expectFrameStays(r, w, leftHalf, clock);
    });
  }

  test('a window that crosses but keeps its frame is placed after a bounded '
      'wait', () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.0;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('dpiwait=none'));
    expect(w.writes, hasLength(1));
    expect(clock.elapsedMs,
        lessThanOrEqualTo(2 * timing.pollMs + timing.dpiSettleMs + timing.pollMs));
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('a crossing whose DPI changes after pass 1 has settled is waited for, '
      'then corrected', () async {
    // Notepad's shape, measured on the W1 rig: the frame lands on the target
    // with the DPI unchanged, the DPI changes 30 to 50 ms later, and the
    // window's own 1.5x resize follows that. Pass 1 settles on two reads
    // before the change, so its DPI alone cannot see the crossing; the
    // target's monitor predicts it.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiBorder = const Border(9, 0, 9, 9)
      ..dpiFlipReads = 3
      ..dpiResizeDelayReads = 3;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    await expectFrameStays(r, w, leftHalf, clock);
    expect(r.trace, matches(RegExp(r'dpiflip=\d+ms')));
    expect(r.trace, contains('dpi=96->144'));
    expect(r.trace, contains('dpiwait=resized'));
    expect(r.trace, contains('final=$leftHalf'));
  });

  test('after a crossing, the correction has time for a slow write', () async {
    // Notepad took 220 to 290 ms, measured, to process a write posted after
    // its own DPI relayout; real polls are coarser than 15 ms. Here the
    // correction's write lands on the 21st read after it is posted (315 ms
    // at the default poll), past passDeadlineMs and well inside the
    // crossing's own deadline.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiBorder = const Border(9, 0, 9, 9)
      ..dpiResizeDelayReads = 4
      ..lagReadsAfterDpiResize = 20;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('correction=hit'));
    expect(r.trace, contains('final=$leftHalf'));
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('a window that is not per-monitor aware is not waited on for a DPI '
      'change', () async {
    // Windows scales such a window's bitmap rather than telling it, so its
    // DPI never changes and there is no crossing to wait for.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..perMonitorDpiAware = false
      ..targetMonitorDpi = 144;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, isNot(contains('dpiflip=')));
    expect(r.trace, isNot(contains(' dpi=')));
    expect(clock.elapsedMs, lessThanOrEqualTo(2 * timing.pollMs),
        reason: 'the bound of a same-display placement');
  });

  test('a hung window gets no wait for a DPI change, even with a crossing '
      'predicted', () async {
    // A window that did not move cannot have crossed.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..hung = true
      ..targetMonitorDpi = 144;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, isNot(contains('dpiflip=')));
    expect(clock.elapsedMs,
        lessThanOrEqualTo(2 * timing.passDeadlineMs + 2 * timing.pollMs));
  });

  test('a predicted crossing that never comes costs one bounded wait, and is '
      'placed as before', () async {
    // The prediction is wrong (the window's DPI never changes): the wait
    // times out, and placement goes on as for a window that did not cross.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..targetMonitorDpi = 144;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('dpiflip=timeout'));
    expect(r.trace, isNot(contains(' dpi=')));
    expect(clock.elapsedMs,
        lessThanOrEqualTo(2 * timing.pollMs + timing.dpiSettleMs));
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('a window gone while its DPI change is awaited is not placed', () async {
    // DPI reads: before pass 1, after it, then the wait's first poll, which
    // finds the window gone. A DPI of 0 is not "not crossed".
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..targetMonitorDpi = 144
      ..goneAtDpiRead = 3;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('dpiflip=unreadable'));
    expect(r.trace, contains('why=window-gone'));
  });

  test('a window gone when its DPI is read after pass 1 is not placed',
      () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..goneAtDpiRead = 2;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('why=window-gone'));
  });

  test('after a crossing, the correction waits for its own write, not an '
      'origin within tolerance', () async {
    // The crossing resizes the window to [2,0,1202,1300]: its origin is within
    // 2 px of the target's, so an origin-settle would accept it before the
    // correction's (lagging) write lands.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.25
      ..dpiBorder = const Border(9, 0, 9, 9)
      ..lagReads = 3;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('final=$leftHalf'));
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('after a crossing, a correction that never lands is not placed (resized '
      'at once)', () async {
    // Pass 1 lands at [2,0,1445,1562]: the window's own resize, whose origin is
    // within 2 px of the target's. That is not the correction landing.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiBorder = const Border(9, 0, 9, 9)
      ..hangAfterWrites = 1;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('correction=miss'));
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('after a crossing, a correction that never lands is not placed (resized '
      'late)', () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiBorder = const Border(9, 0, 9, 9)
      ..dpiResizeDelayReads = 4
      ..hangAfterWrites = 1;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('pass1=hit'));
    expect(r.trace, contains('dpiwait=resized'));
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('a window that goes away while its crossing resize is awaited is not '
      'placed', () async {
    // Six reads: placement's first look at the frame, then pass 1's three
    // (the border measurement, the poll its write lands on, the poll that
    // confirms it), so the window goes after the wait has read its unchanged
    // frame twice. Those good reads must not make a window that then vanished
    // count as one that kept its frame.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiResizeDelayReads = 50
      ..goneAfterReads = 6;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('pass1=hit'));
    expect(r.trace, contains('dpiwait=unreadable'));
  });

  test('a window that goes away after one good poll is not reported placed',
      () async {
    // Three reads: placement's first look at the frame, pass 1's border
    // measurement, and the one poll its write lands on. Every read after that
    // fails, so the frame the pass saw last belongs to a window that no longer
    // exists, and one read is not a settled frame.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..goneAfterReads = 3;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('pass1=unreadable'));
  });

  test('a hung window fails within both pass deadlines, and is not beeped at',
      () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))..hung = true;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.failed);
    expect(clock.elapsedMs,
        lessThanOrEqualTo(2 * timing.passDeadlineMs + 2 * timing.pollMs));
    expect(w.beeps, 0);
    expect(r.trace, contains('correction=miss'));
  });

  test('an elevated window is recognised by the touch, beeped at, and left '
      'alone', () async {
    final w = FakeWindow(frame: const PxRect(0, 0, 1920, 1040))
      ..zoomed = true
      ..deniedTouch = true;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.elevated);
    expect(w.beeps, 1);
    expect(w.restoreRequested, isFalse,
        reason: 'nothing is posted to a window that refuses writes');
    expect(w.writes, isEmpty);
    expect(r.trace, contains('beep=true'));
  });

  test('access denied on the real write is the elevated case too', () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..deniedWrite = true;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.elevated);
    expect(w.beeps, 1);
  });

  test('a target at its minimum size is placed by origin, without waiting out '
      'the second pass', () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..minOuterWidth = 1214;
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(w.frame.left, 0);
    expect(w.frame.width, 1200);
    expect(r.trace, contains('pass1=miss'));
    expect(r.trace, contains('correction=hit'));
    expect(clock.elapsedMs, lessThan(timing.passDeadlineMs),
        reason: 'a frame that settled at the right origin needs no more waiting');
  });

  test('a border measurement torn by the window\'s own resize is re-read, not '
      'written', () async {
    // The minimum width forces a correction pass, and the window resizes
    // itself between that pass's two border reads: the outer rect is from
    // before, the frame from after. Measured from that pair, the right and
    // bottom borders are hundreds of pixels negative, the write is garbage,
    // and origin alone would then call it placed.
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..minOuterWidth = 1214
      ..tears.add(const PxRect(-7, 0, 1607, 1347));
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(w.frame, const PxRect(0, 0, 1200, 1040),
        reason: 'its minimum width at the target height, not a size computed '
            'from a torn border');
    expect(r.trace, contains('final=${w.frame}'));
    await expectFrameStays(r, w, leftHalf, clock);
  });

  test('a border measurement that never reads the same twice writes nothing',
      () async {
    // Three tries, each torn (two outer reads apiece, so six tears): the
    // correction pass fails as unreadable rather than write from a border it
    // could not measure. A fourth try would find the resizing over and write.
    // The tears keep the target's origin, so the frame they leave would pass
    // the origin rule: the correction wrote nothing, so it is not placed.
    const a = PxRect(-7, 0, 1307, 1147);
    const b = PxRect(-7, 0, 1407, 1247);
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..minOuterWidth = 1214
      ..tears.addAll([a, b, a, b, a, b]);
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace,
        contains('correction=unreadable final=none why=frame-unreadable'));
    expect(w.writes, hasLength(1), reason: 'pass 1 wrote; the correction did not');
  });

  test('after a crossing, a correction that cannot measure the border is not '
      'placed', () async {
    // Notepad-shaped: pass 1 hits, the window's own resize follows, and then
    // every try at the correction's border measurement is torn. The tears keep
    // the window's origin within tolerance of the target, and they differ
    // from the frame the wait settled on, so they would pass for the
    // correction's own movement.
    const a = PxRect(-7, 0, 1500, 1600);
    const b = PxRect(-7, 0, 1600, 1700);
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..dpiResize = 1.5
      ..dpiBorder = const Border(9, 0, 9, 9)
      ..dpiResizeDelayReads = 4
      ..tears.addAll([a, b, a, b, a, b]);
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('dpiwait=resized'));
    expect(r.trace,
        contains('correction=unreadable final=none why=frame-unreadable'));
    expect(w.writes, hasLength(1), reason: 'pass 1 wrote; the correction did not');
  });

  test('a write that lands late is waited for, not mistaken for settled',
      () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))..lagReads = 3;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('pass1=hit'));
  });

  test('a hung window already at the target\'s origin is not reported placed',
      () async {
    // From outside, a window that never moved looks exactly like one pressed
    // against its own minimum at that spot. A false "placed" is the worse error.
    final w = FakeWindow(frame: const PxRect(0, 0, 800, 600))..hung = true;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('correction=miss'));
  });

  test('a window that moves but lands at the wrong origin is not placed',
      () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..minOuterTop = 50;
    final r = await place(w, leftHalf, FakeClock());
    expect(w.frame.top, 50, reason: 'it moved, just not where it was asked');
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('correction=miss'));
  });

  test('a slow window already at the target\'s origin is waited for in pass 1',
      () async {
    final w = FakeWindow(frame: const PxRect(0, 0, 800, 600))..lagReads = 3;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.placed);
    expect(r.trace, contains('pass1=hit'));
    expect(w.writes, hasLength(1),
        reason: 'an unchanged frame at the origin is not settled before the '
            'window has shown it responds');
  });

  test('a window already where it is asked to go is placed at once', () async {
    final w = FakeWindow(frame: leftHalf);
    final clock = FakeClock();
    final r = await place(w, leftHalf, clock);
    expect(r.outcome, PlacementOutcome.placed);
    expect(clock.elapsedMs, lessThanOrEqualTo(2 * timing.pollMs));
  });

  test('an unreadable frame is never reported as placed', () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..frameReadable = false;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('why=frame-unreadable'));
  });

  test('a window that has gone is not placed', () async {
    final w = FakeWindow(frame: const PxRect(100, 100, 900, 700))
      ..exists = false;
    final r = await place(w, leftHalf, FakeClock());
    expect(r.outcome, PlacementOutcome.failed);
    expect(r.trace, contains('why=window-gone'));
  });

  group('pxRectFor', () {
    test('rounds edges, so neighbours share an edge rather than a gap', () {
      final left = pxRectFor(const WinRect(0, 0, 960.5, 1040));
      final right = pxRectFor(const WinRect(960.5, 0, 960.5, 1040));
      expect(left.right, right.left);
      expect(left, const PxRect(0, 0, 961, 1040));
      expect(right, const PxRect(961, 0, 1921, 1040));
    });

    test('rounds half away from zero on a display left of the primary', () {
      expect(pxRectFor(const WinRect(-1920.5, 0, 960, 1040)),
          const PxRect(-1921, 0, -961, 1040));
    });
  });

  test('the tolerance is two pixels, and no more', () {
    expect(frameMatches(const PxRect(2, 2, 962, 1042), leftHalf), isTrue);
    expect(frameMatches(const PxRect(3, 0, 963, 1040), leftHalf), isFalse);
    expect(originMatches(const PxRect(2, 0, 1500, 1500), leftHalf), isTrue);
  });
}
