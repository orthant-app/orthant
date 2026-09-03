// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from 'vitest';
import { attachHero } from './hero';

function mount(): HTMLElement {
  const row = (r: number) =>
    `<div class="row" data-row="${r}">${
      Array.from({ length: 4 }, (_, c) =>
        `<div class="cell" id="hero-cell-${c}-${r}" data-col="${c}" data-row="${r}"></div>`,
      ).join('')
    }</div>`;
  document.body.innerHTML = `
    <section id="root">
      <div id="hero-grid" data-cols="4" data-rows="3" aria-describedby="hero-hint">
        ${[0, 1, 2].map(row).join('')}
        <div id="hero-window"></div>
      </div>
      <p id="hero-hint"></p>
      <div id="hero-placed"></div>
      <p id="hero-readout"></p>
      <p id="hero-status" role="status" aria-live="polite"></p>
    </section>`;
  const root = document.getElementById('root') as HTMLElement;
  attachHero(root);
  return root;
}

const $ = (id: string) => document.getElementById(id) as HTMLElement;
const grid = () => $('hero-grid');
const win = () => $('hero-window');

// NOTE: dispatched on the GRID, never on `document`. The listener is attached
// to the grid, so a document-level dispatch never reaches it and the assertion
// passes no matter what the handler does — a vacuous test that would score a
// deleted key handler as "caught".
const press = (k: string, shift = false) => {
  const event = new KeyboardEvent('keydown', {
    key: k, shiftKey: shift, bubbles: true, cancelable: true,
  });
  grid().dispatchEvent(event);
  return event;
};

const pointer = (type: string, target: Element) =>
  target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 1 }));

// happy-dom has no layout, so document.elementFromPoint always returns null and
// pointermove is a no-op. Point it at a chosen cell instead.
const at = (col: number, row: number) => {
  document.elementFromPoint = () => document.getElementById(`hero-cell-${col}-${row}`);
};

const selected = () => document.querySelectorAll('[aria-selected="true"]').length;

describe('attachHero — the widget it presents', () => {
  beforeEach(() => mount());

  /*
   * There is no activation step. The gate this replaces put a "Try the grid"
   * button BELOW the grid, which threw focus backwards, revealed an
   * instructions line that shoved the page down, and was redundant for anyone
   * with a pointer — pointerdown ran the same transition anyway.
   *
   * These four assertions are what the gate was actually protecting, none of
   * which needs a button. Losing any one of them is the reason it existed.
   */

  it('is exactly one tab stop, never twelve', () => {
    expect(grid().getAttribute('tabindex')).toBe('0');
    expect(document.querySelectorAll('.cell[tabindex]')).toHaveLength(0);
  });

  it('never uses role="application"', () => {
    expect(grid().getAttribute('role')).toBe('grid');
    expect(document.querySelector('[role="application"]')).toBeNull();
  });

  it('applies the full WAI grid structure', () => {
    expect(document.querySelectorAll('[role="row"]')).toHaveLength(3);
    expect(document.querySelectorAll('[role="gridcell"]')).toHaveLength(12);
  });

  it('names itself, so a reader reaching it is told what it is', () => {
    expect(grid().getAttribute('aria-label')).toBeTruthy();
    expect(grid().getAttribute('aria-describedby')).toBe('hero-hint');
  });

  it('marks the resting selection and cursor without being touched', () => {
    // The gate painted nothing until activation, so a reader tabbing in met a
    // grid with no selection state at all.
    expect(selected()).toBe(6); // the left half: 2 columns x 3 rows
    const id = grid().getAttribute('aria-activedescendant');
    expect(document.getElementById(id!)).not.toBeNull();
  });

  it('flags itself ready, which is what turns on the pointer affordance', () => {
    // The stylesheet hangs `cursor: crosshair` and the hover tint off this, so
    // an inert grid never claims to be draggable.
    expect(grid().hasAttribute('data-ready')).toBe(true);
  });
});

describe('attachHero — keyboard', () => {
  beforeEach(() => mount());

  it('consumes the arrow keys', () => {
    expect(press('ArrowRight').defaultPrevented).toBe(true);
  });

  it('moves the selection with an arrow', () => {
    const before = win().style.left;
    press('ArrowRight');
    expect(win().style.left).not.toBe(before);
  });

  it('extends the selection with shift-arrow', () => {
    const before = parseFloat(win().style.width);
    press('ArrowRight', true);
    expect(parseFloat(win().style.width)).toBeGreaterThan(before);
  });

  it('updates aria-selected as the selection changes', () => {
    press('ArrowRight', true);
    expect(selected()).toBe(9);
  });

  it('announces a placement on Return', () => {
    press('Enter');
    expect($('hero-status').textContent).toMatch(/placed/i);
  });

  it('marks the window placed, so Return does something visible too', () => {
    // The live region alone left Return looking broken to anyone who can see
    // the grid — the hint promises "↩ places".
    expect($('hero-placed').hasAttribute('data-placed')).toBe(false);
    press('Enter');
    expect($('hero-placed').hasAttribute('data-placed')).toBe(true);
  });

  it('Esc restores the default selection rather than merely changing it', () => {
    const pristine = win().style.cssText;
    press('ArrowRight');
    press('ArrowDown', true);
    expect(win().style.cssText).not.toBe(pristine);

    press('Escape');
    // Asserting equality with the PRISTINE geometry, not just "it moved":
    // resetting to any other cell would satisfy a looser check while breaking
    // the only undo the demo offers.
    expect(win().style.cssText).toBe(pristine);
    expect(selected()).toBe(6);
    expect($('hero-status').textContent).toMatch(/reset/i);
  });

  it('keeps focus on the grid through Esc, with nowhere else to send it', () => {
    grid().focus();
    press('Escape');
    expect(document.activeElement).toBe(grid());
    // Still live: the old design tore the widget down here, so the next arrow
    // press did nothing at all.
    expect(press('ArrowRight').defaultPrevented).toBe(true);
  });
});

