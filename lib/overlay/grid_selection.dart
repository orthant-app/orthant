import 'dart:math' as math;
import 'dart:ui';

import '../core/geometry.dart';

/// One cell of the overlay grid, zero-indexed from the top-left.
class Cell {
  final int col;
  final int row;
  const Cell(this.col, this.row);

  @override
  bool operator ==(Object other) =>
      other is Cell && other.col == col && other.row == row;
  @override
  int get hashCode => Object.hash(col, row);
  @override
  String toString() => 'Cell($col, $row)';
}

/// A rectangular block of cells, inclusive at both ends.
class CellBlock {
  final int c0, c1, r0, r1;
  const CellBlock(this.c0, this.c1, this.r0, this.r1);

  @override
  bool operator ==(Object other) =>
      other is CellBlock &&
      other.c0 == c0 &&
      other.c1 == c1 &&
      other.r0 == r0 &&
      other.r1 == r1;
  @override
  int get hashCode => Object.hash(c0, c1, r0, r1);
  @override
  String toString() => 'CellBlock($c0..$c1, $r0..$r1)';
}

/// The cell containing [local], a point in grid-local coordinates within a grid
/// of [gridSize] divided into [cols] x [rows]. **Clamped**: the pointer
/// routinely leaves the grid mid-drag, and an edge cell is the useful answer
/// there — not an out-of-range index.
Cell pointToCell(Offset local, Size gridSize,
    {required int cols, required int rows}) {
  final cellW = gridSize.width / cols;
  final cellH = gridSize.height / rows;
  final col = (local.dx / cellW).floor().clamp(0, cols - 1);
  final row = (local.dy / cellH).floor().clamp(0, rows - 1);
  return Cell(col, row);
}

/// Which way an arrow key moves the grid selection.
enum GridDirection { left, right, up, down }

/// The selection after an arrow press.
///
/// Keyboard selection is the grid's largest hole: the summon is a shortcut, and
/// then you needed the mouse. Named a deliberate scope-out in M5 and again in
/// M7, and called out by both external reviews.
///
/// Three rules, chosen to match what a selection UI conventionally does:
///
///  * **Nothing selected yet** starts at the top-left cell, whichever arrow was
///    pressed. Interpreting the first press as a *move* would silently swallow
///    it, and starting under the pointer would make the keyboard depend on where
///    the mouse happens to rest.
///  * **A bare arrow collapses** to a single cell and walks it. Keeping a
///    multi-cell block and sliding it is the other option, and it makes the two
///    arrow behaviours indistinguishable until you look at the highlight.
///  * **⇧ + arrow extends** — the anchor stays put and the focus moves, so the
///    block grows in the direction pressed and shrinks coming back, exactly as
///    dragging does. [blockFrom] already normalises either ordering, so
///    extending *past* the anchor works without a special case.
///
/// Clamped at the edges rather than wrapping: a selection that jumped from the
/// last column to the first would be indistinguishable from a mis-press.
({Cell anchor, Cell focus}) moveSelectionFor({
  Cell? anchor,
  Cell? focus,
  required GridDirection direction,
  required bool extend,
  required int cols,
  required int rows,
}) {
  if (focus == null) {
    const start = Cell(0, 0);
    return (anchor: start, focus: start);
  }
  final (dc, dr) = switch (direction) {
    GridDirection.left => (-1, 0),
    GridDirection.right => (1, 0),
    GridDirection.up => (0, -1),
    GridDirection.down => (0, 1),
  };
  final moved = Cell(
    (focus.col + dc).clamp(0, cols - 1),
    (focus.row + dr).clamp(0, rows - 1),
  );
  return extend
      ? (anchor: anchor ?? focus, focus: moved)
      : (anchor: moved, focus: moved);
}

/// The block spanned by a drag from [anchor] to [focus], in either direction.
CellBlock blockFrom(Cell anchor, Cell focus) => CellBlock(
      math.min(anchor.col, focus.col),
      math.max(anchor.col, focus.col),
      math.min(anchor.row, focus.row),
      math.max(anchor.row, focus.row),
    );

/// Where a window covering [block] lands on a [cols] x [rows] grid over
/// [displayFrame], in top-left global points.
///
/// Delegates to [gridBlock] — the single placement formula the direct
/// shortcuts also use, so the grid and the keyboard paths can never disagree.
WinRect targetRect(CellBlock block, WinRect displayFrame,
        {required int cols, required int rows, double gap = 0}) =>
    gridBlock(displayFrame,
        cols: cols,
        rows: rows,
        c0: block.c0,
        c1: block.c1,
        r0: block.r0,
        r1: block.r1,
        gap: gap);

/// A global top-left rect expressed in panel-local coordinates.
///
/// The panel covers the display's visible frame exactly, so this is a
/// subtraction of the frame origin — and it is the only place in the overlay
/// where the global and panel coordinate spaces meet.
Rect previewToLocal(WinRect global, WinRect displayFrame) => Rect.fromLTWH(
      global.x - displayFrame.x,
      global.y - displayFrame.y,
      global.width,
      global.height,
    );
