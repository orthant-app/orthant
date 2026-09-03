import { describe, expect, it } from 'vitest';
import { regionSvg } from './diagram';
import { gridBlock } from './grid';

const FRAME = { x: 0, y: 0, width: 100, height: 100 };

describe('regionSvg', () => {
  it('emits one svg element with an accessible title', () => {
    const svg = regionSvg({ cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, title: 'Left half' });
    expect(svg.startsWith('<svg ')).toBe(true);
    expect(svg).toContain('role="img"');
    expect(svg).toContain('<title>Left half</title>');
  });

  // The whole point of the module: the drawn rect is gridBlock's output, not a
  // hand-placed rectangle that happens to look similar.
  it('places the filled rect exactly where gridBlock does', () => {
    const o = { cols: 4, rows: 3, c0: 0, c1: 1, r0: 0, r1: 2 };
    const want = gridBlock(FRAME, { ...o, gap: 0 });
    const svg = regionSvg({ ...o, title: 'Left half' });
    const fill = /<rect class="fill"[^>]*x="([\d.]+)"[^>]*y="([\d.]+)"[^>]*width="([\d.]+)"[^>]*height="([\d.]+)"/.exec(svg);
    expect(fill, 'no fill rect emitted').not.toBeNull();
    expect(parseFloat(fill![1])).toBeCloseTo(want.x, 4);
    expect(parseFloat(fill![2])).toBeCloseTo(want.y, 4);
    expect(parseFloat(fill![3])).toBeCloseTo(want.width, 4);
    expect(parseFloat(fill![4])).toBeCloseTo(want.height, 4);
  });

  it('draws one cell outline per cell', () => {
    const svg = regionSvg({ cols: 4, rows: 3, c0: 0, c1: 0, r0: 0, r1: 0, title: 'x' });
    expect(svg.match(/class="cell"/g)).toHaveLength(12);
  });

  // CSP: style-src 'self' drops style attributes, so the SVG must be styled by
  // class only. A style attribute here would be silently ignored and the
  // diagram would render as an unstyled outline.
  it('carries no style attribute', () => {
    const svg = regionSvg({ cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, title: 'x', label: '1/2', combo: '⌃⌥←' });
    expect(svg).not.toMatch(/ style="/);
  });

  it('escapes text so a title cannot inject markup', () => {
    const svg = regionSvg({ cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, title: 'a<b>&c' });
    expect(svg).toContain('<title>a&lt;b&gt;&amp;c</title>');
    expect(svg).not.toContain('<b>');
  });

  // The title goes into an ATTRIBUTE as well as an element, so escaping < & >
  // is not enough: an unescaped quote closes aria-label and everything after
  // it becomes markup.
  it('escapes quotes, since the title is also an attribute value', () => {
    const svg = regionSvg({ cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, title: '" onload="x' });
    expect(svg).toContain('aria-label="&quot; onload=&quot;x"');
    expect(svg).not.toContain('onload="x"');
  });

  // Unlike title, label and combo land ONLY in element text
  // (`<text class="label">…</text>` / `<text class="combo">…</text>`) — never
  // in an attribute — so the defect that applies to them is the same one the
  // "escapes text" test above covers for title (markup injection via <, > or
  // &), not the quote/attribute-breakout defect the test above this one
  // covers. There is no attribute for a quote to break out of here; the
  // relevant risk is a caller-supplied label or combo injecting a tag.
  it('escapes label and combo, which only ever land in element text', () => {
    const svg = regionSvg({
      cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, title: 'x',
      label: 'a<b>&c',
      combo: 'd<e>&f',
    });
    expect(svg).toContain('<text class="label" x="50" y="50">a&lt;b&gt;&amp;c</text>');
    expect(svg).not.toContain('<b>');
    expect(svg).toContain('<text class="combo" x="50" y="101">d&lt;e&gt;&amp;f</text>');
    expect(svg).not.toContain('<e>');
  });

  // A hanging-baseline combo label renders BELOW its y coordinate, and
  // `overflow: visible` used to let that ink spill into whatever the page put
  // below the element -- an overlap that scales with the diagram's own
  // rendered width and cannot be compensated by a fixed-px CSS margin at the
  // call site (measured on the real page: 18.6px at 1440px, but -29.41px --
  // WORSE -- at 759px, where the single-column layout renders the diagram at
  // its widest). The viewBox itself must contain the label instead.
  it('extends the viewBox to actually contain the combo label, not merely avoid clipping it via overflow', () => {
    const withCombo = regionSvg({ cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, title: 'x', combo: '⌃⌥←' });
    const withoutCombo = regionSvg({ cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, title: 'x' });
    const bottomOf = (svg: string) => {
      const [, minY, , height] = /viewBox="([^"]+)"/.exec(svg)![1].split(' ').map(Number);
      return minY + height;
    };
    const comboBottom = bottomOf(withCombo);
    const plainBottom = bottomOf(withoutCombo);
    expect(comboBottom).toBeGreaterThan(plainBottom);
    // The label sits at y=101 with a hanging baseline, so its glyphs extend
    // DOWN from there by close to the font's own size (9). The box must
    // reach past that point, not merely be taller than before.
    expect(comboBottom).toBeGreaterThanOrEqual(101 + 9);
  });

  // The nine keymap diagrams never pass `combo`, and the SVG is
  // `width: 100%; height: auto` -- a taller viewBox for them would be a
  // visible reshape, not just a bigger box, so this must be an EXACT match to
  // today's square viewBox rather than merely "not taller".
  it('keeps the exact viewBox when no combo is given, so the nine keymap glyphs never reshape', () => {
    const svg = regionSvg({ cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 0, title: 'x' });
    expect(/viewBox="([^"]+)"/.exec(svg)![1]).toBe('-1 -1 102 102');
  });
});
