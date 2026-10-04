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
    final r = await place(w, target, FakeClock());
    expect(r.outcome, PlacementOutcome.placed);
    expect(w.frame, target);
    expect(w.writes, hasLength(2));
    expect(w.writes.last, const PxRect(1910, 0, 3370, 1570),
        reason: 'the second write uses the border measured after the resize');
    expect(r.trace, contains('pass1=miss'));
    expect(r.trace, contains('correction=hit'));
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
