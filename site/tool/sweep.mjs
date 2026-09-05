/**
 * The responsive sweep, committed so it runs again.
 *
 * Checks every page at every width for two failures that no unit test sees:
 * a page-level horizontal scrollbar, and a standalone link or button below
 * WCAG 2.2's 24px target minimum.
 *
 * ⚠️ The overflow oracle is `documentElement.scrollWidth` against
 * `documentElement.clientWidth`, NOT `window.innerWidth`. innerWidth includes
 * the vertical scrollbar, so comparing against it reports overflow on every
 * page that scrolls vertically — which is every page. That false reading cost
 * real time once already.
 */
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { chromium } from 'playwright';

const DIST = new URL('../dist/', import.meta.url).pathname;
const WIDTHS = [320, 360, 390, 414, 480, 600, 700, 768, 834, 900, 980, 1024, 1280, 1440, 1920, 2560];
const PATHS = [
  '/', '/docs/', '/docs/getting-started/', '/docs/shortcuts/', '/docs/grid-overlay/',
  '/docs/custom-regions/', '/docs/multiple-displays/', '/docs/troubleshooting/',
  '/docs/settings/', '/docs/updates/', '/docs/uninstall/',
  '/compare/', '/faq/', '/changelog/', '/privacy/', '/404.html',
];
const TYPES = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.webm': 'video/webm', '.mp4': 'video/mp4',
  '.xml': 'application/xml', '.txt': 'text/plain' };

const server = createServer(async (req, res) => {
  let p = join(DIST, decodeURIComponent(req.url.split('?')[0]));
  try {
    if ((await stat(p)).isDirectory()) p = join(p, 'index.html');
  } catch { res.writeHead(404).end(); return; }
  try {
    const body = await readFile(p);
    res.writeHead(200, { 'content-type': TYPES[extname(p)] ?? 'application/octet-stream' }).end(body);
  } catch { res.writeHead(404).end(); }
});
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch();
const page = await browser.newPage();
const failures = [];

for (const path of PATHS) {
  await page.goto(base + path, { waitUntil: 'load' });
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: 900 });
    const found = await page.evaluate(() => {
      const de = document.documentElement;

      /*
       * WCAG 2.2 target size is 24 x 24 CSS px — BOTH dimensions. An earlier
       * draft checked height only, which passes a 12px-wide button forever.
       *
       * Exemption is explicit, not inferred. A previous heuristic asked whether
       * a link was its parent's entire text content, which quietly exempted
       * every BUTTON with a sibling — including the Copy button next to the
       * install command, i.e. the control most likely to be too small. The rule
       * now: every visible button is a target, no exceptions; a link is exempt
       * only when it sits inside a sentence, which is what WCAG's "inline"
       * exemption actually covers.
       */
      const EXEMPT_CLASSES = ['skip'];

      /*
       * Inline means: the link's own parent is a paragraph, and that paragraph
       * has real prose outside its links.
       *
       * The comparison this replaces asked whether the parent's text was longer
       * than the link's, which exempts a docs-index <li> merely because it also
       * holds a description span — i.e. it exempted exactly the standalone
       * links this check exists to find. "Has a sibling" is not "is in a
       * sentence".
       */
      const inSentence = (e) => {
        const p = e.parentElement;
        if (!p || p.tagName !== 'P') return false;
        const linkText = [...p.querySelectorAll('a')]
          .map((a) => (a.textContent || '').trim()).join('');
        const prose = (p.textContent || '').replace(/\s+/g, ' ').trim();
        // Whatever is left once every link's text is removed.
        return prose.length - linkText.length > 2;
      };

      const targets = [...document.querySelectorAll('a, button')].filter((e) => {
        if (!e.checkVisibility()) return false;
        if (EXEMPT_CLASSES.some((c) => e.classList.contains(c))) return false;
        if (e.tagName === 'BUTTON') return true;
        return !inSentence(e);
      });

      const small = targets
        .filter((e) => {
          const b = e.getBoundingClientRect();
          return b.height < 24 || b.width < 24;
        })
        .map((e) => {
          const b = e.getBoundingClientRect();
          const what = (e.textContent || '').trim().slice(0, 24) || e.tagName.toLowerCase();
          return `${what} (${Math.round(b.width)}x${Math.round(b.height)}px)`;
        });

      return {
        overflow: de.scrollWidth > de.clientWidth + 1,
        by: de.scrollWidth - de.clientWidth,
        small: [...new Set(small)],
      };
    });
    if (found.overflow) failures.push(`${path} @${width}px scrolls horizontally by ${found.by}px`);
    for (const s of found.small) failures.push(`${path} @${width}px target too small: ${s}`);
  }
}

await browser.close();
server.close();

const checked = PATHS.length * WIDTHS.length;
if (failures.length) {
  console.error(`sweep: ${failures.length} failure(s) across ${checked} page/width combinations\n`);
  for (const f of failures) console.error('  ' + f);
  process.exit(1);
}
console.log(`sweep: clean across ${checked} page/width combinations`);
