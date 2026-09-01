import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { gridBlock } from './grid';

/** Points, matching hero.ts. gapForPlacement enforces a 40 pt minimum cell, so
 *  a percentage-space frame would compare a 40 "point" floor against a 100-unit
 *  screen and clamp nonsensically. */
const FRAME = { x: 0, y: 0, width: 1600, height: 1000 };

describe('the hero\'s dormant selection', () => {
  it('matches gridBlock for the left half', () => {
    const css = readFileSync('src/components/Hero.astro', 'utf8');
    const rule = /\.window\s*\{([^}]*)\}/.exec(css);
    expect(rule, '.window rule not found in Hero.astro').not.toBeNull();

    const value = (prop: string) => {
      const m = new RegExp(`(?:^|;|\\s)${prop}:\\s*([\\d.]+)%`).exec(rule![1]);
      expect(m, `${prop} not found in the .window rule`).not.toBeNull();
      return parseFloat(m![1]);
    };

    const r = gridBlock(FRAME, { cols: 4, rows: 3, c0: 0, c1: 1, r0: 0, r1: 2, gap: 12 });
    expect(value('left')).toBeCloseTo((r.x / FRAME.width) * 100, 4);
    expect(value('top')).toBeCloseTo((r.y / FRAME.height) * 100, 4);
    expect(value('width')).toBeCloseTo((r.width / FRAME.width) * 100, 4);
    expect(value('height')).toBeCloseTo((r.height / FRAME.height) * 100, 4);
  });

  it('never reintroduces a style attribute, which CSP would drop', () => {
    const source = readFileSync('src/components/Hero.astro', 'utf8');
    expect(source).not.toMatch(/id="hero-window"[^>]*style=/);
  });
});
