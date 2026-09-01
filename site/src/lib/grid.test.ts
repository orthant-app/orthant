import { describe, expect, it } from 'vitest';
import { gapForPlacement, gridBlock } from './grid';

const FRAME = { x: 0, y: 0, width: 1000, height: 800 };

describe('gridBlock', () => {
  it('places the left half of a 2x2 grid with no gap', () => {
    expect(gridBlock(FRAME, { cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1 }))
      .toEqual({ x: 0, y: 0, width: 500, height: 800 });
  });

  it('places the left half with a 10 pt gap', () => {
    expect(gridBlock(FRAME, { cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, gap: 10 }))
      .toEqual({ x: 10, y: 10, width: 485, height: 780 });
  });

  it('places the bottom-right quarter', () => {
    expect(gridBlock(FRAME, { cols: 2, rows: 2, c0: 1, c1: 1, r0: 1, r1: 1 }))
      .toEqual({ x: 500, y: 400, width: 500, height: 400 });
  });

  // The property the whole custom-region feature rests on: the result depends
  // only on the fractions, never on the denominators they are written in.
  it.each([0, 8, 64])('gives the same left two-thirds on 3 and 12 columns at gap %i', (gap) => {
    const frame = { x: 0, y: 0, width: 1200, height: 900 };
    const thirds = gridBlock(frame, { cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0, gap });
    const twelfths = gridBlock(frame, { cols: 12, rows: 1, c0: 0, c1: 7, r0: 0, r1: 0, gap });
    expect(twelfths.x).toBeCloseTo(thirds.x, 6);
    expect(twelfths.width).toBeCloseTo(thirds.width, 6);
  });
});

describe('gapForPlacement', () => {
  it('is zero when no gap is asked for', () => {
    expect(gapForPlacement(FRAME, { cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0 })).toBe(0);
  });

  it('passes a modest gap through unchanged', () => {
    expect(gapForPlacement(FRAME, { cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, gap: 10 })).toBe(10);
  });

  // 12 rows at 64 pt needs 832 pt of gutter, which a 775 pt frame does not
  // have. Unclamped, the Dart original produced a cell height of -4.75.
  it('reduces a gap that would produce a cell below the 40 pt floor', () => {
    const tall = { x: 0, y: 0, width: 1000, height: 775 };
    const g = gapForPlacement(tall, { cols: 12, rows: 12, c0: 0, c1: 0, r0: 0, r1: 0, gap: 64 });
    expect(g).toBeLessThan(64);
    const cell = gridBlock(tall, { cols: 12, rows: 12, c0: 0, c1: 0, r0: 0, r1: 0, gap: 64 });
    expect(cell.height).toBeGreaterThanOrEqual(40 - 1e-9);
  });

  it('measures the block, not the grid — a half-screen block keeps its gap', () => {
    const tall = { x: 0, y: 0, width: 1000, height: 775 };
    const wide = gapForPlacement(tall, { cols: 12, rows: 12, c0: 0, c1: 5, r0: 0, r1: 5, gap: 64 });
    const cell = gapForPlacement(tall, { cols: 12, rows: 12, c0: 0, c1: 0, r0: 0, r1: 0, gap: 64 });
    expect(wide).toBeGreaterThan(cell);
  });
});
