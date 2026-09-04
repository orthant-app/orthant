// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from 'vitest';
import { attachScrollHint } from './compare';

/**
 * happy-dom does no real layout, so `scrollWidth`/`clientWidth`/`scrollLeft`
 * are all 0 by default on every element — they have to be stood in for
 * explicitly, the same technique hero.test.ts uses for
 * `document.elementFromPoint`. `defineProperty` rather than plain assignment
 * because these are read-only getters on the real `Element` prototype.
 */
function mount(): HTMLElement {
  document.body.innerHTML = `
    <div id="wrap" class="table-scroll-wrap">
      <div class="scroll-x" tabindex="0" role="region" aria-label="Comparison table">
        <table><tr><td>cell</td></tr></table>
      </div>
    </div>`;
  return document.getElementById('wrap') as HTMLElement;
}

function stub(el: HTMLElement, props: { scrollWidth: number; clientWidth: number; scrollLeft: number }) {
  Object.defineProperty(el, 'scrollWidth', { value: props.scrollWidth, configurable: true });
  Object.defineProperty(el, 'clientWidth', { value: props.clientWidth, configurable: true });
  // scrollLeft is writable on the real Element, but happy-dom's layout-free
  // implementation ignores the write — define it as a plain, mutable data
  // property so a later `stub()`/direct assignment in a test can move it.
  Object.defineProperty(el, 'scrollLeft', { value: props.scrollLeft, configurable: true, writable: true });
}

const wrapAttr = (wrap: HTMLElement) => wrap.hasAttribute('data-can-scroll');

afterEach(() => {
  document.body.innerHTML = '';
});

describe('attachScrollHint — the comparison table\'s scroll affordance', () => {
  it('does not throw when the wrap has no .scroll-x', () => {
    document.body.innerHTML = '<div id="wrap"></div>';
    const wrap = document.getElementById('wrap') as HTMLElement;
    expect(() => attachScrollHint(wrap)).not.toThrow();
  });

  it('shows the affordance when the table overflows and is not scrolled to the end', () => {
    const wrap = mount();
    const scroller = wrap.querySelector('.scroll-x') as HTMLElement;
    stub(scroller, { scrollWidth: 600, clientWidth: 320, scrollLeft: 0 });

    attachScrollHint(wrap);

    expect(wrapAttr(wrap)).toBe(true);
  });

  it('never shows the affordance when the table does not overflow at all', () => {
    // The desktop case: table { min-width: 480px } fits comfortably, so
    // there is nothing to swipe to and nothing to fade toward.
    const wrap = mount();
    const scroller = wrap.querySelector('.scroll-x') as HTMLElement;
    stub(scroller, { scrollWidth: 900, clientWidth: 900, scrollLeft: 0 });

    attachScrollHint(wrap);

    expect(wrapAttr(wrap)).toBe(false);
  });

  it('does not show the affordance when already scrolled to the end', () => {
    const wrap = mount();
    const scroller = wrap.querySelector('.scroll-x') as HTMLElement;
    stub(scroller, { scrollWidth: 600, clientWidth: 320, scrollLeft: 280 });

    attachScrollHint(wrap);

    expect(wrapAttr(wrap)).toBe(false);
  });

  it('hides the affordance once a scroll event reaches the end', () => {
    const wrap = mount();
    const scroller = wrap.querySelector('.scroll-x') as HTMLElement;
    stub(scroller, { scrollWidth: 600, clientWidth: 320, scrollLeft: 0 });
    attachScrollHint(wrap);
    expect(wrapAttr(wrap)).toBe(true);

    scroller.scrollLeft = 280; // 320 + 280 === 600, exactly at the end
    scroller.dispatchEvent(new Event('scroll'));

    expect(wrapAttr(wrap)).toBe(false);
  });

  it('brings the affordance back if the user scrolls back away from the end', () => {
    const wrap = mount();
    const scroller = wrap.querySelector('.scroll-x') as HTMLElement;
    stub(scroller, { scrollWidth: 600, clientWidth: 320, scrollLeft: 280 });
    attachScrollHint(wrap);
    expect(wrapAttr(wrap)).toBe(false);

    scroller.scrollLeft = 100;
    scroller.dispatchEvent(new Event('scroll'));

    expect(wrapAttr(wrap)).toBe(true);
  });

  it('re-checks on window resize, e.g. a table that stops overflowing at a wider viewport', () => {
    const wrap = mount();
    const scroller = wrap.querySelector('.scroll-x') as HTMLElement;
    stub(scroller, { scrollWidth: 600, clientWidth: 320, scrollLeft: 0 });
    attachScrollHint(wrap);
    expect(wrapAttr(wrap)).toBe(true);

    // Simulate the viewport growing past the table's min-width: clientWidth
    // catches up to scrollWidth.
    Object.defineProperty(scroller, 'clientWidth', { value: 600, configurable: true });
    window.dispatchEvent(new Event('resize'));

    expect(wrapAttr(wrap)).toBe(false);
  });
});
