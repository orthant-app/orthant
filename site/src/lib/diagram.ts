import { gridBlock, type Rect } from './grid';

/**
 * A region diagram, rendered from the app's own geometry.
 *
 * The filled rect is `gridBlock`'s output, not a hand-placed rectangle: the
 * same function that decides where Orthant puts a window decides where the
 * picture puts it, so the picture cannot claim something the app does not do.
 *
 * Rendered to a string at build time. No client JS, which keeps it inside
 * `script-src 'self'` and visible with JavaScript disabled. Styled by class
 * only, because `style-src 'self'` drops style attributes.
 */
export interface DiagramOptions {
  cols: number;
  rows: number;
  c0: number;
  c1: number;
  r0: number;
  r1: number;
  /** Accessible name. Required: a diagram nobody can read is decoration. */
  title: string;
  /** Optional annotation under the frame, e.g. "1/2 x 1". */
  label?: string;
  /** Optional key combination, e.g. "⌃⌥←". */
  combo?: string;
}

/** The diagram's own coordinate space. Unitless; the SVG scales to its box. */
const FRAME: Rect = { x: 0, y: 0, width: 100, height: 100 };
const PAD = 1;

/**
 * Escape for both element text and attribute values.
 *
 * The quote matters: `title` is interpolated into `aria-label="…"` as well as
 * into `<title>`, and an unescaped `"` closes the attribute and turns the rest
 * of the string into markup.
 */
function escape(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const n = (v: number) => Number(v.toFixed(4));

export function regionSvg(o: DiagramOptions): string {
  const cells: string[] = [];
  for (let r = 0; r < o.rows; r++) {
    for (let c = 0; c < o.cols; c++) {
      const cell = gridBlock(FRAME, { cols: o.cols, rows: o.rows, c0: c, c1: c, r0: r, r1: r });
      cells.push(
        `<rect class="cell" x="${n(cell.x)}" y="${n(cell.y)}" ` +
          `width="${n(cell.width)}" height="${n(cell.height)}" />`,
      );
    }
  }

  const fill = gridBlock(FRAME, { cols: o.cols, rows: o.rows, c0: o.c0, c1: o.c1, r0: o.r0, r1: o.r1 });
  const parts = [
    `<svg class="region" viewBox="${-PAD} ${-PAD} ${FRAME.width + PAD * 2} ${FRAME.height + PAD * 2}" role="img" aria-label="${escape(o.title)}">`,
    `<title>${escape(o.title)}</title>`,
    ...cells,
    `<rect class="fill" x="${n(fill.x)}" y="${n(fill.y)}" width="${n(fill.width)}" height="${n(fill.height)}" />`,
  ];
  if (o.label) {
    parts.push(`<text class="label" x="${n(FRAME.width / 2)}" y="${n(FRAME.height / 2)}">${escape(o.label)}</text>`);
  }
  if (o.combo) {
    parts.push(`<text class="combo" x="${n(FRAME.width / 2)}" y="${n(FRAME.height + PAD)}">${escape(o.combo)}</text>`);
  }
  parts.push('</svg>');
  return parts.join('');
}
