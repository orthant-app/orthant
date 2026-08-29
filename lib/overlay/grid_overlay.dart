import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/geometry.dart';
import '../core/grid_config.dart';
import 'grid_selection.dart';

/// The overlay's whole surface: a compact grid centred on an otherwise clear,
/// full-screen panel, plus a true-scale preview of where the window will land.
///
/// The grid is a *proxy* — a scale model of the display — while the preview is
/// drawn at real size and position. That pairing is the design: a small drag
/// with a full-size answer.
class GridOverlay extends StatefulWidget {
  const GridOverlay({
    super.key,
    required this.sessionId,
    required this.displayFrame,
    required this.appName,
    required this.active,
    required this.onBeginDrag,
    required this.onEndDrag,
    required this.onCommit,
    required this.onCancel,
    this.onSave,
    this.saveHint = false,
    this.cols = kDefaultGridCols,
    this.rows = kDefaultGridRows,
    this.gap = 0,
    this.appIcon,
  });

  /// The live grid, from the user's settings. It arrives in the `summon`
  /// payload rather than being read here: this widget runs on the overlay's
  /// *own* Flutter engine, which has no access to the main isolate's
  /// SharedPreferences. Pushing it per summon also makes a stale grid
  /// unrepresentable — there is nowhere for one to be cached.
  final int cols;
  final int rows;

  /// Screen inset and inter-window gutter, in points, already resolved from the
  /// on/off toggle — so this is zero when gaps are off, not the stored size.
  final double gap;

  /// Identifies the summon this grid belongs to. A new value means a *new*
  /// capture is behind this grid, so any selection held over from the
  /// previous one must not survive — see [GridOverlayState.didUpdateWidget].
  /// The widget's own state must not depend on `hidden` arriving to clear it:
  /// a re-summon that lands inside the previous session's fade window skips
  /// `hidden` entirely (the panel-local fade guard wins), so this is the only
  /// signal guaranteed to arrive for every new session.
  final int sessionId;

  /// The display's visible frame, top-left global points. The panel covers it
  /// exactly, so panel-local == global minus this origin.
  final WinRect displayFrame;

  /// The captured window's app — the only thing telling the user what they are
  /// about to move, since that window is now behind the overlay.
  final String appName;
  final Uint8List? appIcon;

  /// False on every display except the one under the pointer. Inactive panels
  /// render dimmed and accept no input.
  final bool active;

  final VoidCallback onBeginDrag;

  /// Sent when a drag is interrupted rather than released (e.g. the pointer
  /// leaves the app). Native's press lock must be told explicitly — nothing
  /// else releases it, and a held lock suppresses `becameActive` for the rest
  /// of the session.
  final VoidCallback onEndDrag;
  final void Function(WinRect) onCommit;

  /// Asked for the current block to become a shortcut — `⌘S`, grabbed natively
  /// like `Return` and the arrows, because the panel is non-key.
  final void Function(CellBlock block, WinRect rect)? onSave;

  /// Whether to offer the hint at all. False once the user has a region of
  /// their own: at that point they know the feature exists, and the overlay
  /// goes back to being only the grid.
  final bool saveHint;
  final VoidCallback onCancel;

  /// Marks the cell area specifically — the exact rect [pointToCell] and
  /// the painter both divide into cells — so tests can derive expected cell
  /// geometry straight from it. Deliberately *not* a key on the whole panel:
  /// that placement (this key's original spot) is what let hit-testing and
  /// painting disagree about where the grid actually was.
  static const cellsKey = ValueKey('orthant.grid.cells');

  @override
  State<GridOverlay> createState() => GridOverlayState();
}

/// Panel chrome, in points. [GridOverlayState._cellsRect] and the panel's own
/// on-screen layout are both built from these same three numbers — that
/// sharing is what keeps "what's clickable" and "what's drawn" from drifting
/// apart the way they used to.
const double _kPanelPadding = 9;
const double _kChipRowHeight = 16;
const double _kChipGap = 8;

class GridOverlayState extends State<GridOverlay> {
  Cell? _anchor;
  Cell? _focus;

