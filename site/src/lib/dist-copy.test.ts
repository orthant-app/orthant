import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/*
 * The site-wide copy rules, checked against what actually ships.
 *
 * ⚠️ These were enforced for this entire redesign by hand: every implementer
 * and reviewer was told to `grep` the built output, and every one of them did.
 * Nothing in the suite or CI checked any of it, so the rules would have stopped
 * being enforced the moment the plan ended. That is the same argument the
 * responsive sweep makes about itself: ad hoc means it never runs again.
 *
 * The hand-grep also had a blind spot that proves the point. It always globbed
 * *.html, *.css and *.js, so `.svg` was never looked at, and a shipped icon
 * carried an em dash through the whole plan without one reviewer seeing it.
 * This walks every text file under dist/ instead of naming extensions.
 *
 * Requires `dist/` — run `npm run build` first. A source-only change is
 * invisible here without a rebuild.
 */

const DIST = 'dist';

/** Binary assets: nothing to read, and reading them would be noise. */
const SKIP = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.ico', '.mp4', '.webm', '.woff', '.woff2', '.ttf']);

function textFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...textFiles(full));
    else if (![...SKIP].some((ext) => entry.name.endsWith(ext))) out.push(full);
  }
  return out;
}

describe('the built site', () => {
  const files = existsSync(DIST) ? textFiles(DIST) : [];

  it('has something to check', () => {
    // A walk that finds nothing passes every assertion below it, which is the
    // failing-toward-fine this file exists to remove.
    expect(existsSync(DIST), `${DIST}/ is missing - run \`npm run build\` first`).toBe(true);
    expect(files.length).toBeGreaterThan(20);
  });

  it('ships no em dash, in any file type', () => {
    const guilty = files.filter((f) => readFileSync(f, 'utf8').includes('—'));
    expect(guilty, `em dash (U+2014) in: ${guilty.join(', ')}`).toEqual([]);
  });

  /*
   * Apple notarizes; the developer signs, with an Apple-issued Developer ID.
   * "Signed by Apple" is not a wording preference — it is false, and it is a
   * claim about a third party.
   */
  it('never says Apple signed anything', () => {
    const guilty = files.filter((f) => /signed by Apple/i.test(readFileSync(f, 'utf8')));
    expect(guilty, `"signed by Apple" in: ${guilty.join(', ')}`).toEqual([]);
  });

  /*
   * Spec §3.4 fixes the wording of the latency figure because the number is a
   * real measurement and a reworded one loses the precision it was stating.
   * There are exactly two approved forms and no third.
   */
  it('states the latency figure only in its approved forms', () => {
    const approved = /about 50 (?:milliseconds|ms)/;
    const guilty: string[] = [];
    for (const f of files) {
      // ⚠️ Collapse whitespace first. HTML wraps wherever the source wrapped,
      // so the correct copy ships as "about 50\nmilliseconds" and a pattern
      // demanding a literal space reports it as a violation. That false
      // positive is how a gate gets switched off, which is the opposite of
      // what this file is for.
      const text = readFileSync(f, 'utf8').replace(/\s+/g, ' ');
      for (const m of text.matchAll(/[^.>]{0,24}\b50 ?(?:ms|milliseconds)\b/g)) {
        if (!approved.test(m[0])) guilty.push(`${f}: ${m[0].trim()}`);
      }
    }
    expect(guilty, `unapproved latency wording: ${guilty.join(' | ')}`).toEqual([]);
  });
});
