import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * Guards CRITICAL findings from the final whole-branch review: an inlined
 * hero <script> (no `src`) and Shiki's inline `style="…"` on every docs code
 * block both shipped silently because every other test looked at *source*,
 * never at built output. The site's own CSP (`style-src 'self'`,
 * `script-src 'self' …`, no nonce, no hash, no 'unsafe-inline') makes both
 * inert in a real browser — hero-default.test.ts already guards one file's
 * source against reintroducing a `style=` attribute; this guards the whole
 * built site's output against both classes of defect at once.
 *
 * Requires `dist/` to already exist — this file does NOT invoke `astro
 * build` itself, so `npm test` stays fast (this suite also runs under
 * `vitest watch` during development, where re-running a full site build on
 * every save would be a bad trade). The CI `site` job runs Build before Test
 * for exactly this reason; run `npm run build` locally first.
 */
const DIST = 'dist';

function htmlFiles(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...htmlFiles(full));
    else if (name.endsWith('.html')) out.push(full);
  }
  return out;
}

describe('the built site never ships what its own CSP would drop', () => {
  it('has a build to check', () => {
    expect(existsSync(DIST), `${DIST}/ is missing — run \`npm run build\` first`).toBe(true);
    expect(
      existsSync(DIST) ? htmlFiles(DIST).length : 0,
      `${DIST}/ contains no HTML — run \`npm run build\` first`,
    ).toBeGreaterThan(0);
  });

  // Registered only once a build exists: with no dist/, the assertion above
  // already fails with a clear message, and there is nothing here to scan.
  if (existsSync(DIST) && htmlFiles(DIST).length > 0) {
    const files = htmlFiles(DIST);

    it('has zero style attributes, which style-src \'self\' would drop', () => {
      const offenders = files.filter((f) => / style="/.test(readFileSync(f, 'utf8')));
      expect(offenders, `style= found in: ${offenders.join(', ')}`).toEqual([]);
    });

    it('has zero inline <script> bodies, except application/ld+json, which script-src \'self\' would drop', () => {
      const offenders: string[] = [];
      const scriptRe = /<script\b([^>]*)>([\s\S]*?)<\/script>/g;
      for (const file of files) {
        const html = readFileSync(file, 'utf8');
        let m: RegExpExecArray | null;
        while ((m = scriptRe.exec(html)) !== null) {
          const [, attrs, body] = m;
          if (/type="application\/ld\+json"/.test(attrs)) continue;
          if (body.trim() === '') continue; // an external <script src> has no body
          offenders.push(file);
        }
      }
      expect(offenders, `inline script body found in: ${offenders.join(', ')}`).toEqual([]);
    });
  }
});