describe('attachHero — pointer', () => {
  beforeEach(() => mount());

  it('a drag selects the cells it crosses', () => {
    // pointermove reads document.elementFromPoint, which happy-dom does not
    // implement — a drag test that only sends pointerdown proves nothing about
    // dragging.
    at(1, 1);
    pointer('pointerdown', $('hero-cell-0-0'));
    expect(selected()).toBe(1);
    pointer('pointermove', grid());
    expect(selected()).toBe(4); // 0..1 x 0..1
    pointer('pointerup', grid());
    expect($('hero-status').textContent).toMatch(/placed/i);
  });

  it('a press alone does not announce a placement', () => {
    pointer('pointerdown', $('hero-cell-2-1'));
    expect($('hero-status').textContent).toBe('');
  });
});

describe('attachHero — a cancelled gesture', () => {
  beforeEach(() => mount());

  /*
   * touch-action: pan-y lets the browser reclaim a vertical swipe mid-gesture.
   * pointerdown has already run by then, so without a pointercancel handler the
   * page scrolls AND the window moves — exactly the promise broken. Confirmed
   * against a real CDP touch swipe, which is how the original defect surfaced
   * while every unit assertion of the day still passed.
   */

  it('restores the resting geometry a swipe had disturbed', () => {
    const resting = win().style.cssText;
    expect(resting).not.toBe('');

    pointer('pointerdown', $('hero-cell-3-2'));
    expect(win().style.cssText).not.toBe(resting);

    pointer('pointercancel', grid());
    expect(win().style.cssText).toBe(resting);
    expect(selected()).toBe(6);
  });

  it('restores a parked position, not the default', () => {
    // The compound case: interact first, so "what was there" and "the default"
    // are different strings. A handler that reset to the default instead of the
    // snapshot passes every other test here and desyncs this one.
    press('ArrowRight');
    press('ArrowDown', true);
    const parked = win().style.cssText;

    pointer('pointerdown', $('hero-cell-0-0'));
    pointer('pointercancel', grid());
    expect(win().style.cssText).toBe(parked);
  });

  it('leaves the cursor where the cancelled press found it', () => {
    press('ArrowRight');
    const cursor = grid().getAttribute('aria-activedescendant');
    pointer('pointerdown', $('hero-cell-3-0'));
    pointer('pointercancel', grid());
    expect(grid().getAttribute('aria-activedescendant')).toBe(cursor);
  });

  it('stops a later pointerup announcing a placement that was cancelled', () => {
    pointer('pointerdown', $('hero-cell-1-1'));
    pointer('pointercancel', grid());
    pointer('pointerup', grid());
    expect($('hero-status').textContent).toBe('');
  });

  it('leaves the grid usable afterwards', () => {
    pointer('pointerdown', $('hero-cell-1-1'));
    pointer('pointercancel', grid());
    expect(grid().getAttribute('role')).toBe('grid');
    expect(press('ArrowRight').defaultPrevented).toBe(true);
  });
});

describe('attachHero — the readout', () => {
  beforeEach(() => mount());

  it('describes the resting selection without being touched', () => {
    expect($('hero-readout').textContent).toMatch(/left half/i);
  });

  it('updates as the selection changes', () => {
    press('ArrowRight');
    expect($('hero-readout').textContent).not.toMatch(/left half/i);
  });

  it('names a fraction, since that is what the annotation is for', () => {
    // The resting selection is 2 of 4 columns by 3 of 3 rows.
    expect($('hero-readout').textContent).toMatch(/1\/2|½/);
  });
});

describe('attachHero — the window lands', () => {
  beforeEach(() => mount());

  /*
   * The whole point of the hero (spec §4.1): a recognisable window has to
   * VISIBLY LAND. A translucent preview sliding around is a diagram. The
   * preview follows the selection; the window moves only on commit, which is
   * what the app does on release or Return.
   */
  it('leaves the window alone while the selection moves', () => {
    const before = $('hero-placed').style.cssText;
    press('ArrowRight');
    press('ArrowDown', true);
    expect($('hero-window').style.left).not.toBe('');
    expect($('hero-placed').style.cssText).toBe(before);
  });

  it('moves the window onto the selection when Return commits', () => {
    press('ArrowRight');
    press('Enter');
    expect($('hero-placed').style.left).toBe($('hero-window').style.left);
    expect($('hero-placed').style.width).toBe($('hero-window').style.width);
  });

  it('moves the window on pointer release too', () => {
    at(3, 2);
    pointer('pointerdown', $('hero-cell-2-0'));
    pointer('pointermove', grid());
    pointer('pointerup', grid());
    expect($('hero-placed').style.left).toBe($('hero-window').style.left);
  });

  it('marks the landed window so Return does something visible', () => {
    expect($('hero-placed').hasAttribute('data-placed')).toBe(false);
    press('Enter');
    expect($('hero-placed').hasAttribute('data-placed')).toBe(true);
  });
});
