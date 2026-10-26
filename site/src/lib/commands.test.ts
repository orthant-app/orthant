import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { BINDINGS, windowsCombo } from './commands';

describe('BINDINGS', () => {
  // Eleven, not ten: kDefaultBindings opens with showGrid (⌃⌥O), then the ten
  // placements. A map that renders ten is missing the one shortcut a new user
  // needs first.
  it('has the eleven defaults the app ships', () => {
    expect(BINDINGS).toHaveLength(11);
  });

  /*
   * Three kinds, because the app has three shapes and flattening them lies:
   *
   *  - 'block'     nine placements, gridBlock(cols: 2, rows: 2) with fixed
   *                indices (region_commands.dart:17-25)
   *  - 'keepsSize' center, which preserves the captured window's CURRENT size
   *                and centres it (region_commands.dart:28-36) — no fixed shape
   *  - 'summon'    showGrid, which opens the overlay and places nothing at all
   *
   * An earlier draft modelled center and the summon both as `block: null`,
   * which collides two different facts into one absence: center HAS a target
   * rect and no fixed fraction; the summon has no target rect whatsoever.
   */
  it('separates the summon from the command that merely keeps its size', () => {
    expect(BINDINGS.filter((b) => b.kind === 'summon').map((b) => b.id)).toEqual(['showGrid']);
    expect(BINDINGS.filter((b) => b.kind === 'keepsSize').map((b) => b.id)).toEqual(['center']);
    expect(BINDINGS.filter((b) => b.kind === 'block')).toHaveLength(9);
  });

  it('matches the app for the four indices that are easy to transpose', () => {
    const block = (id: string) => {
      const b = BINDINGS.find((x) => x.id === id);
      return b && b.kind === 'block' ? b.block : null;
    };
    expect(block('leftHalf')).toEqual({ c0: 0, c1: 0, r0: 0, r1: 1 });
    expect(block('topHalf')).toEqual({ c0: 0, c1: 1, r0: 0, r1: 0 });
    expect(block('topRight')).toEqual({ c0: 1, c1: 1, r0: 0, r1: 0 });
    expect(block('maximize')).toEqual({ c0: 0, c1: 1, r0: 0, r1: 1 });
  });

  it('gives every binding a label and a ⌃⌥ combo', () => {
    for (const b of BINDINGS) {
      expect(b.label.length, b.id).toBeGreaterThan(0);
      expect(b.combo.startsWith('⌃⌥'), b.id).toBe(true);
    }
  });
});

/*
 * Windows has the same eleven defaults on the same keys, so its combos are
 * derived from BINDINGS rather than typed out a second time. These pin the
 * function's shape; test/site_docs_test.dart pins the two constants it reads
 * against the app's own Windows defaults.
 */
describe('windowsCombo', () => {
  it('puts Win+Ctrl+Shift in place of ⌃⌥ and keeps the key', () => {
    expect(windowsCombo('⌃⌥←')).toBe('Win+Ctrl+Shift+←');
    expect(windowsCombo('⌃⌥O')).toBe('Win+Ctrl+Shift+O');
    expect(windowsCombo('⌃⌥C')).toBe('Win+Ctrl+Shift+C');
  });

  it('names the key Windows names otherwise: ↩ is Enter', () => {
    expect(windowsCombo('⌃⌥↩')).toBe('Win+Ctrl+Shift+Enter');
  });

  // A combo it does not know how to translate is an error, not a guess: a
  // ⌘ chord has no Windows counterpart this rule could produce.
  it('refuses a combo that does not start with ⌃⌥', () => {
    expect(() => windowsCombo('⌘S')).toThrow();
    expect(() => windowsCombo('⌃⌥')).toThrow();
  });

  it('gives the eleven defaults eleven different Windows combos', () => {
    expect(new Set(BINDINGS.map((b) => windowsCombo(b.combo))).size).toBe(BINDINGS.length);
  });
});

/*
 * The Windows table on the shortcuts page is rendered from BINDINGS through
 * windowsCombo, so this checks the page uses them: every action, once, with
 * its derived combo. Reads built output, so `npm run build` must have run.
 */
describe('the built Windows shortcuts table', () => {
  const PAGE = 'dist/docs/shortcuts/index.html';

  it('lists every default with its Windows combo, and nothing else', () => {
    if (!existsSync(PAGE)) throw new Error(`${PAGE} missing - run \`npm run build\` first`);
    const html = readFileSync(PAGE, 'utf8');

    // The table under the Windows heading, not the macOS one above it.
    const start = html.search(/<h2 id="windows"/);
    expect(start, 'no Windows heading on the shortcuts page').toBeGreaterThan(-1);
    const table = /<table[\s\S]*?<\/table>/.exec(html.slice(start));
    expect(table, 'no table under the Windows heading').not.toBeNull();

    const rows = [...table![0].matchAll(/<td>([^<]+)<\/td>\s*<td><code>([^<]+)<\/code><\/td>/g)]
      .map((m) => [m[1], m[2]]);
    expect(rows).toEqual(BINDINGS.map((b) => [b.label, windowsCombo(b.combo)]));
  });
});

/*
 * The discriminated union above is meant to make "ask a summon entry for a
 * block" a compile error. It is not, where it matters: `.astro` and `.mdx` are
 * outside the tsc program — `tsc --listFiles` reports **zero** of them — and
 * there is no `astro check`. A review proved the gap by widening the keymap's
 * filter to admit `keepsSize`: tsc passed, `npm run build` passed, and the page
 * shipped `x="NaN" y="NaN"`.
 *
 * So the type is the intent and this is the enforcement. Reads built output, so
 * `npm run build` must have run first — ⚠️ a source mutation is invisible here
 * without a rebuild in between.
 */
describe('the built keymap diagrams', () => {
  const PAGE = 'dist/docs/shortcuts/index.html';

  it('render one per block binding, with no unplaceable geometry', () => {
    if (!existsSync(PAGE)) throw new Error(`${PAGE} missing - run \`npm run build\` first`);
    const html = readFileSync(PAGE, 'utf8');

    // One diagram per block, and only blocks: center keeps the window's current
    // size and the summon places nothing, so neither has a rect to draw.
    const blocks = BINDINGS.filter((b) => b.kind === 'block');
    expect(html.match(/class="region"/g) ?? []).toHaveLength(blocks.length);

    // The actual symptom the union was supposed to prevent. A geometry
    // attribute is written straight from the block's indices, so a binding
    // without one arrives here as NaN rather than as an error.
    expect(html).not.toContain('NaN');
  });
});
