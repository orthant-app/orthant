import 'dart:math' as math;
import 'dart:ui' show Size;

/// The grid a fresh install starts with. The live size is a user setting —
/// see `Settings.gridCols` / `gridRows` — and rides the summon payload to the
/// overlay's isolate.
///
/// 6 x 6 because six factors into 2 x 3, so *both* axes give halves (3+3) and
/// thirds (2+2+2). 6x4 could express the first and 6x3 the second, neither
/// both. A "quarter" in window-manager terms is a quadrant — 3 columns x 3
/// rows — which is exact here.
///
/// This reasoning binds the *default* only. A user who picks 4 x 4 trades
/// thirds for quarters, which is a fair trade to offer and not ours to refuse.
const int kDefaultGridCols = 6;
const int kDefaultGridRows = 6;

/// The grid is a scale model of the display, so its width is a fraction of the
/// display's rather than a fixed number of points — a fixed size is a quarter
/// of a 13" laptop but a tenth of an ultrawide.
const double kGridWidthFraction = 0.25;

/// Clamps: neither an unhittable postage stamp nor a second full-screen grid.
const double kGridMinWidth = 280;
const double kGridMaxWidth = 560;

/// Floor on a cell's height, in points.
///
/// A proportional grid on an extreme ultrawide gets unusably flat: 7680 x 1440
/// would give 17 pt rows. Past this floor the miniature stops being exactly
/// proportional — deliberately, because a grid you cannot aim at is worse than
/// one that is slightly too tall.
const double kGridMinCellHeight = 22;

/// The on-screen size of the **cell area** for a display of [displayWidth] x
/// [displayHeight] points — not the whole panel.
///
/// This is what makes the grid a true miniature of the screen: the cells carry
/// the display's aspect ratio, and the panel is whatever this plus its chrome
/// (the app chip, the gap under it, the padding) comes to. Sizing the *panel*
/// here instead and subtracting chrome from it — which is what this did before —
/// left the cells disproportionate by the chrome's share: 15 % too wide on a
/// 1920 x 1050 display, 32 % on a 5120 x 1440 ultrawide.
///
/// [rows] is the live row count, not a constant: the minimum-cell-height floor
/// has to grow with the grid, or a 12-row grid on an ultrawide would produce
/// rows half the height the floor exists to guarantee.
Size gridCellsSizeFor(double displayWidth, double displayHeight,
    {required int rows}) {
  final w = (displayWidth * kGridWidthFraction)
      .clamp(kGridMinWidth, kGridMaxWidth)
      .toDouble();
  final proportional = w * (displayHeight / displayWidth);
  return Size(w, math.max(proportional, rows * kGridMinCellHeight));
}
