import { existsSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/*
 * The homepage's demo videos, as they ship. There is one per platform, and
 * the page shows the other platform's only when asked, so a missing file
 * would be seen by nobody who did not switch: every <source> and poster the
 * built page names must be a file in the build.
 *
 * Requires `dist/`: run `npm run build` first.
 */

const DIST = 'dist';

describe('the homepage demo media', () => {
  const html = existsSync(join(DIST, 'index.html')) ? readFileSync(join(DIST, 'index.html'), 'utf8') : '';
  const sources = [...html.matchAll(/<source\b[^>]*\bsrc="([^"]+)"/g)].map((m) => m[1]);
  const posters = [...html.matchAll(/<video\b[^>]*\bposter="([^"]+)"/g)].map((m) => m[1]);

  it('names a video for each platform, in both formats, each with a poster', () => {
    expect(html, `${DIST}/index.html is missing - run \`npm run build\` first`).not.toBe('');
    expect(sources.sort()).toEqual(['/demo-windows.mp4', '/demo-windows.webm', '/demo.mp4', '/demo.webm']);
    expect(posters.sort()).toEqual(['/demo-poster.webp', '/demo-windows-poster.webp']);
  });

  it('ships every file it names, none of them empty', () => {
    const missing = [...sources, ...posters].filter((p) => {
      const f = join(DIST, p);
      return !existsSync(f) || statSync(f).size === 0;
    });
    expect(missing).toEqual([]);
  });
});
