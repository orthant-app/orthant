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
      <div id="hero-grid" data-cols="4" data-rows="3">
        ${[0, 1, 2].map(row).join('')}
        <div id="hero-window"></div>
      </div>
      <button id="hero-activate" type="button" hidden>Try the grid</button>
      <p id="hero-instructions" hidden></p>
      <p id="hero-status" role="status" aria-live="polite"></p>
    </section>`;
  const root = document.getElementById('root') as HTMLElement;
  attachHero(root);
  return root;
}

const $ = (id: string) => document.getElementById(id) as HTMLElement;
const grid = () => $('hero-grid');
const activate = () => ($('hero-activate') as HTMLButtonElement).click();

// NOTE: dispatched on the GRID, never on `document`. The listener is attached
// to the grid, so a document-level dispatch never reaches it and the assertion
// passes no matter what the handler does — a vacuous test that would score a
// removed activation guard as "caught".
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

describe('attachHero — dormant', () => {
  beforeEach(() => mount());

  it('reveals the activate button, since the controller is now present', () => {
    expect($('hero-activate').hasAttribute('hidden')).toBe(false);
  });

  it('leaves the grid out of the tab order and unlabelled', () => {
    expect(grid().getAttribute('role')).toBeNull();
    expect(grid().getAttribute('tabindex')).toBeNull();
    expect(grid().getAttribute('aria-label')).toBeNull();
  });

  it('leaves rows and cells without grid semantics', () => {
    expect(document.querySelectorAll('[role="row"]')).toHaveLength(0);
    expect(document.querySelectorAll('[role="gridcell"]')).toHaveLength(0);
  });

  it('does not consume arrow keys', () => {
    expect(press('ArrowRight').defaultPrevented).toBe(false);
  });
});

describe('attachHero — activation', () => {
  beforeEach(() => mount());

  it('focuses the grid and shows instructions', () => {
    activate();
    expect(document.activeElement).toBe(grid());
    expect($('hero-instructions').hasAttribute('hidden')).toBe(false);
  });

  it('never uses role="application"', () => {
    activate();
    expect(grid().getAttribute('role')).toBe('grid');
    expect(document.querySelector('[role="application"]')).toBeNull();
  });

  it('applies the full WAI grid structure', () => {
    activate();
    expect(document.querySelectorAll('[role="row"]')).toHaveLength(3);
    expect(document.querySelectorAll('[role="gridcell"]')).toHaveLength(12);
  });

  it('tracks the active cell with aria-activedescendant', () => {
    activate();
    const id = grid().getAttribute('aria-activedescendant');
    expect(id).toBeTruthy();
    expect(document.getElementById(id!)).not.toBeNull();
  });

  it('marks selected cells with aria-selected', () => {
    activate();
    const selected = document.querySelectorAll('[aria-selected="true"]');
    expect(selected).toHaveLength(6); // the left half: 2 columns x 3 rows
  });

  // A pointer press is as deliberate as pressing the button, so it performs the
  // same transition rather than being ignored. Without this the grid could be
  // driven by mouse while still claiming to be dormant.
  it('a pointer press on a cell activates, rather than silently mutating', () => {
    pointer('pointerdown', $('hero-cell-2-1'));
    expect(grid().getAttribute('role')).toBe('grid');
    expect($('hero-instructions').hasAttribute('hidden')).toBe(false);
  });
});

describe('attachHero — interaction', () => {
  beforeEach(() => { mount(); activate(); });

  it('consumes arrow keys once active', () => {
    expect(press('ArrowRight').defaultPrevented).toBe(true);
  });

  it('moves the selection with an arrow', () => {
    const before = $('hero-window').style.left;
    press('ArrowRight');
    expect($('hero-window').style.left).not.toBe(before);
  });

  it('extends the selection with shift-arrow', () => {
    const before = parseFloat($('hero-window').style.width);
    press('ArrowRight', true);
    expect(parseFloat($('hero-window').style.width)).toBeGreaterThan(before);
  });

  it('updates aria-selected as the selection changes', () => {
    press('ArrowRight', true);
    expect(document.querySelectorAll('[aria-selected="true"]')).toHaveLength(9);
  });

  it('announces a placement to screen readers', () => {
    press('Enter');
    expect($('hero-status').textContent).toMatch(/placed/i);
  });

  it('a pointer drag selects the cells it crosses', () => {
    // pointermove reads document.elementFromPoint, which happy-dom does not
    // implement — a drag test that only sends pointerdown proves nothing about
    // dragging.
    at(1, 1);
    pointer('pointerdown', $('hero-cell-0-0'));
    expect(document.querySelectorAll('[aria-selected="true"]')).toHaveLength(1);
    pointer('pointermove', grid());
    expect(document.querySelectorAll('[aria-selected="true"]')).toHaveLength(4); // 0..1 x 0..1
    pointer('pointerup', grid());
    expect($('hero-status').textContent).toMatch(/placed/i);
  });
});

describe('attachHero — a cancelled gesture', () => {
  beforeEach(() => mount());

  // touch-action: pan-y lets the browser reclaim a vertical swipe mid-gesture.
  // pointerdown has already run by then, so without a pointercancel handler the
  // page scrolls AND the window moves — which is exactly the promise broken.
  it('returns a swiped-past dormant grid to dormant', () => {
    pointer('pointerdown', $('hero-cell-2-1'));
    expect(grid().getAttribute('role')).toBe('grid');
    pointer('pointercancel', grid());
    expect(grid().getAttribute('role')).toBeNull();
    expect($('hero-instructions').hasAttribute('hidden')).toBe(true);
    expect(press('ArrowRight').defaultPrevented).toBe(false);
    // The painted geometry must go back as well. Found by driving a real touch
    // swipe through CDP: the state restored correctly while the window stayed
    // where the finger landed, and every other assertion here still passed.
    expect($('hero-window').style.left).toBe('');
    expect($('hero-window').style.width).toBe('');
  });

  it('restores the selection the press had changed', () => {
    activate();
    const before = $('hero-window').style.width;
    pointer('pointerdown', $('hero-cell-3-2'));
    expect($('hero-window').style.width).not.toBe(before);
    pointer('pointercancel', grid());
    expect($('hero-window').style.width).toBe(before);
  });

  it('leaves an already-active grid active', () => {
    activate();
    pointer('pointerdown', $('hero-cell-3-2'));
    pointer('pointercancel', grid());
    expect(grid().getAttribute('role')).toBe('grid');
  });
});

describe('attachHero — exit', () => {
  beforeEach(() => { mount(); activate(); });

  it('Esc returns focus to the button and stops consuming arrows', () => {
    press('Escape');
    expect(document.activeElement).toBe($('hero-activate'));
    expect(press('ArrowRight').defaultPrevented).toBe(false);
  });

  it('Esc strips the grid semantics again', () => {
    press('Escape');
    expect(grid().getAttribute('role')).toBeNull();
    expect(document.querySelectorAll('[role="gridcell"]')).toHaveLength(0);
    expect(grid().getAttribute('aria-activedescendant')).toBeNull();
  });

  it('blur exits too, so focus never leaves an armed grid behind', () => {
    grid().dispatchEvent(new FocusEvent('blur', { bubbles: true }));
    expect(press('ArrowRight').defaultPrevented).toBe(false);
  });

  it('Esc mid-drag stops a later pointerup announcing a placement', () => {
    pointer('pointerdown', $('hero-cell-1-1'));
    press('Escape');
    $('hero-status').textContent = '';
    pointer('pointerup', grid());
    expect($('hero-status').textContent).toBe('');
  });
});
