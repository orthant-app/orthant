import { gridBlock, type Rect } from './grid';

// Points, matching Hero.astro. gapForPlacement enforces a 40 pt minimum cell,
// so the frame must be in the app's own units or the floor compares against a
// percentage box and clamps nonsensically.
const FRAME: Rect = { x: 0, y: 0, width: 1600, height: 1000 };
const GAP = 12;

interface Selection { c0: number; c1: number; r0: number; r1: number }

const NAMES: Record<string, string> = {
  '0,1,0,2': 'left half',
  '2,3,0,2': 'right half',
  '0,3,0,0': 'top third',
  '0,3,0,2': 'full screen',
};

function describe(s: Selection, cols: number, rows: number): string {
  const named = NAMES[`${s.c0},${s.c1},${s.r0},${s.r1}`];
  if (named) return named;
  const w = s.c1 - s.c0 + 1;
  const h = s.r1 - s.r0 + 1;
  return `${w} of ${cols} columns, ${h} of ${rows} rows`;
}

/** A span as a reduced fraction, for annotation: 2 of 4 -> "1/2". */
function fraction(span: number, of: number): string {
  const gcd = (a: number, b: number): number => (b === 0 ? a : gcd(b, a % b));
  const d = gcd(span, of);
  const n = span / d;
  const q = of / d;
  return q === 1 ? '1' : `${n}/${q}`;
}

/**
 * Make the hero grid work.
 *
 * There is deliberately no activation step. An earlier version gated every
 * interaction behind a "Try the grid" button placed BELOW the grid, so
 * pressing it threw focus backwards to the element above, revealed an
 * instructions line that shoved the rest of the page down, and — because a
 * pointer press on the grid ran the same transition anyway — did nothing a
 * mouse user had not already been able to do. Blur tore all of it down again.
 *
 * What the gate was actually protecting is kept, and none of it needs a button:
 *
 *   - The twelve cells stay out of the tab order. The grid is ONE tab stop and
 *     moves its cursor with `aria-activedescendant`, which is the WAI-ARIA grid
 *     pattern; a roving tabindex is what would have added twelve stops.
 *   - A vertical swipe still scrolls the page. That is `touch-action: pan-y`
 *     plus the `pointercancel` restore below, not the button.
 *   - Without JavaScript nothing here runs, so the markup stays an ordinary
 *     figure with a caption. `role`/`tabindex` are added here, never authored.
 */
