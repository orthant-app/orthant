/**
 * The comparison table's scroll affordance (design gate finding: "the mobile
 * table scrolls horizontally without an obvious cue that more columns
 * exist").
 *
 * `compare.astro` already authors the keyboard path with no JavaScript at
 * all needed: `tabindex="0"` on a `overflow-x: auto` element is enough on
 * its own for native arrow-key/Page-Down scrolling once focused. What plain
 * CSS cannot do is know whether there is anything LEFT to scroll to — a
 * right-edge fade drawn with CSS alone stays visible even once the last
 * column is already on screen, which is exactly the "invisible to anyone
 * who has scrolled to the end" half of the gate's own complaint, just
 * inverted (permanently visible instead of never visible).
 *
 * This sets `data-can-scroll` to the literal string `"true"` or `"false"` —
 * never merely present/absent — specifically so the stylesheet's own
 * no-JavaScript baseline (visible below the table's own overflow width,
 * hidden at and above it; see compare.astro) can tell "JavaScript has run
 * and decided false" apart from "JavaScript has not run at all" (attribute
 * absent, in which case the CSS-only baseline is what a real no-JS visitor
 * sees). A followup review found the presence-only version of this reduced
 * to `visibility: hidden` unconditionally with no CSS fallback, so a
 * visitor without JavaScript never saw the cue at all even though the table
 * genuinely overflowed and genuinely scrolled — the exact defect the design
 * gate raised, reproduced for anyone without a script engine.
 */
export function attachScrollHint(wrap: HTMLElement): void {
  const scroller = wrap.querySelector<HTMLElement>('.scroll-x');
  if (!scroller) return;

  // Sub-pixel rounding at fractional zoom/device-pixel ratios can leave
  // scrollLeft + clientWidth a hair short of scrollWidth even at the true
  // end, which would otherwise strand the affordance on permanently.
  const EPSILON = 1;

  function update() {
    const el = scroller!;
    const overflowing = el.scrollWidth > el.clientWidth;
    const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - EPSILON;
    wrap.setAttribute('data-can-scroll', String(overflowing && !atEnd));
  }

  update();
  scroller.addEventListener('scroll', update, { passive: true });
  // A rotation or a desktop window resize can cross the table's own
  // min-width threshold and change whether it overflows at all.
  window.addEventListener('resize', update);
}
