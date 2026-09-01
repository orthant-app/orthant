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

export function attachHero(root: HTMLElement): void {
  const grid = root.querySelector<HTMLElement>('#hero-grid');
  const windowEl = root.querySelector<HTMLElement>('#hero-window');
  const activate = root.querySelector<HTMLButtonElement>('#hero-activate');
  const instructions = root.querySelector<HTMLElement>('#hero-instructions');
  const status = root.querySelector<HTMLElement>('#hero-status');
  if (!grid || !windowEl || !activate || !instructions || !status) return;

  const cols = Number(grid.dataset.cols);
  const rows = Number(grid.dataset.rows);
  let selection: Selection = { c0: 0, c1: 1, r0: 0, r1: rows - 1 };
  let active = false;
  let anchor = { col: 0, row: 0 };
  let cursor = { col: 1, row: rows - 1 };
  let dragging = false;

  /**
   * State captured at pointerdown so a cancelled gesture can be undone.
   *
   * `touch-action: pan-y` means the browser may decide mid-gesture that a
   * vertical swipe is a page scroll. It takes the gesture over and fires
   * `pointercancel` — but pointerdown has already run by then, so without this
   * a swipe past the hero would leave the selection changed and the widget
   * activated. Restoring here is what makes the touch promise true.
   */
  let beforeDrag: { selection: Selection; anchor: typeof anchor; cursor: typeof cursor; active: boolean; style: string } | null = null;

  const rowEls = Array.from(grid.querySelectorAll<HTMLElement>('.row'));
  const cellEls = Array.from(grid.querySelectorAll<HTMLElement>('.cell'));

  function paint() {
    const rect = gridBlock(FRAME, { cols, rows, ...selection, gap: GAP });
    windowEl!.style.left = `${(rect.x / FRAME.width) * 100}%`;
    windowEl!.style.top = `${(rect.y / FRAME.height) * 100}%`;
    windowEl!.style.width = `${(rect.width / FRAME.width) * 100}%`;
    windowEl!.style.height = `${(rect.height / FRAME.height) * 100}%`;
    if (!active) return;
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
   * Apply the WAI-ARIA grid pattern — but only while active.
   *
   * The roles go on at activation rather than at rest for the same reason
   * role="application" is never used at all: announcing an interactive grid to
   * a screen reader before the gate has run contradicts the promise that this
   * is an ordinary piece of page content until asked otherwise.
   *
   * Focus is managed with aria-activedescendant rather than roving tabindex, so
   * the twelve cells never enter the tab order.
   */
  function enter() {
    if (active) return;
    active = true;
    grid!.setAttribute('role', 'grid');
    grid!.setAttribute('tabindex', '0');
    grid!.setAttribute('aria-label', 'Window placement grid');
    grid!.setAttribute('aria-multiselectable', 'true');
    for (const row of rowEls) row.setAttribute('role', 'row');
    for (const cell of cellEls) cell.setAttribute('role', 'gridcell');
    instructions!.removeAttribute('hidden');
    grid!.focus();
    paint();
  }

  function exit() {
    if (!active) return;
    active = false;
    // Otherwise Esc during a mouse drag leaves `dragging` true, and the
    // pointerup that follows announces a placement for a widget that is no
    // longer active.
    dragging = false;
    beforeDrag = null;
    for (const attribute of [
      'role', 'tabindex', 'aria-label', 'aria-multiselectable', 'aria-activedescendant',
    ]) {
      grid!.removeAttribute(attribute);
    }
    for (const row of rowEls) row.removeAttribute('role');
    for (const cell of cellEls) {
      cell.removeAttribute('role');
      cell.removeAttribute('aria-selected');
    }
    instructions!.setAttribute('hidden', '');
  }

  activate.removeAttribute('hidden'); // the control exists only once it works
  activate.addEventListener('click', enter);

  grid.addEventListener('blur', exit);

  grid.addEventListener('keydown', (event: KeyboardEvent) => {
    if (!active) return;

    if (event.key === 'Escape') {
      event.preventDefault();
      exit();
      activate.focus();
      return;
    }

    if (event.key === 'Enter') {
      event.preventDefault();
      status.textContent = `Window placed: ${describe(selection, cols, rows)}.`;
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
    beforeDrag = { selection: { ...selection }, anchor: { ...anchor }, cursor: { ...cursor }, active, style: windowEl!.style.cssText };
    // A pointer press is as deliberate as pressing the button, so it performs
    // the SAME transition. Mutating the grid without it would leave a state
    // that is interactive by mouse while still claiming to be dormant —
    // no instructions, no grid semantics, no Esc route out.
    enter();
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
    // Put back exactly what was on the element, rather than assuming a
    // cancelled gesture means "return to the CSS default". That assumption
    // holds only until the first deliberate exit: `exit()` never touches
    // `selection`, so after activate -> move -> Esc the widget parks at a
    // non-default position with `selection` agreeing. Clearing there would
    // desync them and make the NEXT activation jump.
    //
    // At rest for the first time this snapshot is '', so the inline styles
    // painted by pointerdown are still cleared — which is the case that
    // matters on touch: without it, a swipe reclaimed as a page scroll leaves
    // the window wherever the finger landed.
    windowEl!.style.cssText = snapshot.style;
    if (!snapshot.active) exit();
    else paint();
  });

  grid.addEventListener('pointermove', (event: PointerEvent) => {
    if (!dragging || !active) return;
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
    status.textContent = `Window placed: ${describe(selection, cols, rows)}.`;
  });

  // No paint() here. While dormant the window's position comes from the
  // stylesheet (see Hero.astro's .window rule and hero-default.test.ts), and
  // painting would write aria state onto a grid that is not yet a grid.
  // enter() paints.
}