export function attachHero(root: HTMLElement): void {
  const grid = root.querySelector<HTMLElement>('#hero-grid');
  const windowEl = root.querySelector<HTMLElement>('#hero-window');
  const status = root.querySelector<HTMLElement>('#hero-status');
  if (!grid || !windowEl || !status) return;

  const readout = root.querySelector<HTMLElement>('#hero-readout');
  /** The window that lands. Distinct from `windowEl`, which is the preview. */
  const placedEl = root.querySelector<HTMLElement>('#hero-placed');

  const cols = Number(grid.dataset.cols);
  const rows = Number(grid.dataset.rows);

  const DEFAULT: Selection = { c0: 0, c1: 1, r0: 0, r1: rows - 1 };
  let selection: Selection = { ...DEFAULT };
  let anchor = { col: 0, row: 0 };
  let cursor = { col: 1, row: rows - 1 };
  let dragging = false;
  let placedTimer = 0;

  /**
   * State captured at pointerdown so a cancelled gesture can be undone.
   *
   * `touch-action: pan-y` means the browser may decide mid-gesture that a
   * vertical swipe is a page scroll. It takes the gesture over and fires
   * `pointercancel` — but pointerdown has already run by then, so without this
   * a swipe past the hero would leave the selection changed. Restoring here is
   * what makes the touch promise true.
   */
  let beforeDrag: {
    selection: Selection;
    anchor: typeof anchor;
    cursor: typeof cursor;
  } | null = null;

  const rowEls = Array.from(grid.querySelectorAll<HTMLElement>('.row'));
  const cellEls = Array.from(grid.querySelectorAll<HTMLElement>('.cell'));

  /** The selection's rect, as CSS percentages of the scene. */
  function rectStyle(): { left: string; top: string; width: string; height: string } {
    const r = gridBlock(FRAME, { cols, rows, ...selection, gap: GAP });
    return {
      left: `${(r.x / FRAME.width) * 100}%`,
      top: `${(r.y / FRAME.height) * 100}%`,
      width: `${(r.width / FRAME.width) * 100}%`,
      height: `${(r.height / FRAME.height) * 100}%`,
    };
  }

  function paint() {
    const box = rectStyle();
    windowEl!.style.left = box.left;
    windowEl!.style.top = box.top;
    windowEl!.style.width = box.width;
    windowEl!.style.height = box.height;
    // Selection state is part of the grid pattern, not decoration: a screen
    // reader has no other way to know what the blue rectangle covers.
    for (const cell of cellEls) {
      const c = Number(cell.dataset.col);
      const r = Number(cell.dataset.row);
      const inside =
        c >= selection.c0 && c <= selection.c1 && r >= selection.r0 && r <= selection.r1;
      cell.setAttribute('aria-selected', String(inside));
    }
    grid!.setAttribute('aria-activedescendant', `hero-cell-${cursor.col}-${cursor.row}`);

    // Annotation, deliberately outside the simulated screen. The real overlay
    // shows no measurements (grid_overlay.dart renders only the ⌘S hint and an
    // app-name chip), so putting numbers inside it would depict a feature
    // Orthant does not have. See spec §3.5.
    if (readout) {
      const w = fraction(selection.c1 - selection.c0 + 1, cols);
      const h = fraction(selection.r1 - selection.r0 + 1, rows);
      readout.textContent = `${describe(selection, cols, rows)} · ${w} × ${h} of the screen`;
    }
  }

  function normalise() {
    selection = {
      c0: Math.min(anchor.col, cursor.col),
      c1: Math.max(anchor.col, cursor.col),
      r0: Math.min(anchor.row, cursor.row),
      r1: Math.max(anchor.row, cursor.row),
    };
  }

  /**
   * The commit the app itself performs on release or Return: `windowEl` is
   * only ever the preview that follows the selection, so it is `placedEl` —
   * the Safari window in the scene — that has to move here, or the hero is a
   * diagram instead of a demonstration (spec §4.1).
   */
  function announcePlacement() {
    status!.textContent = `Window placed: ${describe(selection, cols, rows)}.`;
    if (!placedEl) return;
    const box = rectStyle();
    placedEl.style.left = box.left;
    placedEl.style.top = box.top;
    placedEl.style.width = box.width;
    placedEl.style.height = box.height;
    placedEl.setAttribute('data-placed', '');
    clearTimeout(placedTimer);
    placedTimer = window.setTimeout(() => placedEl!.removeAttribute('data-placed'), 260);
  }

  // The WAI-ARIA grid pattern, applied once. `data-ready` is the hook the
  // stylesheet uses for the cursor and hover tint, so those appear only when
  // something is listening for them.
  grid.setAttribute('role', 'grid');
  grid.setAttribute('tabindex', '0');
  grid.setAttribute('aria-label', 'Window placement demo');
  grid.setAttribute('aria-multiselectable', 'true');
  grid.setAttribute('data-ready', '');
  for (const row of rowEls) row.setAttribute('role', 'row');
  for (const cell of cellEls) cell.setAttribute('role', 'gridcell');
  paint();

  grid.addEventListener('keydown', (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      // Nothing to dismiss on a page, so Esc means "put it back" — which the
      // hint promises, and which is the only undo a demo can offer.
      event.preventDefault();
      selection = { ...DEFAULT };
      anchor = { col: DEFAULT.c0, row: DEFAULT.r0 };
      cursor = { col: DEFAULT.c1, row: DEFAULT.r1 };
      paint();
      status.textContent = 'Reset to the left half.';
      return;
    }

    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      announcePlacement();
      return;
    }

    const step: Record<string, [number, number]> = {
      ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1],
    };
    const delta = step[event.key];
    if (!delta) return;

    event.preventDefault();
    cursor = {
      col: Math.min(cols - 1, Math.max(0, cursor.col + delta[0])),
      row: Math.min(rows - 1, Math.max(0, cursor.row + delta[1])),
    };
    if (!event.shiftKey) anchor = { ...cursor };
    normalise();
    paint();
  });

  grid.addEventListener('pointerdown', (event: PointerEvent) => {
    const cell = (event.target as HTMLElement).closest<HTMLElement>('.cell');
    if (!cell) return;
    // Snapshot BEFORE anything changes, so pointercancel can put it all back.
    beforeDrag = { selection: { ...selection }, anchor: { ...anchor }, cursor: { ...cursor } };
    dragging = true;
    grid.setPointerCapture?.(event.pointerId);
    anchor = { col: Number(cell.dataset.col), row: Number(cell.dataset.row) };
    cursor = { ...anchor };
    normalise();
    paint();
  });

  // The browser claims the gesture (a vertical swipe under `touch-action:
  // pan-y`, or a system gesture taking over). Undo everything pointerdown did:
  // the user asked to scroll the page, not to move a window.
  grid.addEventListener('pointercancel', () => {
    if (!beforeDrag) return;
    const snapshot = beforeDrag;
    dragging = false;
    beforeDrag = null;
    selection = snapshot.selection;
    anchor = snapshot.anchor;
    cursor = snapshot.cursor;
    // Restoring the three state values and repainting is the whole undo: the
    // rectangle is a pure function of `selection`, so there is nothing else to
    // put back. An earlier version also re-assigned the element's saved
    // `style.cssText`, which was load-bearing while a cancel could leave the
    // widget unpainted — it cannot now, and a mutation deleting that line
    // survived every test because it genuinely does nothing.
    paint();
  });

  grid.addEventListener('pointermove', (event: PointerEvent) => {
    if (!dragging) return;
    const cell = document
      .elementFromPoint(event.clientX, event.clientY)
      ?.closest<HTMLElement>('.cell');
    if (!cell) return;
    const next = { col: Number(cell.dataset.col), row: Number(cell.dataset.row) };
    if (next.col === cursor.col && next.row === cursor.row) return; // only on cell change
    cursor = next;
    normalise();
    paint();
  });

  grid.addEventListener('pointerup', (event: PointerEvent) => {
    if (!dragging) return;
    dragging = false;
    beforeDrag = null;
    grid.releasePointerCapture?.(event.pointerId);
    announcePlacement();
  });
}
