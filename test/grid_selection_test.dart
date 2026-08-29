import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/overlay/grid_selection.dart';

void main() {
  _arrowKeys();
  const gridSize = Size(600, 360); // 100 x 60 per cell at 6 x 6

  group('pointToCell', () {
    test('maps a point to the cell containing it', () {
      expect(pointToCell(const Offset(0, 0), gridSize, cols: 6, rows: 6), const Cell(0, 0));
      expect(pointToCell(const Offset(150, 90), gridSize, cols: 6, rows: 6), const Cell(1, 1));
      expect(pointToCell(const Offset(599, 359), gridSize, cols: 6, rows: 6), const Cell(5, 5));
    });

    test('clamps outside the grid instead of returning an invalid index', () {
      // A drag that leaves the grid must still resolve to an edge cell — the
      // pointer routinely runs past the grid while dragging.
      expect(pointToCell(const Offset(-40, -40), gridSize, cols: 6, rows: 6), const Cell(0, 0));
      expect(pointToCell(const Offset(9999, 9999), gridSize, cols: 6, rows: 6), const Cell(5, 5));
    });
  });

  group('blockFrom', () {
    test('normalises a top-left to bottom-right drag', () {
      expect(blockFrom(const Cell(1, 1), const Cell(3, 2)),
          const CellBlock(1, 3, 1, 2));
    });

    test('normalises a bottom-right to top-left drag identically', () {
      // Dragging "backwards" must produce the same block, or half of all
      // drags would select nothing.
      expect(blockFrom(const Cell(3, 2), const Cell(1, 1)),
          const CellBlock(1, 3, 1, 2));
    });

    test('a single cell is a 1x1 block', () {
      expect(blockFrom(const Cell(2, 4), const Cell(2, 4)),
          const CellBlock(2, 2, 4, 4));
    });
  });

  group('targetRect', () {
    const frame = WinRect(0, 0, 1200, 600);

    test('the whole grid is the whole visible frame', () {
      expect(targetRect(const CellBlock(0, 5, 0, 5), frame, cols: 6, rows: 6), frame);
    });

    test('the left half is exactly half', () {
      expect(targetRect(const CellBlock(0, 2, 0, 5), frame, cols: 6, rows: 6),
          const WinRect(0, 0, 600, 600));
    });

    test('the left two-thirds is exactly two-thirds', () {
      expect(targetRect(const CellBlock(0, 3, 0, 5), frame, cols: 6, rows: 6),
          const WinRect(0, 0, 800, 600));
    });

    test('a rect is offset by the display origin', () {
      // The second display does not start at zero; forgetting this is the
      // classic multi-display placement bug.
      const second = WinRect(1440, 25, 1200, 600);
      expect(targetRect(const CellBlock(0, 2, 0, 5), second, cols: 6, rows: 6),
          const WinRect(1440, 25, 600, 600));
    });

    test('honours a non-zero gap via the shared formula', () {
      final r = targetRect(const CellBlock(0, 5, 0, 5), frame,
          cols: 6, rows: 6, gap: 10);
      expect(r, const WinRect(10, 10, 1180, 580));
    });
  });

  group('previewToLocal', () {
    test('subtracts the display origin so the preview draws in panel space', () {
      const second = WinRect(1440, 25, 1200, 600);
      const global = WinRect(1440, 25, 600, 600);
      expect(previewToLocal(global, second), const Rect.fromLTWH(0, 0, 600, 600));
    });
  });

  group('a configurable grid', () {
    test('pointToCell honours a non-square grid', () {
      // 4 columns x 8 rows over 100x100: cells are 25 wide, 12.5 tall.
      const size = Size(100, 100);
      expect(pointToCell(const Offset(26, 13), size, cols: 4, rows: 8),
          const Cell(1, 1));
      expect(pointToCell(const Offset(99, 99), size, cols: 4, rows: 8),
          const Cell(3, 7));
      // Still clamped: the pointer routinely leaves the grid mid-drag.
      expect(pointToCell(const Offset(500, -20), size, cols: 4, rows: 8),
          const Cell(3, 0));
    });

    test('targetRect divides by the grid it is given', () {
      const frame = WinRect(0, 0, 1200, 600);
      expect(targetRect(const CellBlock(0, 0, 0, 0), frame, cols: 4, rows: 4),
          const WinRect(0, 0, 300, 150));
      expect(targetRect(const CellBlock(0, 0, 0, 0), frame, cols: 8, rows: 8),
          const WinRect(0, 0, 150, 75));
    });

    test('a full selection is the whole display at every grid size', () {
      const frame = WinRect(0, 0, 1200, 600);
      for (final n in [2, 4, 6, 8, 12]) {
        expect(
            targetRect(CellBlock(0, n - 1, 0, n - 1), frame, cols: n, rows: n),
            frame,
            reason: 'covering every cell must mean the display at $n x $n');
      }
    });

    test('gaps inset the outer edge and separate the cells', () {
      const frame = WinRect(0, 0, 1000, 1000);
      // usable = 1000 - 2*10 = 980; cellW = (980 - 10) / 2 = 485.
      expect(
          targetRect(const CellBlock(0, 0, 0, 1), frame,
              cols: 2, rows: 2, gap: 10),
          const WinRect(10, 10, 485, 980));
    });

    test('a full selection with gaps is the display minus the edge inset', () {
      const frame = WinRect(0, 0, 1000, 1000);
      expect(
          targetRect(const CellBlock(0, 5, 0, 5), frame,
              cols: 6, rows: 6, gap: 10),
          const WinRect(10, 10, 980, 980),
          reason: 'the gutters are consumed by the span; only the edge remains');
    });
  });
}

