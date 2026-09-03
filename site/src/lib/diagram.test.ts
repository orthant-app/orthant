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
});
