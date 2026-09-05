import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { contrastRatio } from './contrast';

describe('contrastRatio', () => {
  it('computes the known white-on-black extreme', () => {
    expect(contrastRatio('#FFFFFF', '#000000')).toBeCloseTo(21, 1);
  });

  it('computes an identity as 1', () => {
    expect(contrastRatio('#4A4A4A', '#4A4A4A')).toBeCloseTo(1, 5);
  });
});

/**
 * Parse the custom properties actually declared in tokens.css.
 *
 * Reading the stylesheet is the whole point: a test that asserts a hard-coded
 * hex pair proves the contrast FORMULA works, which nobody doubted, and goes on
 * passing after someone edits the palette to something unreadable. That is the
 * failure mode this file already had — it tested --label and --label-secondary
 * as literals and never noticed that #007AFF as link text measures 4.02:1 on
 * white, below WCAG AA, on every page of the site.
 */
function tokens(scope: 'light' | 'dark'): Record<string, string> {
  const css = readFileSync('src/styles/tokens.css', 'utf8');
  // Light lives in :root; dark lives in the prefers-color-scheme block, which
  // re-declares a subset. Dark therefore starts from light and overrides.
  const root = /:root\s*\{([\s\S]*?)\n\}/.exec(css);
  expect(root, ':root block not found in tokens.css').not.toBeNull();
  const dark = /prefers-color-scheme:\s*dark[\s\S]*?:root\s*\{([\s\S]*?)\n  \}/.exec(css);
  expect(dark, 'dark :root block not found in tokens.css').not.toBeNull();

  const read = (body: string, into: Record<string, string>) => {
    // Strip comments first: a prose comment that happens to write "--foo:" (a
    // very natural thing to do when documenting a custom property) otherwise
    // matches as a declaration and clobbers the real one with trailing junk.
    const withoutComments = body.replace(/\/\*[\s\S]*?\*\//g, '');
    for (const m of withoutComments.matchAll(/(--[\w-]+):\s*([^;]+);/g)) into[m[1]] = m[2].trim();
    return into;
  };
  const light = read(root![1], {});
  return scope === 'light' ? light : read(dark![1], { ...light });
}

/** `rgb(16 22 34 / 0.62)` and `#RRGGBB` both become `#RRGGBBAA` for contrastRatio. */
function toHex8(value: string): string {
  const rgb = /rgb\(\s*(\d+)\s+(\d+)\s+(\d+)\s*\/\s*([\d.]+)\s*\)/.exec(value);
  if (rgb) {
    const [, r, g, b, a] = rgb;
    const h = (n: number) => n.toString(16).padStart(2, '0');
    return `#${h(+r)}${h(+g)}${h(+b)}${h(Math.round(parseFloat(a) * 255))}`;
  }
  const hex = /^#[0-9a-fA-F]{6}$/.exec(value.trim());
  expect(hex, `unparseable colour in tokens.css: ${value}`).not.toBeNull();
  return value.trim();
}

describe('the palette declared in tokens.css', () => {
  // Every token that renders TEXT, against the surface it renders on.
  // --accent is absent on purpose: it fills glyphs, and --accent-text is the
  // one that has to clear AA. Splitting them is what fixes the live defect.
  it.each([
    ['light', 'body', '--label'],
    ['light', 'secondary', '--label-secondary'],
    ['light', 'link text', '--accent-text'],
    ['dark', 'body', '--label'],
    ['dark', 'secondary', '--label-secondary'],
    ['dark', 'link text', '--accent-text'],
  ] as const)('%s %s clears 4.5:1 on its own surface', (scope, _role, name) => {
    const t = tokens(scope);
    expect(t[name], `${name} missing from tokens.css`).toBeDefined();
    expect(contrastRatio(toHex8(t[name]), toHex8(t['--surface']))).toBeGreaterThanOrEqual(4.5);
  });

  it('uses --accent-text, not --accent, for links', () => {
    const css = readFileSync('src/styles/tokens.css', 'utf8');
    const rule = /(^|\n)a\s*\{([^}]*)\}/.exec(css);
    expect(rule, 'no bare `a { }` rule in tokens.css').not.toBeNull();
    expect(rule![2]).toContain('var(--accent-text)');
  });

  /*
   * The pairing the block above excludes on purpose, and was wrong to.
   *
   * "--accent is absent: it fills glyphs" was true of glyphs and false of
   * .btn-primary, which paints #fff ON that fill. Measured before this test
   * existed: 4.02:1 light and 3.65:1 dark, at 15px/550 — normal text, so the
   * bar is 4.5:1. The download button, the site's single most important
   * control, failed AA in both schemes on every page.
   *
   * Asserted against #fff rather than the surface, because a filled button is
   * the one place the accent is a BACKGROUND. The scheme loop matters: dark
   * mode was the worse of the two, and a light-only check would have passed a
   * button that is still failing for half the visitors.
   */
  /*
   * BOTH states, because hover is not a decoration — it is the state the
   * visitor is in while deciding to click. The first version of this fix
   * covered only the resting fill and left `filter: brightness(1.08)` in
   * place, which measured 4.30:1: the resting state cleared the bar and the
   * hovered one did not.
   */
  const FILLS = [
    ['light', '--accent-fill'], ['dark', '--accent-fill'],
    ['light', '--accent-fill-hover'], ['dark', '--accent-fill-hover'],
  ] as const;

  it.each(FILLS)('clears 4.5:1 for white text on the %s %s', (scope, name) => {
    const t = tokens(scope);
    expect(t[name], `${name} missing from tokens.css`).toBeDefined();
    expect(contrastRatio('#FFFFFF', toHex8(t[name]))).toBeGreaterThanOrEqual(4.5);
  });

  // Non-text UI still has a floor: a button nobody can find is not an
  // improvement on one whose label is hard to read. SC 1.4.11 is 3:1.
  it.each(FILLS)('keeps the %s %s distinguishable from its surface', (scope, name) => {
    const t = tokens(scope);
    expect(contrastRatio(toHex8(t[name]), toHex8(t['--surface']))).toBeGreaterThanOrEqual(3);
  });

  // A fill that clears 4.5:1 buys nothing if the button stops using it. Pins
  // both halves: the declaration, and that it is not the bare --accent whose
  // 4.02:1 this test exists to keep out.
  it('paints the primary button with --accent-fill', () => {
    const css = readFileSync('src/styles/tokens.css', 'utf8');
    const rule = /\.btn-primary\s*\{([^}]*)\}/.exec(css);
    expect(rule, 'no `.btn-primary { }` rule in tokens.css').not.toBeNull();
    expect(rule![1]).toContain('var(--accent-fill)');
    expect(rule![1]).not.toMatch(/background:\s*var\(--accent\)/);
  });

  /*
   * The hover state has to be a COLOUR, not a filter.
   *
   * Everything above reads declared colours out of tokens.css, so a
   * `filter: brightness()` hover is a state this file cannot evaluate at all:
   * the four assertions would keep passing while the hovered button failed.
   * Forbidding the mechanism is what makes the assertions above complete.
   */
  it('gives the primary button a hover colour rather than a filter', () => {
    const css = readFileSync('src/styles/tokens.css', 'utf8');
    const rule = /\.btn-primary:hover\s*\{([^}]*)\}/.exec(css);
    expect(rule, 'no `.btn-primary:hover { }` rule in tokens.css').not.toBeNull();
    expect(rule![1]).toContain('var(--accent-fill-hover)');
    expect(rule![1], 'a filtered hover is a state the assertions above cannot see')
      .not.toContain('filter');
  });
});
