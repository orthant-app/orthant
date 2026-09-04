// @vitest-environment happy-dom
import { existsSync, readFileSync } from 'node:fs';
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

// The attribute is a literal "true"/"false" string, never mere presence —
// see compare.ts's own doc comment for why (the CSS-only no-JS baseline
// needs to tell "JavaScript decided false" apart from "JavaScript never
// ran"). This helper reads the boolean the CSS-visible-toggle rules key
// off; a separate assertion below checks the attribute is always SET once
// attachScrollHint has run at all, which the old presence-based version
// could not have distinguished from "false".
const wrapAttr = (wrap: HTMLElement) => wrap.getAttribute('data-can-scroll') === 'true';

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

  it('writes an explicit "false", not mere absence, once it has run and decided false', () => {
    // The property the CSS no-JS baseline depends on: compare.astro's
    // stylesheet must be able to tell "JavaScript ran and said false" apart
    // from "JavaScript never ran at all" (attribute absent), because those
    // two cases resolve to opposite CSS defaults below the overflow
    // threshold. `toggleAttribute` — the previous implementation — cannot
    // make this distinction; it leaves the attribute equally absent either
    // way.
    const wrap = mount();
    const scroller = wrap.querySelector('.scroll-x') as HTMLElement;
    stub(scroller, { scrollWidth: 900, clientWidth: 900, scrollLeft: 0 });

    attachScrollHint(wrap);

    expect(wrap.hasAttribute('data-can-scroll')).toBe(true);
    expect(wrap.getAttribute('data-can-scroll')).toBe('false');
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

/**
 * Guards the no-JavaScript baseline itself, against the actual BUILT output
 * — not the .astro source, and not attachScrollHint, which never runs at
 * all for the visitor this section is about. `dist/` must already exist
 * (`npm run build` first; this suite does not build for itself, matching
 * dist-csp.test.ts's own reasoning: a full build on every `vitest watch`
 * save would be a bad trade).
 *
 * A prior version of the affordance had `.scroll-fade`/`.swipe-hint`
 * default to `visibility: hidden` unconditionally, revealed only by
 * compare.ts setting `data-can-scroll`. That is invisible to plain
 * assertions against attachScrollHint, because attachScrollHint IS the
 * thing that would be missing — the only way to catch a regression back to
 * that shape is to read the CSS a real no-JS browser would apply, which is
 * what ships in dist/_astro/compare.*.css, referenced from
 * dist/compare/index.html.
 */
describe('the comparison table\'s scroll cue has a safe CSS-only baseline', () => {
  const DIST = 'dist';
  const PAGE = `${DIST}/compare/index.html`;

  it('has a build to check', () => {
    expect(existsSync(PAGE), `${PAGE} is missing — run \`npm run build\` first`).toBe(true);
  });

  if (existsSync(PAGE)) {
    // Concatenate every stylesheet compare/index.html actually links —
    // matching how a real browser assembles the cascade for this page,
    // rather than guessing which hashed file holds the relevant rule.
    const html = readFileSync(PAGE, 'utf8');
    const hrefs = [...html.matchAll(/<link rel="stylesheet" href="([^"]+)"/g)].map((m) => m[1]);
    const css = hrefs
      .map((href) => readFileSync(`${DIST}${href}`, 'utf8'))
      .join('\n');

    it('found the page\'s own stylesheets to check', () => {
      expect(hrefs.length, 'no <link rel="stylesheet"> found on the compare page').toBeGreaterThan(0);
      expect(css, 'none of the linked stylesheets mention .scroll-fade').toMatch(/\.scroll-fade/);
    });

    it('defaults the fade and hint to visible OUTSIDE any media query', () => {
      // Anchored to start with `.scroll-fade[` specifically: the
      // JS-attribute-driven rules further down always mention
      // `.table-scroll-wrap` and `[data-can-scroll=…]` BEFORE `.scroll-fade`
      // ever appears, so this cannot accidentally match one of those.
      const beforeMedia = css.slice(0, css.indexOf('@media'));
      const base = /\.scroll-fade\[[^\]]*\],\.swipe-hint\[[^\]]*\]\{([^}]*)\}/.exec(beforeMedia);
      expect(base, 'no unconditional .scroll-fade/.swipe-hint rule found before the first @media').not.toBeNull();
      expect(base![1]).toBe('visibility:visible');
    });

    it('hides the fade and hint inside a media query gated on the measured 528px breakpoint', () => {
      const media = /@media[^{]*528[^{]*\{([^}]+)\}/.exec(css);
      expect(media, 'no @media block mentioning 528 found').not.toBeNull();
      expect(media![1]).toContain('.scroll-fade');
      expect(media![1]).toContain('.swipe-hint');
      expect(media![1]).toContain('visibility:hidden');
    });

    it('still lets compare.ts\'s own measurement override the CSS baseline at any width', () => {
      // The two rules keyed on the explicit "true"/"false" string compare.ts
      // writes — kept working alongside the new baseline, not replaced by it.
      const trueRule = /\[data-can-scroll=true\][^{]*\{([^}]*)\}/.exec(css);
      const falseRule = /\[data-can-scroll=false\][^{]*\{([^}]*)\}/.exec(css);
      expect(trueRule, 'no [data-can-scroll=true] rule found').not.toBeNull();
      expect(falseRule, 'no [data-can-scroll=false] rule found').not.toBeNull();
      expect(trueRule![1]).toBe('visibility:visible');
      expect(falseRule![1]).toBe('visibility:hidden');
    });
  }
});
