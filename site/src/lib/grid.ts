export interface Rect { x: number; y: number; width: number; height: number }

export interface BlockOptions {
  cols: number; rows: number;
  c0: number; c1: number; r0: number; r1: number;
  gap?: number;
}

/** The smallest cell a placement may produce, in points. */
const MIN_PLACED_CELL = 40;

/**
 * The gap `gridBlock` will actually use. A direct port of
 * `gapForPlacement` in lib/core/geometry.dart:103.
 *
 * Measured against the BLOCK, not the grid, which is what keeps placement free
 * of the denominators it was written in: expand gridBlock with f = span / n and
 * `cols` cancels out entirely, so this clamp is the only path by which a
 * denominator could reach the result.
 */
export function gapForPlacement(frame: Rect, o: BlockOptions): number {
  const gap = o.gap ?? 0;
  if (gap <= 0) return 0;
  const limit = (extent: number, n: number, span: number) =>
    (span * extent - MIN_PLACED_CELL * n) / (span + n);
  const w = limit(frame.width, o.cols, o.c1 - o.c0 + 1);
  const h = limit(frame.height, o.rows, o.r1 - o.r0 + 1);
  const most = w < h ? w : h;
  if (most <= 0) return 0;
  return gap < most ? gap : most;
}

/**
 * The rect of cell block c0..c1 × r0..r1 on a cols×rows grid over `frame`.
 * A direct port of `gridBlock` in lib/core/geometry.dart:148.
 */
export function gridBlock(frame: Rect, o: BlockOptions): Rect {
  const gap = gapForPlacement(frame, o);
  const usableX = frame.x + gap;
  const usableY = frame.y + gap;
  const usableW = frame.width - 2 * gap;
  const usableH = frame.height - 2 * gap;
  const cellW = (usableW - (o.cols - 1) * gap) / o.cols;
  const cellH = (usableH - (o.rows - 1) * gap) / o.rows;
  return {
    x: usableX + o.c0 * (cellW + gap),
    y: usableY + o.r0 * (cellH + gap),
    width: (o.c1 - o.c0 + 1) * cellW + (o.c1 - o.c0) * gap,
    height: (o.r1 - o.r0 + 1) * cellH + (o.r1 - o.r0) * gap,
  };
}