void _arrowKeys() {
  group('arrow-key selection', () {
    // The grid's largest hole: the summon is a shortcut, and then you needed the
    // mouse. Named a scope-out in M5 and M7, and raised by both reviews.
    ({Cell anchor, Cell focus}) move(
      Cell? anchor,
      Cell? focus,
      GridDirection d, {
      bool extend = false,
      int cols = 6,
      int rows = 6,
    }) => moveSelectionFor(
      anchor: anchor,
      focus: focus,
      direction: d,
      extend: extend,
      cols: cols,
      rows: rows,
    );

    test('the first press selects the top-left cell, whichever arrow it was',
        () {
      // Not a move from nowhere, which would swallow the press, and not "under
      // the pointer", which would make the keyboard depend on the mouse.
      for (final d in GridDirection.values) {
        expect(move(null, null, d),
            (anchor: const Cell(0, 0), focus: const Cell(0, 0)));
      }
    });

    test('a bare arrow walks a single cell', () {
      var s = move(const Cell(2, 2), const Cell(2, 2), GridDirection.right);
      expect(s, (anchor: const Cell(3, 2), focus: const Cell(3, 2)));
      s = move(s.anchor, s.focus, GridDirection.down);
      expect(s, (anchor: const Cell(3, 3), focus: const Cell(3, 3)));
    });

    test('a bare arrow collapses a block instead of sliding it', () {
      // Otherwise the two arrow behaviours are indistinguishable until you look
      // at the highlight.
      final s = move(const Cell(1, 1), const Cell(4, 3), GridDirection.left);
      expect(s.anchor, s.focus);
      expect(s.focus, const Cell(3, 3));
    });

    test('shift extends from the anchor', () {
      final s = move(const Cell(1, 1), const Cell(1, 1), GridDirection.right,
          extend: true);
      expect(s.anchor, const Cell(1, 1));
      expect(s.focus, const Cell(2, 1));
      expect(blockFrom(s.anchor, s.focus), const CellBlock(1, 2, 1, 1));
    });

    test('shift shrinks coming back, and crosses the anchor cleanly', () {
      var s = (anchor: const Cell(2, 2), focus: const Cell(4, 2));
      s = move(s.anchor, s.focus, GridDirection.left, extend: true);
      expect(blockFrom(s.anchor, s.focus), const CellBlock(2, 3, 2, 2));
      // Back past the anchor: blockFrom normalises, so no special case.
      s = move(s.anchor, s.focus, GridDirection.left, extend: true);
      s = move(s.anchor, s.focus, GridDirection.left, extend: true);
      expect(s.focus, const Cell(1, 2));
      expect(blockFrom(s.anchor, s.focus), const CellBlock(1, 2, 2, 2));
    });

    test('the edges clamp rather than wrap', () {
      // A jump from the last column to the first is indistinguishable from a
      // mis-press.
      expect(move(null, const Cell(0, 0), GridDirection.left).focus,
          const Cell(0, 0));
      expect(move(null, const Cell(0, 0), GridDirection.up).focus,
          const Cell(0, 0));
      expect(move(null, const Cell(5, 5), GridDirection.right).focus,
          const Cell(5, 5));
      expect(move(null, const Cell(5, 5), GridDirection.down).focus,
          const Cell(5, 5));
    });

    test('clamping respects a non-square grid', () {
      expect(
        move(null, const Cell(9, 1), GridDirection.right, cols: 10, rows: 3)
            .focus,
        const Cell(9, 1),
      );
      expect(
        move(null, const Cell(9, 2), GridDirection.down, cols: 10, rows: 3)
            .focus,
        const Cell(9, 2),
      );
    });

    test('an extended selection at the edge stops without losing the anchor',
        () {
      final s = move(const Cell(4, 0), const Cell(5, 0), GridDirection.right,
          extend: true);
      expect(s.anchor, const Cell(4, 0), reason: 'the anchor never moves');
      expect(s.focus, const Cell(5, 0));
    });
  });
}
