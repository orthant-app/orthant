import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/grid_preview.dart';

void main() {
  GridPreviewPainter painter({int cols = 6, int rows = 6, double gap = 0}) =>
      GridPreviewPainter(
          cols: cols, rows: rows, gap: gap, cell: const Color(0xFF000000));

  // A pixel golden would be brittle across platforms and would mostly assert
  // anti-aliasing. The repaint contract is the part that can actually break:
  // a preview that does not redraw is a settings control with no feedback,
  // which is the whole reason this widget exists.
  test('repaints when the grid changes', () {
    expect(painter().shouldRepaint(painter(cols: 7)), isTrue);
    expect(painter().shouldRepaint(painter(rows: 7)), isTrue);
  });

  test('repaints when the gap changes', () {
    expect(painter().shouldRepaint(painter(gap: 8)), isTrue);
  });

  test('does not repaint when nothing changed', () {
    expect(painter().shouldRepaint(painter()), isFalse);
  });

  testWidgets('an extreme grid still paints rather than throwing',
      (tester) async {
    // The store clamps to 12, but a painter that divided by zero — or produced
    // negative cells at a large gap — would take the whole pane down. Cheaper
    // to be total than to rely on the clamp being upstream forever.
    for (final spec in const [(2, 2, 0.0), (12, 12, 0.0), (12, 12, 64.0)]) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: GridPreview(cols: spec.$1, rows: spec.$2, gap: spec.$3),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'grid $spec');
    }
  });

  group('the preview shows a gap the grid can keep', () {
    // The *single-cell* gap — `effectiveGapFor` — which is the right one for a
    // picture of every cell at once, and deliberately not what most placements
    // get: `gapForPlacement` measures the block, so a bigger selection keeps
    // more. Hence the pane's "up to N pt gaps".
    //
    // Reduced rather than drawn literally, because this painter's old response
    // to an impossible gap was to draw *nothing*, which reads as "this grid is
    // broken" for a grid that places windows perfectly well.
    test('an ordinary gap is drawn to scale, untouched', () {
      // 8 pt of a 1600 pt display, drawn 176 pt wide.
      expect(painter(gap: 8).scaledGapFor(GridPreview.size),
          closeTo(8 * 176 / 1600, 0.001));
    });

    test('an impossible gap is reduced rather than blanking the picture', () {
      final drawn = painter(cols: 12, rows: 12, gap: 64)
          .scaledGapFor(GridPreview.size);
      expect(drawn, greaterThan(0), reason: 'it used to render an empty box');
      expect(drawn, lessThan(64 * 176 / 1600));
    });

    test('every allowed setting leaves a positive cell', () {
      for (var cols = 2; cols <= 12; cols++) {
        for (var rows = 2; rows <= 12; rows++) {
          final p = painter(cols: cols, rows: rows, gap: 64);
          final g = p.scaledGapFor(GridPreview.size);
          expect((GridPreview.size.width - g * (cols + 1)) / cols,
              greaterThan(0),
              reason: '$cols x $rows');
          expect((GridPreview.size.height - g * (rows + 1)) / rows,
              greaterThan(0),
              reason: '$cols x $rows');
        }
      }
    });
  });

  testWidgets('the caption states the grid, and the gap only when set',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(child: GridPreview(cols: 10, rows: 4, gap: 0))));
    expect(find.text('10 × 4'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
        home: Center(child: GridPreview(cols: 10, rows: 4, gap: 12))));
    expect(find.text('10 × 4 · up to 12 pt gaps'), findsOneWidget);
  });
}