  @override
  void didUpdateWidget(covariant GridOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new session means a fresh capture behind this same resident widget —
    // clear declaratively, from the input that's guaranteed to change on
    // every summon, rather than waiting on a `hidden` round trip that a
    // re-summon during the previous session's fade can skip entirely.
    if (widget.sessionId != oldWidget.sessionId) {
      _anchor = null;
      _focus = null;
    }
    // Going inactive must also drop the selection. The Opacity in build()
    // dims the whole stack, preview included, so a panel that keeps its
    // _focus goes on drawing a ghosted highlight and true-scale preview on a
    // display the pointer has already left — two previews on screen at once,
    // one of them wrong.
    if (!widget.active && oldWidget.active) {
      _anchor = null;
      _focus = null;
    }
  }

  /// The cell area's size — proportional to the display. The panel is derived
  /// from this by adding chrome, never the reverse.
  Size get _cellsSize =>
      gridCellsSizeFor(widget.displayFrame.width, widget.displayFrame.height,
          rows: widget.rows);

  /// The whole rounded panel — background, chip and cells together — centred
  /// on the display. Positions the background and the chip; [_cellsRect], not
  /// this rect, is what hit-testing and the painter must use.
  Rect get _panelRect {
    final c = _cellsSize;
    return Rect.fromCenter(
      center: Offset(
          widget.displayFrame.width / 2, widget.displayFrame.height / 2),
      width: c.width + _kPanelPadding * 2,
      height: c.height + _kPanelPadding * 2 + _kChipRowHeight + _kChipGap,
    );
  }

  /// The app-name chip: top of the panel, inset by the shared padding.
  Rect get _chipRect {
    final p = _panelRect;
    return Rect.fromLTWH(p.left + _kPanelPadding, p.top + _kPanelPadding,
        p.width - _kPanelPadding * 2, _kChipRowHeight);
  }

  /// The cell area, below the chip. This is the *single* rect
  /// [pointToCell] and [_GridPainter] may use — both are driven from this one
  /// getter rather than one measuring `_panelRect` and the other measuring a
  /// rendered Column, which is exactly how the two drifted ~33px/~9px apart
  /// before (see the commit that introduced this comment).
  Rect get _cellsRect {
    final p = _panelRect;
    return Rect.fromLTRB(
      p.left + _kPanelPadding,
      p.top + _kPanelPadding + _kChipRowHeight + _kChipGap,
      p.right - _kPanelPadding,
      p.bottom - _kPanelPadding,
    );
  }

  /// The rect for whatever is currently selected — a drag or a bare hover.
  WinRect? get _effectiveTarget {
    final b = _effectiveBlock;
    return b == null
        ? null
        : targetRect(b, widget.displayFrame,
            cols: widget.cols, rows: widget.rows, gap: widget.gap);
  }

  /// Commit whatever is currently selected. Called for `Return`, which is
  /// grabbed natively and relayed — the panel is non-key, so the key event
  /// never reaches Flutter directly. No selection means no-op, not a guess.
  void commitCurrent() {
    final t = _effectiveTarget;
    if (t != null) widget.onCommit(t);
  }

  /// Hand the current block up to be turned into a shortcut. Like
  /// [commitCurrent], no selection is a no-op rather than a guess — pressing
  /// ⌘S at an empty grid should do nothing, not save a corner.
  /// ⌘S is Return *plus* an offer, so it carries the rect as well as the
  /// block: the window lands where it was going to land, and the shape becomes
  /// a shortcut. Saving without placing would mean summoning again to use the
  /// region you had just finished defining.
  void saveCurrent() {
    final b = _effectiveBlock;
    final t = _effectiveTarget;
    if (b != null && t != null) widget.onSave?.call(b, t);
  }

