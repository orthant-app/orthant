import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/settings/settings.dart';

void main() {
  test('WinRect has value equality', () {
    expect(const WinRect(1, 2, 3, 4), const WinRect(1, 2, 3, 4));
    expect(const WinRect(1, 2, 3, 4) == const WinRect(0, 2, 3, 4), isFalse);
  });

  test('leftHalf halves the width, keeps origin and height', () {
    const frame = WinRect(100, 200, 1440, 900);
    expect(leftHalf(frame), const WinRect(100, 200, 720, 900));
  });

  test('gridBlock with no gap: left half of a 2x2 grid', () {
    const f = WinRect(0, 0, 1440, 900);
    expect(gridBlock(f, cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1),
        const WinRect(0, 0, 720, 900));
  });

  test('gridBlock with no gap: top-right quarter', () {
    const f = WinRect(0, 0, 1440, 900);
    expect(gridBlock(f, cols: 2, rows: 2, c0: 1, c1: 1, r0: 0, r1: 0),
        const WinRect(720, 0, 720, 450));
  });

  test('gridBlock with gap insets edges and gutters', () {
    const f = WinRect(0, 0, 1000, 1000);
    // gap 10: usable = 980x980 at (10,10); cell = (980-10)/2 = 485
    expect(gridBlock(f, cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, gap: 10),
        const WinRect(10, 10, 485, 485));
    // right column starts at 10 + 485 + 10 = 505
    expect(gridBlock(f, cols: 2, rows: 2, c0: 1, c1: 1, r0: 0, r1: 0, gap: 10),
        const WinRect(505, 10, 485, 485));
  });

  test('gridBlock spanning both columns (maximize) with gap = frame minus edge', () {
    const f = WinRect(0, 0, 1000, 1000);
    expect(gridBlock(f, cols: 2, rows: 2, c0: 0, c1: 1, r0: 0, r1: 1, gap: 10),
        const WinRect(10, 10, 980, 980));
  });

  group('gap clamping', () {
    // A 13" MacBook's visible frame — the smallest display this ships on, and
    // the one the settings bounds have to survive.
    const laptop = WinRect(0, 25, 1280, 775);

    test('the settings bounds cannot produce a non-positive cell', () {
      // Rows, columns and gap size are validated independently of each other
      // (Settings.clamped), so nothing upstream knows that 12 rows and a 64 pt
      // gap do not both fit on 775 points. Every combination the steppers
      // offer, on the smallest display: 12 x 12 at 64 pt used to give a cell
      // height of -4.75.
      for (var cols = kMinGridAxis; cols <= kMaxGridAxis; cols++) {
        for (var rows = kMinGridAxis; rows <= kMaxGridAxis; rows++) {
          for (var gap = 0; gap <= kMaxGapSize; gap++) {
            final r = gridBlock(laptop,
                cols: cols,
                rows: rows,
                c0: 0,
                c1: 0,
                r0: 0,
                r1: 0,
                gap: gap.toDouble());
            expect(r.width, greaterThan(0),
                reason: '$cols x $rows at ${gap}pt gave width ${r.width}');
            expect(r.height, greaterThan(0),
                reason: '$cols x $rows at ${gap}pt gave height ${r.height}');
          }
        }
      }
    });

    test('a block stays inside the frame at every allowed setting', () {
      // Clamping the gap must not push the far edge past the display either.
      for (var cols = kMinGridAxis; cols <= kMaxGridAxis; cols++) {
        for (var rows = kMinGridAxis; rows <= kMaxGridAxis; rows++) {
          final r = gridBlock(laptop,
              cols: cols,
              rows: rows,
              c0: 0,
              c1: cols - 1,
              r0: 0,
              r1: rows - 1,
              gap: kMaxGapSize.toDouble());
          expect(r.x, greaterThanOrEqualTo(laptop.x));
          expect(r.y, greaterThanOrEqualTo(laptop.y));
          expect(r.x + r.width, lessThanOrEqualTo(laptop.x + laptop.width + 0.001));
          expect(r.y + r.height, lessThanOrEqualTo(laptop.y + laptop.height + 0.001));
        }
      }
    });

    test('a gap that fits is used exactly as given', () {
      // The clamp is a backstop for the extremes, not a general re-scaling —
      // every ordinary configuration must come out byte-identical.
      expect(effectiveGapFor(laptop, cols: 6, rows: 6, gap: 8), 8);
      expect(effectiveGapFor(laptop, cols: 2, rows: 2, gap: 64), 64);
      expect(gridBlock(const WinRect(0, 0, 1000, 1000),
              cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, gap: 10),
          const WinRect(10, 10, 485, 485));
    });

    test('an impossible gap is reduced, not rejected', () {
      // 12 rows on 775 points cannot afford 64 pt gutters. Shrinking the gap
      // keeps the grid usable; refusing the setting would leave the user with a
      // stepper that silently does nothing.
      final g = effectiveGapFor(laptop, cols: 12, rows: 12, gap: 64);
      expect(g, lessThan(64));
      expect(g, greaterThan(0));
    });

    test('the grid-wide clamp is the placement clamp at its worst case', () {
      // Not a coincidence to be maintained by hand — `effectiveGapFor` is
      // defined as this call. Asserted anyway, because the settings preview
      // reads it and would silently start drawing a gap no placement uses if
      // the two ever came apart.
      for (final n in [2, 4, 6, 8, 12]) {
        for (final gap in [0.0, 8.0, 64.0]) {
          expect(
            effectiveGapFor(laptop, cols: n, rows: n, gap: gap),
            gapForPlacement(laptop,
                cols: n, rows: n, c0: 0, c1: 0, r0: 0, r1: 0, gap: gap),
            reason: '$n x $n at $gap',
          );
        }
      }
    });

    test('a bigger block keeps more of the gap it asked for', () {
      // The clamp exists to keep *the window that lands* off the 40 pt floor.
      // Measuring the grid instead protected the smallest cell the user could
      // have picked rather than the block they did, so a 12 x 12 grid cut 64 pt
      // to 24.6 even for a half-screen window.
      const frame = WinRect(0, 0, 1440, 800);
      double gapFor(int c0, int c1, int r0, int r1) => gapForPlacement(frame,
          cols: 12, rows: 12, c0: c0, c1: c1, r0: r0, r1: r1, gap: 64);

      expect(gapFor(0, 5, 0, 11), 64, reason: 'a left half is not at risk');
      expect(gapFor(0, 0, 0, 0), closeTo(320 / 13, 1e-9),
          reason: 'one cell of twelfths still needs the clamp');
      expect(gapFor(0, 0, 0, 0), lessThan(gapFor(0, 5, 0, 11)));
    });

    test('the floor holds for the block, whatever the grid', () {
      // The guarantee the clamp exists for, asserted against every block of a
      // 12 x 12 grid on a frame where the request cannot be met in full.
      const frame = WinRect(0, 0, 1440, 800);
      for (var c0 = 0; c0 < 12; c0++) {
        for (var c1 = c0; c1 < 12; c1++) {
          final r = gridBlock(frame,
              cols: 12, rows: 12, c0: c0, c1: c1, r0: 0, r1: 0, gap: 64);
          expect(r.width, greaterThanOrEqualTo(kMinPlacedCell - 1e-9),
              reason: 'columns $c0..$c1');
          expect(r.height, greaterThanOrEqualTo(kMinPlacedCell - 1e-9),
              reason: 'columns $c0..$c1');
          expect(r.x + r.width, lessThanOrEqualTo(frame.width + 1e-9));
        }
      }
    });

    test('placement does not depend on the grid a block is written on', () {
      // The invariant the whole gap clamp had to be rewritten for: expand
      // gridBlock and `cols` cancels, so the only way it can reach the result
      // is through the clamp. Three spellings of "left two-thirds, full
      // height", at a gap the old grid-wide clamp treated differently.
      const frame = WinRect(0, 0, 1440, 800);
      WinRect place(int cols, int rows, int c1, int r1) => gridBlock(frame,
          cols: cols, rows: rows, c0: 0, c1: c1, r0: 0, r1: r1, gap: 64);

      final thirds = place(3, 1, 1, 0);
      expect(place(6, 6, 3, 5).width, closeTo(thirds.width, 1e-9));
      expect(place(6, 6, 3, 5).x, closeTo(thirds.x, 1e-9));
      expect(place(12, 12, 7, 11).width, closeTo(thirds.width, 1e-9));
      expect(place(12, 12, 7, 11).x, closeTo(thirds.x, 1e-9));
      // And it is the *requested* gap that survives, not a clamped one.
      expect(thirds.x, 64);
    });

    test('a block loses gap only when it would otherwise go under the floor',
        () {
      // The exact boundary of the one thing block-measured clamping gives up.
      // Two blocks sit exactly one gap apart when they *share* a gap, so a seam
      // can only be wrong beside a window that had to be shrunk to the 40 pt
      // floor — a placement the user's own settings made impossible, not a
      // rounding error. Everything else keeps the gap it asked for.
      const frame = WinRect(0, 0, 1440, 800);
      const g = 64.0;
      // The closed form, unclamped: w = f*W - g*(f + 1).
      double sizeAt(double extent, int span) =>
          (span / 12) * extent - g * (span / 12 + 1);

      var kept = 0, reduced = 0;
      for (var c0 = 0; c0 < 12; c0++) {
        for (var c1 = c0; c1 < 12; c1++) {
          for (var r0 = 0; r0 < 12; r0++) {
            for (var r1 = r0; r1 < 12; r1++) {
              final used = gapForPlacement(frame,
                  cols: 12, rows: 12, c0: c0, c1: c1, r0: r0, r1: r1, gap: g);
              final fits = sizeAt(1440, c1 - c0 + 1) >= kMinPlacedCell &&
                  sizeAt(800, r1 - r0 + 1) >= kMinPlacedCell;
              final where = 'cols $c0..$c1, rows $r0..$r1';
              if (fits) {
                expect(used, g, reason: 'gap was reduced for $where, which fits');
                kept++;
              } else {
                expect(used, lessThan(g), reason: 'gap was kept for $where');
                reduced++;
              }
            }
          }
        }
      }
      // Neither branch is empty, so the loop is really testing both.
      expect(kept, greaterThan(0));
      expect(reduced, greaterThan(0));
    });

    test('windows that keep their gap tile exactly', () {
      // The corollary a user actually sees: two windows side by side sit one
      // gap apart, at every split of the grid.
      const frame = WinRect(0, 0, 1440, 800);
      for (final split in [1, 2, 3, 4, 6, 8, 11]) {
        final left = gridBlock(frame,
            cols: 12, rows: 12, c0: 0, c1: split - 1, r0: 0, r1: 11, gap: 64);
        final right = gridBlock(frame,
            cols: 12, rows: 12, c0: split, c1: 11, r0: 0, r1: 11, gap: 64);
        expect(right.x - (left.x + left.width), closeTo(64, 1e-9),
            reason: 'split at $split');
      }
    });

    test('a frame too small for any gap falls back to none', () {
      // Not reachable from a real display, but the formula must not answer
      // with a negative gap and reinvent the bug one level down.
      const tiny = WinRect(0, 0, 200, 120);
      expect(effectiveGapFor(tiny, cols: 12, rows: 12, gap: 64), 0);
      final r = gridBlock(tiny,
          cols: 12, rows: 12, c0: 0, c1: 0, r0: 0, r1: 0, gap: 64);
      expect(r.width, greaterThan(0));
      expect(r.height, greaterThan(0));
    });
  });

  group('screenContaining', () {
    // Laptop at origin, external to its right (top-left space).
    const laptop = WinRect(0, 0, 1512, 945);
    const external = WinRect(1512, 0, 2560, 1440);
    const screens = [laptop, external];

    test('picks the screen a window sits entirely within', () {
      expect(screenContaining(const WinRect(100, 100, 400, 300), screens),
          laptop);
      expect(screenContaining(const WinRect(1600, 200, 800, 600), screens),
          external);
    });

    test('a straddling window belongs to the screen it mostly occupies', () {
      // 300pt on the laptop, 700pt on the external.
      expect(screenContaining(const WinRect(1212, 100, 1000, 500), screens),
          external);
      // 700pt on the laptop, 300pt on the external.
      expect(screenContaining(const WinRect(812, 100, 1000, 500), screens),
          laptop);
    });

    test('falls back to the first screen when nothing overlaps', () {
      expect(screenContaining(const WinRect(9000, 9000, 100, 100), screens),
          laptop);
    });

    test('handles a single screen and an empty list', () {
      expect(screenContaining(const WinRect(10, 10, 100, 100), const [laptop]),
          laptop);
      expect(screenContaining(const WinRect(10, 10, 100, 100), const []),
          isNull);
    });
  });
}
