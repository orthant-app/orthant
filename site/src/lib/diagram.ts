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
 * Extra room below the frame, reserved ONLY when a combo label is drawn.
 *
 * The combo `<text>` sits at y = FRAME.height + PAD (101) with a hanging
 * baseline, so its glyphs extend DOWN from that point rather than up: a
 * hanging baseline is near the top of the em box, so almost the whole
 * 9px font-size renders below y=101 (measured ~9 units of actual ink).
 * `COMBO_ROOM` extends the viewBox to actually CONTAIN that ink, rather than
 * relying on `overflow: visible` to let it spill into whatever sits below
 * the element in the page -- which scales with the diagram's own rendered
 * width and cannot be compensated by a fixed-px CSS margin at the call site.
 *
 * Gated on `o.combo` in `regionSvg`, not applied unconditionally: the nine
 * keymap diagrams carry no combo, and `width: 100%; height: auto` means a
 * taller viewBox is a visible reshape for them, not just a bigger box.
 */
const COMBO_ROOM = 11;

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
  const viewBoxHeight = FRAME.height + PAD * 2 + (o.combo ? COMBO_ROOM : 0);
  const parts = [
    `<svg class="region" viewBox="${-PAD} ${-PAD} ${FRAME.width + PAD * 2} ${viewBoxHeight}" role="img" aria-label="${escape(o.title)}">`,
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
