import 'package:flutter/widgets.dart';
import '../core/geometry.dart';
import '../shortcuts/custom_region.dart';
import '../shortcuts/region_commands.dart';
import 'mac_theme.dart';

/// A miniature diagram of where a command puts the window: an outlined "screen"
/// with the target region filled.
///
/// The filled rect comes from [rectForCommand] over a unit frame — the *same*
/// formula that places real windows — so the diagram can never drift from what
/// the shortcut actually does.
///
/// A null [command] means the row opens the grid rather than placing a window,
/// and draws a lattice instead of a filled region. Same screen outline, so the
/// list still reads as one family; different fill, because nothing is being
/// placed.
class RegionGlyph extends StatelessWidget {
  const RegionGlyph({
    super.key,
    this.command,
    this.custom,
    this.dimmed = false,
  });

  final RegionCommand? command;

  /// A user-defined region, which wins over [command] when both are given.
  /// Both null draws the summon's lattice.
  final CustomRegion? custom;

  /// Unbound commands draw muted, matching their "Not set" row.
  final bool dimmed;

  static const Size _size = Size(26, 18);

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    return CustomPaint(
      size: _size,
      painter: _RegionGlyphPainter(
        command: command,
        custom: custom,
        outline: t.glyphOutline,
        fill: dimmed ? t.labelTertiary : t.accent,
      ),
    );
  }
}

class _RegionGlyphPainter extends CustomPainter {
  _RegionGlyphPainter({
    required this.command,
    required this.custom,
    required this.outline,
    required this.fill,
  });

  final RegionCommand? command;
  final CustomRegion? custom;
  final Color outline;
  final Color fill;

  /// Divisions per axis in the lattice drawn for a null [command]. Three, not
  /// the live grid size: this is an icon meaning "a grid", and redrawing it
  /// whenever the user changes the columns would make a 12x12 row unreadable.
  static const _latticeDivisions = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );

    final unit = unitRectForGlyph(command: command, custom: custom);
    if (unit == null) {
      _paintLattice(canvas, size);
      return;
    }

    final region = Rect.fromLTWH(
      unit.x * size.width,
      unit.y * size.height,
      unit.width * size.width,
      unit.height * size.height,
    ).deflate(_insetFor(unit, size));
    if (region.width <= 0 || region.height <= 0) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(region, const Radius.circular(1.5)),
      Paint()..color = fill,
    );
  }

  /// How far to inset the filled region, in glyph points.
  ///
  /// A flat 1.5 takes 3 points off each axis, which a thin region does not
  /// have: a region may divide an axis into twelve, and one column of twelve in
  /// a 26-point glyph is **2.17 points** wide — deflating it goes negative, the
  /// guard above bails, and the row draws an empty screen outline for a
  /// perfectly valid shape. Scale the inset down for narrow fills so the gap
  /// stays proportional and something is always drawn.
  static double _insetFor(WinRect unit, Size size) {
    final w = unit.width * size.width;
    final h = unit.height * size.height;
    final smallest = w < h ? w : h;
    return smallest / 4 < 1.5 ? smallest / 4 : 1.5;
  }

  /// Cells inset inside the screen outline, the way the overlay's grid sits
  /// inside the display it covers.
  void _paintLattice(Canvas canvas, Size size) {
    const n = _latticeDivisions;
    final inner = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1)
        .deflate(2.5);
    if (inner.width <= 0 || inner.height <= 0) return;

    final cellW = inner.width / n;
    final cellH = inner.height / n;
    final paint = Paint()..color = fill;
    for (var c = 0; c < n; c++) {
      for (var r = 0; r < n; r++) {
        final cell = Rect.fromLTWH(
          inner.left + c * cellW,
          inner.top + r * cellH,
          cellW,
          cellH,
        ).deflate(0.75);
        if (cell.width <= 0 || cell.height <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell, const Radius.circular(0.75)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RegionGlyphPainter old) =>
      old.command != command ||
      old.custom != custom ||
      old.fill != fill ||
      old.outline != outline;
}

/// The filled rect a glyph draws, over a unit frame — or null for the summon,
/// which draws a lattice instead.
///
/// Pulled out of the painter so it can be asserted directly: a `CustomPaint`
/// renders to a canvas no widget test can read, and the guarantee that matters
/// here is not *that* something was drawn but that the shape came from the
/// **placement formula** rather than from hand-tuned coordinates. That is what
/// stops a row's diagram drifting from what its shortcut actually does.
WinRect? unitRectForGlyph({
  required RegionCommand? command,
  required CustomRegion? custom,
}) {
  const frame = WinRect(0, 0, 1, 1);
  /// A stand-in "current window" for [RegionCommand.center], the one command
  /// whose rect depends on the window's own size. Half-size and centred reads
  /// correctly at glyph scale.
  const window = WinRect(0.25, 0.25, 0.5, 0.5);

  if (custom != null) {
    return gridBlock(frame,
        cols: custom.cols,
        rows: custom.rows,
        c0: custom.c0,
        c1: custom.c1,
        r0: custom.r0,
        r1: custom.r1);
  }
  if (command == null) return null;
  return rectForCommand(command, frame, current: window);
}
