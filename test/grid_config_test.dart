import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/grid_config.dart';
import 'package:orthant/settings/settings.dart';

void main() {
  test('the grid divides into halves and thirds on both axes', () {
    // 6 factors into 2x3, which is the whole reason for this grid size:
    // halves and thirds are both exact, horizontally and vertically.
    expect(kDefaultGridCols % 2, 0);
    expect(kDefaultGridCols % 3, 0);
    expect(kDefaultGridRows % 2, 0);
    expect(kDefaultGridRows % 3, 0);
  });

  test('the cell area is a fraction of the display width', () {
    // 1470 * 0.25 = 367.5, inside the clamps.
    expect(gridCellsSizeFor(1470, 956, rows: kDefaultGridRows).width, closeTo(367.5, 0.01));
  });

  test('a very wide display clamps rather than growing without bound', () {
    expect(gridCellsSizeFor(3440, 1440, rows: kDefaultGridRows).width, kGridMaxWidth);
  });

  test('a very small display clamps up to stay hittable', () {
    expect(gridCellsSizeFor(800, 600, rows: kDefaultGridRows).width, kGridMinWidth);
  });

  test('the CELL AREA carries the display aspect ratio, so the grid reads as a '
      'miniature of the screen', () {
    final s = gridCellsSizeFor(1600, 1000, rows: kDefaultGridRows);
    expect(s.height / s.width, closeTo(1000 / 1600, 0.0001));
  });

  test('every ordinary display keeps its aspect ratio in the cell area', () {
    // Regression for the panel-vs-cells mix-up: sizing the *panel* to the
    // display ratio and then subtracting chrome left the cells 15-32 % too
    // wide, so the miniature lied about the shape of the screen.
    for (final d in const [
      [1470.0, 956.0],
      [1920.0, 1050.0],
      [2560.0, 1440.0],
      [3440.0, 1440.0],
    ]) {
      final s = gridCellsSizeFor(d[0], d[1], rows: kDefaultGridRows);
      expect(s.height / s.width, closeTo(d[1] / d[0], 0.0001),
          reason: 'cells must match the display ratio for \${d[0]}x\${d[1]}');
    }
  });

  test('an extreme ultrawide trades exact proportion for a hittable row', () {
    // 7680x1440 proportionally would give 105 pt of cells — 17 pt rows. The
    // floor wins there, on purpose.
    final s = gridCellsSizeFor(7680, 1440, rows: kDefaultGridRows);
    expect(s.height / kDefaultGridRows, greaterThanOrEqualTo(kGridMinCellHeight));
    // ...and it does not kick in for displays that do not need it.
    final ok = gridCellsSizeFor(1920, 1050, rows: kDefaultGridRows);
    expect(ok.height / ok.width, closeTo(1050 / 1920, 0.0001));
  });

  test('gaps default to off — flush, as Rectangle/Magnet/Divvy ship', () {
    // The formula honours any gap; what ships is none, so "left half" is
    // *exactly* half until the user asks otherwise. The value now lives on
    // Settings, which is where the toggle is.
    expect(const Settings().effectiveGap, 0);
  });

  test('the row floor tracks the live grid, not a fixed six', () {
    // The floor exists so an ultrawide does not produce unaimable rows. A grid
    // with more rows needs proportionally more height, or the guarantee is
    // silently halved at 12 rows.
    for (final rows in [4, 6, 12]) {
      final s = gridCellsSizeFor(7680, 1440, rows: rows);
      expect(s.height / rows, greaterThanOrEqualTo(kGridMinCellHeight),
          reason: 'every row must clear the floor at $rows rows');
    }
  });
}
