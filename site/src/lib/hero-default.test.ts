import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { gridBlock } from './grid';

/** Points, matching hero.ts. gapForPlacement enforces a 40 pt minimum cell, so
 *  a percentage-space frame would compare a 40 "point" floor against a 100-unit
 *  screen and clamp nonsensically. */
const FRAME = { x: 0, y: 0, width: 1600, height: 1000 };

describe('the hero\'s resting selection', () => {
  it('matches gridBlock for the left half', () => {
    const css = readFileSync('src/components/Hero.astro', 'utf8');
    const rule = /\.preview\s*\{([^}]*)\}/.exec(css);
    expect(rule, '.preview rule not found in Hero.astro').not.toBeNull();

    const value = (prop: string) => {
      const m = new RegExp(`(?:^|;|\\s)${prop}:\\s*([\\d.]+)%`).exec(rule![1]);
      expect(m, `${prop} not found in the .preview rule`).not.toBeNull();
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

describe('the hero\'s demo does not move the page under the reader', () => {
  // The reveal-on-activate instructions line pushed everything below the hero
  // down the moment the grid was touched. Nothing in the demo may start
  // hidden: with the controller absent the markup has to be a complete,
  // readable figure, and with it present the same words are already in place.
  it('ships no hidden element in the figure', () => {
    const source = readFileSync('src/components/Hero.astro', 'utf8');
    const figure = /<figure class="demo">([\s\S]*?)<\/figure>/.exec(source);
    expect(figure, '<figure class="demo"> not found in Hero.astro').not.toBeNull();
    expect(figure![1]).not.toMatch(/\shidden(\s|>|=)/);
  });
});

describe('the hero\'s resting selection is visible without JavaScript', () => {
  /*
   * `aria-selected` is written only by paint(), so with the controller absent
   * every cell renders at the same unselected tint while the preview — whose
   * geometry IS a CSS constant — shows a left-half placement. The scene
   * contradicts itself. This asserts the CSS carries the selection too.
   */
  it('tints the resting selection from CSS, retiring once the controller attaches', () => {
    const css = readFileSync('src/components/Hero.astro', 'utf8');
    const rule = /\.grid:not\(\[data-ready\]\)[^{]*\.cell:nth-child\(-n \+ (\d+)\)\s*\{([^}]*)\}/.exec(css);
    expect(rule, 'no no-JS resting-selection rule found in Hero.astro').not.toBeNull();
    expect(rule![2]).toContain('--accent');

    // The count must equal the default selection's width, or the CSS and the
    // controller disagree about what "resting" means.
    const COLS = 4;
    const r = gridBlock(FRAME, { cols: COLS, rows: 3, c0: 0, c1: 1, r0: 0, r1: 2, gap: 12 });
    const columnsCovered = Math.round((r.width / FRAME.width) * COLS);
    expect(Number(rule![1])).toBe(columnsCovered);
  });
});

describe('the hero puts the scene before the supporting copy on small screens', () => {
  // Design-gate finding 1: at 320px the old single .copy block (eyebrow, h1,
  // lede, cta) pushed the figure ~636px down the page — copy before any
  // demonstration. The DOM must read eyebrow+h1, THEN the figure, THEN
  // lede+cta, so a reader (and Tab) meets the scene right after the headline.
  it('orders leading copy, then the figure, then trailing copy in the DOM', () => {
    const source = readFileSync('src/components/Hero.astro', 'utf8');
    const lead = source.indexOf('class="copy-lead"');
    const figure = source.indexOf('<figure class="demo">');
    const trail = source.indexOf('class="copy-trail"');
    expect(lead, 'copy-lead not found in Hero.astro').toBeGreaterThan(-1);
    expect(figure, 'figure not found in Hero.astro').toBeGreaterThan(-1);
    expect(trail, 'copy-trail not found in Hero.astro').toBeGreaterThan(-1);
    expect(lead).toBeLessThan(figure);
    expect(figure).toBeLessThan(trail);
  });

  // The cheap way to reorder visually is CSS `order` or `flex-direction:
  // column-reverse` — both leave focus order following SOURCE order, so Tab
  // would jump backwards from the CTA to the grid above it, trading this
  // finding for a worse one (the gate praised the hero's keyboard semantics).
  // Scoped to the <style> block only: the template above this describes the
  // very thing being forbidden, so scanning the whole file would trip on its
  // own comment.
  it('never uses `order:` or `column-reverse` to fake the reorder', () => {
    const source = readFileSync('src/components/Hero.astro', 'utf8');
    const styleMatch = /<style>([\s\S]*)<\/style>/.exec(source);
    expect(styleMatch, '<style> block not found in Hero.astro').not.toBeNull();
    const css = styleMatch![1];
    // \b(not just /order:/) so a legitimate `border:` declaration — which
    // contains "order:" as a literal substring — does not false-positive.
    expect(css).not.toMatch(/\border\s*:/);
    expect(css).not.toMatch(/column-reverse/);
  });
});

describe('the hero\'s touch targets clear WCAG 2.2 SC 2.5.8 at 320px', () => {
  // Design-gate finding 3b: the panel was 46% of the scene at every width, and
  // at a 320px viewport that produced ~27.3 x 22.7px cells — the HEIGHT axis
  // fell short of the 24px floor. This recomputes both axes from the same
  // percentages, paddings, gaps and aspect-ratio the component's CSS declares
  // (parsed from source, not a hardcoded pixel target) so a later change to
  // any one of them is caught here rather than silently invalidating a magic
  // number. The formula is plain CSS box-model arithmetic: percentage widths,
  // border-box padding, an aspect-ratio height, and flexbox `gap`.
  it('gives the grid cells a 24x24 box at a 320px viewport', () => {
    const VIEWPORT = 320;
    const COLS = 4;
    const ROWS = 3;

    const css = readFileSync('src/components/Hero.astro', 'utf8');
    const tokens = readFileSync('src/styles/tokens.css', 'utf8');

    const gutter = Number(/--gutter:\s*([\d.]+)px/.exec(tokens)![1]);

    const sceneBody = /\.scene\s*\{([^}]*)\}/.exec(css)![1];
    const sceneBorder = Number(/border:\s*([\d.]+)px/.exec(sceneBody)![1]);

    // The BASE .panel rule (padding), matched before any @media block that
    // also declares `.panel { ... }` — it appears first in the source.
    const panelBody = /\.panel\s*\{([^}]*)\}/.exec(css)![1];
    const panelPadding = Number(/padding:\s*([\d.]+)px/.exec(panelBody)![1]);

    // The small-screen override that widens the panel. Matched as its own
    // dedicated `@media (max-width) { .panel { width } }` block so this
    // regex cannot confuse it with the desktop .hero query or the base rule.
    const media =
      /@media \(max-width:\s*(\d+)px\)\s*\{\s*\.panel\s*\{\s*width:\s*([\d.]+)%;?\s*\}\s*\}/.exec(css);
    expect(media, 'no small-screen .panel width override found in Hero.astro').not.toBeNull();
    const breakpoint = Number(media![1]);
    const panelFraction = Number(media![2]) / 100;
    expect(breakpoint, 'the override must actually cover a 320px viewport').toBeGreaterThanOrEqual(
      VIEWPORT,
    );

    const gridBody = /\.grid\s*\{([^}]*)\}/.exec(css)![1];
    const [, aspectW, aspectH] = /aspect-ratio:\s*([\d.]+)\s*\/\s*([\d.]+)/.exec(gridBody)!;
    const rowGap = Number(/gap:\s*([\d.]+)px/.exec(gridBody)![1]); // between ROWS

    const rowRuleBody = /\.row\s*\{([^}]*)\}/.exec(css)![1];
    const cellGap = Number(/gap:\s*([\d.]+)px/.exec(rowRuleBody)![1]); // between CELLS in a row

    // The figure fills the whole single-column width below the 980px
    // breakpoint (grid-template-columns: minmax(0, 1fr), .demo { margin: 0 }),
    // so the scene's content width is the page's content width.
    const contentWidth = VIEWPORT - 2 * gutter;
    const sceneWidth = contentWidth;
    const desktopWidth = sceneWidth - 2 * sceneBorder;
    const panelWidth = panelFraction * desktopWidth;
    const gridWidth = panelWidth - 2 * panelPadding;
    const gridHeight = (gridWidth * Number(aspectH)) / Number(aspectW);
    const cellWidth = (gridWidth - (COLS - 1) * cellGap) / COLS;
    const cellHeight = (gridHeight - (ROWS - 1) * rowGap) / ROWS;

    expect(cellWidth).toBeGreaterThanOrEqual(24);
    expect(cellHeight).toBeGreaterThanOrEqual(24);
  });
});