  /// Move or extend the selection by one cell. Called for an arrow key, which —
  /// like `Return` — is grabbed natively and relayed, because the panel is
  /// non-activating and no key event reaches Flutter directly.
  ///
  /// This is what makes the grid usable without a mouse: the summon was already
  /// a shortcut, and then you had to reach for the trackpad. Selection rules
  /// live in [moveSelection], where they are testable on their own.
  void moveSelection(GridDirection direction, {bool extend = false}) {
    if (!widget.active) return;
    final next = moveSelectionFor(
      anchor: _anchor,
      focus: _focus,
      direction: direction,
      extend: extend,
      cols: widget.cols,
      rows: widget.rows,
    );
    setState(() {
      _anchor = next.anchor;
      _focus = next.focus;
    });
  }

  void _setFocusFrom(Offset panelLocal) {
    final cell = pointToCell(panelLocal - _cellsRect.topLeft, _cellsRect.size,
        cols: widget.cols, rows: widget.rows);
    if (cell != _focus) setState(() => _focus = cell);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!widget.active) return;
    if (!_panelRect.contains(e.localPosition)) {
      widget.onCancel();
      return;
    }
    if (!_cellsRect.contains(e.localPosition)) {
      // Inside the panel but on its chrome (the app chip, or the padding
      // around it) — not a cell. Ignored rather than cancelled: a mis-press
      // on the chip isn't an obvious "dismiss" gesture, and cancelling here
      // would tear down the whole overlay for a near-miss inside its own
      // bounds.
      return;
    }
    // Primary button only. A right- or middle-press would otherwise begin a
    // selection like any other, and its release would snap the window — the
    // overlay's own panels are exempt from the native click-away monitors, so
    // nothing else stops a secondary click here.
    if (e.buttons & kPrimaryButton == 0) return;
    final cell =
        pointToCell(e.localPosition - _cellsRect.topLeft, _cellsRect.size,
            cols: widget.cols, rows: widget.rows);
    setState(() {
      _anchor = cell;
      _focus = cell;
    });
    // Native locks the drag to this display at press, not release.
    widget.onBeginDrag();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!widget.active || _anchor == null) return;
    _setFocusFrom(e.localPosition);
  }

  /// Hover selects exactly one cell. The anchor stays null, and
  /// [_effectiveBlock] turns a null anchor into a 1x1 block.
  void _onPointerHover(PointerHoverEvent e) {
    if (!widget.active || _anchor != null) return;
    final inside = _cellsRect.contains(e.localPosition);
    final next = inside
        ? pointToCell(e.localPosition - _cellsRect.topLeft, _cellsRect.size,
            cols: widget.cols, rows: widget.rows)
        : null;
    if (next != _focus) setState(() => _focus = next);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (!widget.active) return;
    // Only a press that actually began a selection may commit. Without this,
    // releasing a *secondary* button — or releasing after a press that landed
    // on the chip and was ignored — would commit whatever the hover happened
    // to be highlighting, snapping a window the user never aimed at.
    if (_anchor == null) return;
    final t = _effectiveTarget;
    setState(() => _anchor = null);
    if (t != null) widget.onCommit(t);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    // An interrupted drag returns to hover; it must not tear the session down,
    // but native's press lock must be released too, or becameActive stays
    // suppressed for the rest of the session.
    widget.onEndDrag();
    setState(() {
      _anchor = null;
      _focus = null;
    });
  }

  /// The hovered/dragged block, treating a bare hover as a 1x1 selection.
  CellBlock? get _effectiveBlock {
    final f = _focus;
    if (f == null) return null;
    return blockFrom(_anchor ?? f, f);
  }

  @override
  Widget build(BuildContext context) {
    final block = _effectiveBlock;
    final preview = block == null
        ? null
        : previewToLocal(
            targetRect(block, widget.displayFrame,
                cols: widget.cols, rows: widget.rows, gap: widget.gap),
            widget.displayFrame);
    final dim = widget.active ? 1.0 : 0.4;
    final dragging = _anchor != null;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerHover: _onPointerHover,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Opacity(
        opacity: dim,
        child: Stack(
          children: [
            if (preview != null)
              Positioned.fromRect(
                rect: preview,
                // A filled tint, not an outline: it is read peripherally while
                // the eyes are on the grid. Nothing else is dimmed.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF8CCDFF).withValues(alpha: 0.34),
                    border: Border.all(
                        color: const Color(0xFFBEE6FF).withValues(alpha: 0.75)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            // Background, chip and cells are three siblings placed straight
            // from _panelRect/_chipRect/_cellsRect, rather than one widget
            // whose internal Padding+Column merely *implied* those rects. The
            // implied version was the bug: pointToCell used _panelRect's own
            // maths as a stand-in for where the cells were actually painted,
            // and the two only ever agreed by coincidence.
            Positioned.fromRect(
              rect: _panelRect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Plain alpha, not vibrancy: an NSVisualEffectView here is
                  // the panel's contentView and would frost the whole screen,
                  // and M4 measured its cost at 2.6-12.2 % CPU for the
                  // overlay's whole visible life.
                  color: const Color(0xFF18181C).withValues(alpha: 0.80),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 12)),
                  ],
                ),
              ),
            ),
            // Deliberately *outside* the panel, positioned from its bottom
            // edge rather than added to its height. Growing the panel would
            // move `_cellsRect`, and the comment on that getter records what it
            // cost the last time what-is-drawn and what-is-clickable drifted
            // apart. A caption under a HUD costs nothing and risks nothing.
            if (widget.saveHint)
              Positioned.fromRect(
                rect: Rect.fromLTWH(
                    _panelRect.left, _panelRect.bottom + 7, _panelRect.width, 14),
                child: Text(
                  '⌘S  save this shape as a shortcut',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            Positioned.fromRect(
              rect: _chipRect,
              child: Row(
                children: [
                  if (widget.appIcon != null) ...[
                    // Fixed box + contain: a non-square or oddly padded icon
                    // letterboxes rather than distorting.
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: Image.memory(widget.appIcon!, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(widget.appName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Positioned.fromRect(
              rect: _cellsRect,
              child: CustomPaint(
                key: GridOverlay.cellsKey,
                painter: _GridPainter(
                    block: block,
                    dragging: dragging,
                    cols: widget.cols,
                    rows: widget.rows),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.block,
    required this.dragging,
    required this.cols,
    required this.rows,
  });

  final int cols;
  final int rows;
  final CellBlock? block;

  /// True for an active press/drag, false for a bare hover. Distinguishes the
  /// committed-looking cyan block from the lighter provisional tint below —
  /// without it, a hover would read as though a drag had already happened.
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    final bg = Paint()..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
        bg);

    final b = block;
    if (b != null) {
      final rect = Rect.fromLTWH(b.c0 * cellW, b.r0 * cellH,
          (b.c1 - b.c0 + 1) * cellW, (b.r1 - b.r0 + 1) * cellH);
      if (dragging) {
        canvas.drawRect(
            rect, Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.34));
        canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(0xFF00E5FF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      } else {
        // Hover is provisional, not committed: a soft fill with no border,
        // deliberately weak enough to read as "the pointer is here" rather
        // than "this is what you get" — Divvy's cue for the same distinction.
        canvas.drawRect(
            rect, Paint()..color = Colors.white.withValues(alpha: 0.14));
      }
    }

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..strokeWidth = 1;
    for (var c = 1; c < cols; c++) {
      canvas.drawLine(
          Offset(c * cellW, 0), Offset(c * cellW, size.height), line);
    }
    for (var r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * cellH), Offset(size.width, r * cellH), line);
    }
  }

  /// [cols] and [rows] belong here as much as the selection does.
  ///
  /// This panel is resident, so a settings change arrives as an *update* to the
  /// live widget — and the cell area's size comes from the display's aspect
  /// ratio, not the column count (`gridCellsSizeFor`), so 6x6 → 4x4 leaves the
  /// CustomPaint exactly the same size. No relayout means no repaint of its
  /// own, so omitting these left the grid drawing six columns of lines over a
  /// four-column hit test until a hover happened to change `block`.
  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.block != block ||
      old.dragging != dragging ||
      old.cols != cols ||
      old.rows != rows;
}
