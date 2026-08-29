import 'package:flutter/material.dart';

import '../core/geometry.dart';
import 'mac_theme.dart';

/// A miniature of the overlay grid, fed by the grid *and* the gap controls.
///
/// This is the reason the settings live in a window rather than a menu. Divvy
/// offers eight bare steppers and no picture, so "10 pt" and "7 x 3" are
/// abstractions you have to go and test. Here both groups of controls feed one
/// image, which is what makes an arbitrary grid comprehensible at a glance —
/// and what lets the grid be two steppers instead of a list of safe presets.
class GridPreview extends StatelessWidget {
  const GridPreview({
    super.key,
    required this.cols,
    required this.rows,
    required this.gap,
  });

  final int cols;
  final int rows;

  /// Points of gap, already resolved from the on/off toggle — zero when gaps
  /// are off, so the picture matches what a placement would actually do.
  final double gap;

  /// 16:10, so the miniature reads as a display rather than a square of cells.
  static const Size size = Size(176, 110);

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: t.contentBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.separator),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: size,
            painter: GridPreviewPainter(
              cols: cols,
              rows: rows,
              gap: gap,
              cell: t.glyphOutline,
            ),
          ),
          const SizedBox(height: 7),
          // Pinned to the miniature's own width. Left to size itself the caption
          // set the width of this whole column, and a longer one pushed the row
          // it sits in over by six points rather than wrapping — these panes are
          // tuned against a mockup and a caption is not the thing that should
          // move them.
          SizedBox(
            width: size.width,
            child: Text(
              // "up to", because the number is a request rather than a promise.
              // The gap shrinks for any window too small to keep it, and that
              // depends on the display: one cell of 12 × 12 at 64 pt keeps all
              // 64 on a 27" and comes down to about 23 on a 13". This pane
              // cannot know which display a summon will land on, so it must not
              // print a figure that holds on only some of them. Since
              // `gapForPlacement` measures the block, "up to" is now literally
              // what a user gets: bigger selections keep more of it.
              gap > 0
                  ? '$cols × $rows · up to ${gap.toInt()} pt gaps'
                  : '$cols × $rows',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: t.labelTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
class GridPreviewPainter extends CustomPainter {
  GridPreviewPainter({
    required this.cols,
    required this.rows,
    required this.gap,
    required this.cell,
  });

  final int cols;
  final int rows;
  final double gap;
  final Color cell;

  /// Points of real screen the preview's width stands in for.
  ///
  /// The gap is a screen measurement, so drawing it at its literal value in a
  /// 176 pt miniature would swamp the picture and lie about the result — 8 pt
  /// looks like a hairline on a real display and like a chasm at 1:9. Scaling
  /// by the same ratio keeps the miniature honest.
  static const double _representedWidth = 1600;

  /// The gap this painter will draw, in miniature points.
  ///
  /// Runs the request through [effectiveGapFor], so a gap the display cannot
  /// afford shrinks in the picture rather than breaking it. Without this the
  /// painter's own `cellW <= 0` guard bailed and drew an **empty box** for a
  /// grid that in fact places windows fine.
  ///
  /// That is the *single-cell* gap, which is the right one here and not the one
  /// most placements get. `gapForPlacement` measures the block, so only a window
  /// small enough to approach the 40 pt floor loses any of the gap — a half of a
  /// 12 × 12 grid keeps all 64 pt where one cell of it comes down to 24.6. This
  /// miniature draws every cell at once, so it has to show the tightest of them;
  /// the caption says "up to" for exactly this reason.
  ///
  /// Against the represented display rather than the user's real one: this pane
  /// has no display to ask about, and on a multi-display setup there is no
  /// single one to name. So the picture is honest about the *shape* of the
  /// clamp, and a smaller display clamps harder still.
  @visibleForTesting
  double scaledGapFor(Size size) {
    final represented = WinRect(0, 0, _representedWidth,
        _representedWidth * size.height / size.width);
    final live = effectiveGapFor(represented, cols: cols, rows: rows, gap: gap);
    return live * size.width / _representedWidth;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = scaledGapFor(size);
    final cellW = (size.width - gap0(g) * 2 - g * (cols - 1)) / cols;
    final cellH = (size.height - gap0(g) * 2 - g * (rows - 1)) / rows;
    if (cellW <= 0 || cellH <= 0) return;

    final fill = Paint()..color = cell.withValues(alpha: 0.30);
    // Stroked as well as filled. With no gap the cells abut exactly, so fills
    // alone merge into one grey slab that reads as a rectangle rather than a
    // grid — the outline is what makes the divisions visible at 6x6 and still
    // countable at 12x12. It also means the picture changes shape, not just
    // spacing, when gaps come on.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = cell.withValues(alpha: 0.55);

    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        final rect = Rect.fromLTWH(
          gap0(g) + c * (cellW + g),
          gap0(g) + r * (cellH + g),
          cellW,
          cellH,
        );
        final rrect =
            RRect.fromRectAndRadius(rect.deflate(0.25), const Radius.circular(1.5));
        canvas.drawRRect(rrect, fill);
        canvas.drawRRect(rrect, edge);
      }
    }
  }

  /// The outer inset. Same value as the gutter — one number, per spec §8 —
  /// but named so the formula reads the way `gridBlock` does.
  double gap0(double g) => g;

  @override
  bool shouldRepaint(covariant GridPreviewPainter old) =>
      old.cols != cols ||
      old.rows != rows ||
      old.gap != gap ||
      old.cell != cell;
}
