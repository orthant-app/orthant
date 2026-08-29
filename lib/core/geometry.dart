/// A rectangle in top-left-origin global points (CoreGraphics / AX space).
class WinRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const WinRect(this.x, this.y, this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is WinRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'WinRect($x, $y, $width, $height)';
}

/// The left half of [frame], in the same top-left global space.
WinRect leftHalf(WinRect frame) =>
    WinRect(frame.x, frame.y, frame.width / 2, frame.height);

/// The screen from [screens] that [window] occupies the most, or null if
/// [screens] is empty. Falls back to the first screen when nothing overlaps.
///
/// Keyboard shortcuts must snap a window *within its own display* — using the
/// display under the cursor instead would teleport the window whenever the
/// mouse happens to rest on another screen. Overlap-by-area (rather than
/// containment) is what decides the case of a window straddling two displays.
/// Pure geometry, so the Windows backend reuses it unchanged.
WinRect? screenContaining(WinRect window, List<WinRect> screens) {
  if (screens.isEmpty) return null;
  var best = screens.first;
  var bestArea = 0.0;
  for (final screen in screens) {
    final area = _overlapArea(window, screen);
    if (area > bestArea) {
      bestArea = area;
      best = screen;
    }
  }
  return best;
}

double _overlapArea(WinRect a, WinRect b) {
  final w = _overlap(a.x, a.x + a.width, b.x, b.x + b.width);
  final h = _overlap(a.y, a.y + a.height, b.y, b.y + b.height);
  return w * h;
}

double _overlap(double a0, double a1, double b0, double b1) {
  final lo = a0 > b0 ? a0 : b0;
  final hi = a1 < b1 ? a1 : b1;
  return hi > lo ? hi - lo : 0.0;
}

/// The smallest cell a placement may produce, in points.
///
/// Not a rendering concern (the overlay miniature has its own floor, see
/// `kGridMinCellHeight`) — this is about the window that actually lands. A
/// 32 pt-tall window is not a window, and on the way to one the arithmetic
/// passes through zero and out the other side.
const double kMinPlacedCell = 40;

/// The gap [gridBlock] will actually use to place [c0..c1] × [r0..r1] on a
/// [cols]×[rows] grid over [frame].
///
/// The settings validate columns, rows and gap size **independently of each
/// other** — nothing there can know which display the grid will land on, and on
/// a multi-display setup there is no single right answer to know. So the
/// relation between them is enforced here, where the frame is finally known:
/// 12 rows at 64 pt needs 832 points of gutter alone, which a 775-point visible
/// frame does not have, and the unclamped formula answered with a cell height
/// of **-4.75** — a negative-size window handed to the Accessibility API.
///
/// Reduced rather than refused. A stepper the user can move that then silently
/// does nothing is worse than a gap quietly smaller than the number beside it,
/// and the on-screen preview is drawn from this same value, so what they see is
/// still what they get.
///
/// **Measured against the block, not the grid**, which is what keeps placement
/// free of the denominators it was written in. Expand [gridBlock] with
/// `f = span / n` and the grid cancels out entirely — `x = f₀·W + g(1 − f₀)`,
/// `w = f_w·W − g(f_w + 1)` — so the *only* way `cols` can reach the result is
/// through this clamp. Deriving it from the grid made "left ⅔" land in two
/// places depending on whether it was written as thirds or as twelfths, and
/// made the placement of any region change when [refineForEditing] rewrote its
/// denominators. Deriving it from the block cannot: two spellings of one
/// fraction give one gap.
///
/// It is also the clamp that was always meant. The floor is about *the window
/// that lands*, and a grid-wide clamp protects the smallest cell the user
/// **could** have picked rather than the block they did — so a 12 × 12 grid cut
/// a 64 pt gap to 24.6 even for a half-screen window. Substituting `span = 1`
/// here recovers the grid-wide formula exactly, which is what [effectiveGapFor]
/// is: this clamp at its worst case.
double gapForPlacement(
  WinRect frame, {
  required int cols,
  required int rows,
  required int c0,
  required int c1,
  required int r0,
  required int r1,
  double gap = 0,
}) {
  if (gap <= 0) return 0;
  // Solve `span/n * extent - g * (span/n + 1) >= kMinPlacedCell` for g. Stated
  // multiplied through by n, which is both tidier and — at span 1 — the exact
  // expression this replaced, down to the floating-point operations.
  double limit(double extent, int n, int span) =>
      (span * extent - kMinPlacedCell * n) / (span + n);
  final w = limit(frame.width, cols, c1 - c0 + 1);
  final h = limit(frame.height, rows, r1 - r0 + 1);
  final most = w < h ? w : h;
  if (most <= 0) return 0; // even zero gap cannot reach the floor — cells still divide the frame
  return gap < most ? gap : most;
}

/// The gap a [cols]×[rows] grid can offer *every* one of its cells.
///
/// [gapForPlacement] at its worst case — a single cell — and so the right thing
/// to draw a picture of the whole grid with, which is its one caller: the
/// settings miniature shows all the cells at once, so it must show the gap the
/// tightest of them would get.
double effectiveGapFor(WinRect frame,
        {required int cols, required int rows, double gap = 0}) =>
    gapForPlacement(frame,
        cols: cols, rows: rows, c0: 0, c1: 0, r0: 0, r1: 0, gap: gap);

/// The rect of the cell block [c0..c1] × [r0..r1] on a [cols]×[rows] grid over
/// [frame], insetting the outer edges by [gap] and separating cells with [gap]
/// gutters. All in top-left global points. This is the single placement formula
/// shared by direct shortcuts (2×2) and the grid overlay (N×M).
///
/// [gap] is a request, not a promise — see [gapForPlacement].
///
/// The result depends only on the *fractions* `c0/cols` and `(c1-c0+1)/cols`,
/// never on `cols` itself, so the same rectangle written on any two grids lands
/// in the same place. That is what makes [refineForEditing] safe and what lets
/// ⌘S promise the shortcut it offers reproduces the placement it just made.
WinRect gridBlock(
  WinRect frame, {
  required int cols,
  required int rows,
  required int c0,
  required int c1,
  required int r0,
  required int r1,
  double gap = 0,
}) {
  gap = gapForPlacement(frame,
      cols: cols, rows: rows, c0: c0, c1: c1, r0: r0, r1: r1, gap: gap);
  final usableX = frame.x + gap;
  final usableY = frame.y + gap;
  final usableW = frame.width - 2 * gap;
  final usableH = frame.height - 2 * gap;
  final cellW = (usableW - (cols - 1) * gap) / cols;
  final cellH = (usableH - (rows - 1) * gap) / rows;
  final x = usableX + c0 * (cellW + gap);
  final y = usableY + r0 * (cellH + gap);
  final w = (c1 - c0 + 1) * cellW + (c1 - c0) * gap;
  final h = (r1 - r0 + 1) * cellH + (r1 - r0) * gap;
  return WinRect(x, y, w, h);
}
