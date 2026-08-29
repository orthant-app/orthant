import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/shortcuts/custom_region.dart';

const _leftTwoThirds = CustomRegion(
  id: 'r7fk2',
  name: 'Left ⅔',
  cols: 6,
  rows: 6,
  c0: 0,
  c1: 3,
  r0: 0,
  r1: 5,
);

/// A valid region, so each test can spoil exactly one field.
const _valid = CustomRegion(
  id: 'a',
  name: 'n',
  cols: 6,
  rows: 6,
  c0: 0,
  c1: 1,
  r0: 0,
  r1: 1,
);

void main() {
  test('has value equality', () {
    expect(_leftTwoThirds, _leftTwoThirds.copyWith());
    expect(_leftTwoThirds == _leftTwoThirds.copyWith(c1: 2), isFalse);
  });

  test('round-trips through json', () {
    expect(CustomRegion.tryFromJson(_leftTwoThirds.toJson()), _leftTwoThirds);
  });

  test('accepts a single-row denominator', () {
    // cols:3 rows:1 is left two-thirds full height. kMinGridAxis is 2 and
    // governs the overlay grid; a region's denominator is arithmetic.
    final r = CustomRegion.tryFromJson(const CustomRegion(
      id: 'a',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    ).toJson());
    expect(r, isNotNull);
    expect(r!.rows, 1);
  });

  test('rejects an axis outside 1..12', () {
    for (final bad in [0, -1, 13]) {
      expect(CustomRegion.tryFromJson({..._valid.toJson(), 'cols': bad}), isNull,
          reason: 'cols: $bad');
      expect(CustomRegion.tryFromJson({..._valid.toJson(), 'rows': bad}), isNull,
          reason: 'rows: $bad');
    }
  });

  test('rejects a block outside its own grid', () {
    Map<String, dynamic> withField(String k, int v) =>
        {..._valid.toJson(), k: v};
    expect(CustomRegion.tryFromJson(withField('c1', 6)), isNull); // == cols
    expect(CustomRegion.tryFromJson(withField('c0', -1)), isNull);
    expect(CustomRegion.tryFromJson(withField('c0', 3)), isNull); // c0 > c1
    expect(CustomRegion.tryFromJson(withField('r1', 6)), isNull);
    expect(CustomRegion.tryFromJson(withField('r0', 3)), isNull);
  });

  test('rejects an empty id or a blank name', () {
    Map<String, dynamic> withField(String k, String v) =>
        {..._valid.toJson(), k: v};
    expect(CustomRegion.tryFromJson(withField('id', '')), isNull);
    expect(CustomRegion.tryFromJson(withField('name', '   ')), isNull);
  });

  test('rejects malformed entries without throwing', () {
    expect(CustomRegion.tryFromJson(null), isNull);
    expect(CustomRegion.tryFromJson('nope'), isNull);
    expect(CustomRegion.tryFromJson(const {'id': 'a'}), isNull);
    expect(
      CustomRegion.tryFromJson({..._valid.toJson(), 'cols': '6'}),
      isNull,
      reason: 'a stringified int is what a hand-edited file looks like',
    );
  });

  group('suggestRegionName', () {
    String name(int cols, int rows, int c0, int c1, int r0, int r1) =>
        suggestRegionName(
            cols: cols, rows: rows, c0: c0, c1: c1, r0: r0, r1: r1);

    test('names full-height spans from the left or right edge', () {
      expect(name(6, 6, 0, 3, 0, 5), 'Left ⅔');
      expect(name(6, 6, 0, 2, 0, 5), 'Left ½');
      expect(name(6, 6, 2, 5, 0, 5), 'Right ⅔');
      expect(name(3, 1, 0, 1, 0, 0), 'Left ⅔'); // rows:1 is still full height
    });

    test('names full-width spans from the top or bottom edge', () {
      expect(name(6, 6, 0, 5, 0, 2), 'Top ½');
      expect(name(6, 6, 0, 5, 3, 5), 'Bottom ½');
      expect(name(4, 4, 0, 3, 0, 0), 'Top ¼');
    });

    test('names the whole screen', () {
      expect(name(6, 6, 0, 5, 0, 5), 'Full screen');
    });

    test('falls back for a shape with no edge word', () {
      expect(name(6, 6, 1, 3, 1, 3), 'Custom region');
      expect(name(6, 6, 1, 4, 0, 5), 'Custom region'); // full height, no edge
    });

    test('reduces fractions and falls back to n/d for odd ones', () {
      expect(name(12, 12, 0, 7, 0, 11), 'Left ⅔'); // 8/12
      expect(name(7, 7, 0, 2, 0, 6), 'Left 3/7');
    });
  });
  group('refineForEditing', () {
    // Deliberately coarse: 3 columns, 1 row — "Left ⅔, full height" expressed
    // as economically as it can be, which is the shape that cannot be reshaped
    // vertically without refinement.
    const coarse = CustomRegion(
      id: 'c', name: 'Left ⅔',
      cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0,
    );

    test('a coarser axis is refined to a compatible multiple', () {
      // 3 x 1 opened while the live grid is 6 x 6.
      final r = refineForEditing(coarse, gridCols: 6, gridRows: 6);
      expect(r.cols, 6);
      expect(r.rows, 6);
      expect(r.c0, 0);
      expect(r.c1, 3, reason: 'columns 0..1 of 3 is columns 0..3 of 6');
      expect(r.r0, 0);
      expect(r.r1, 5, reason: 'the single row becomes all six');
    });

    test('picks a multiple even when the live grid is not one', () {
      // 4 is not a multiple of 3; 6 is the first that is.
      final r = refineForEditing(coarse, gridCols: 4, gridRows: 4);
      expect(r.cols, 6);
      expect(r.rows, 4);
      expect(r.c1, 3);
      expect(r.r1, 3);
    });

    test('leaves an already-fine axis alone', () {
      const wide = CustomRegion(
        id: 'w', name: 'w', cols: 6, rows: 6, c0: 1, c1: 4, r0: 2, r1: 3,
      );
      expect(refineForEditing(wide, gridCols: 4, gridRows: 4), wide);
    });

    test('gives up rather than exceed the maximum denominator', () {
      const twelve = CustomRegion(
        id: 't', name: 't', cols: 12, rows: 1, c0: 0, c1: 5, r0: 0, r1: 0,
      );
      final r = refineForEditing(twelve, gridCols: 8, gridRows: 8);
      expect(r.cols, 12, reason: 'the next multiple of 12 is 24, over the cap');
      expect(r.rows, 8, reason: 'rows can still refine 1 -> 8');
    });

    test('never moves the window it describes, at any gap', () {
      // The property that matters. A refined region must place identically.
      //
      // **Including at a gap large enough to be clamped**, which is where this
      // used to fail: a grid-wide clamp read the *denominators*, so twelfths cut
      // a 64 pt gap that thirds kept and a refined region landed 40 pt to the
      // left. Running only at the default zero gap hid it completely —
      // `gapForPlacement` returns early there, so the fractions were the whole
      // story and the clamp was never exercised. A property test at the default
      // value tests the branch that does nothing.
      const frame = WinRect(0, 0, 1440, 800);
      for (final gap in [0.0, 8.0, 64.0]) {
        for (final live in [2, 3, 4, 5, 6, 7, 8, 12]) {
          final r = refineForEditing(coarse, gridCols: live, gridRows: live);
          final refined = gridBlock(frame,
              cols: r.cols, rows: r.rows,
              c0: r.c0, c1: r.c1, r0: r.r0, r1: r.r1, gap: gap);
          final stored = gridBlock(frame,
              cols: coarse.cols, rows: coarse.rows,
              c0: coarse.c0, c1: coarse.c1, r0: coarse.r0, r1: coarse.r1,
              gap: gap);
          final where = 'live $live, gap $gap';
          // Within a tolerance, not exactly: dividing 800 by 7 and multiplying
          // back gives 800.0000000000001. Refinement is exact in *integers* —
          // the same fraction, differently written — and the only difference is
          // which divisor the double arithmetic went through. A 1e-9 pt window
          // is the same window.
          expect(refined.x, closeTo(stored.x, 1e-9), reason: 'x, $where');
          expect(refined.y, closeTo(stored.y, 1e-9), reason: 'y, $where');
          expect(refined.width, closeTo(stored.width, 1e-9),
              reason: 'width, $where');
          expect(refined.height, closeTo(stored.height, 1e-9),
              reason: 'height, $where');
        }
      }
    });

    test('a vertical reshape leaves the columns alone, even at 64 pt', () {
      // The defect this all came from, stated end to end. 1440 x 800 is about
      // what a 13" display leaves visible; 64 pt is the largest gap offered.
      const frame = WinRect(0, 0, 1440, 800);
      final editing = refineForEditing(coarse, gridCols: 12, gridRows: 12);
      final reshaped = editing.copyWith(r1: 5); // drag the bottom edge up

      WinRect place(CustomRegion r) => gridBlock(frame,
          cols: r.cols, rows: r.rows,
          c0: r.c0, c1: r.c1, r0: r.r0, r1: r.r1, gap: 64);

      expect(place(reshaped).x, closeTo(place(coarse).x, 1e-9));
      expect(place(reshaped).width, closeTo(place(coarse).width, 1e-9));
      // Not vacuous: the drag really did change the height.
      expect(place(reshaped).height, lessThan(place(coarse).height));
    });

    test('the result is always a region the loader would accept', () {
      for (final live in [1, 2, 3, 5, 7, 11, 12]) {
        final r = refineForEditing(coarse, gridCols: live, gridRows: live);
        expect(CustomRegion.tryFromJson(r.toJson()), isNotNull,
            reason: 'live grid $live produced an invalid region');
      }
    });
  });
}
