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
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { chromium } from 'playwright';

const DIST = new URL('../dist/', import.meta.url).pathname;
const WIDTHS = [320, 360, 390, 414, 480, 600, 700, 768, 834, 900, 980, 1024, 1280, 1440, 1920, 2560];

/**
 * Every page the build produced, derived rather than listed.
 *
 * ⚠️ This was a hardcoded array of sixteen routes, and a page added later was
 * silently not swept — a sweep that quietly narrows is worse than no sweep,
 * because its green means less each time the site grows and nobody is told.
 * Globbing what actually built is the only version whose coverage cannot rot.
 *
 * `/download` is deliberately absent and cannot appear here: it is a Worker
 * route that 302s and emits no HTML, so the build never writes a file for it.
 */
async function builtPages() {
  const files = await readdir(DIST, { recursive: true });
  const routes = files
    .filter((f) => f.endsWith('index.html'))
    .map((f) => '/' + f.slice(0, -'index.html'.length).replaceAll('\\', '/'));
  if (files.includes('404.html')) routes.push('/404.html');

  // A glob that matches nothing sweeps nothing and passes, which is the same
  // failing-toward-fine this function exists to remove. The floor is the count
  // the hardcoded list carried, so shrinking coverage has to be deliberate.
  if (routes.length < 16) {
    throw new Error(
      `only ${routes.length} pages found under dist/ - expected at least 16. ` +
        'Run `npm run build` first; if the site genuinely shrank, lower this floor on purpose.',
    );
  }
  return routes.sort();
}

const PATHS = await builtPages();
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

// Read actual line boxes and computed type: source CSS cannot prove whether a
// key fits, a diagram shrinks its chord, or a desktop fact note wraps.
async function checkHomepageTypography(page, label, platform, width) {
  const found = await page.evaluate(({ platform, width }) => {
    const errors = [];
    const visible = (e) => e.checkVisibility({ visibilityProperty: true });
    const lineCount = (e) => {
      const range = document.createRange();
      range.selectNodeContents(e);
      return new Set([...range.getClientRects()].map((r) => Math.round(r.top))).size;
    };
    const list = document.querySelector('.keymap');
    const instruction = document.getElementById(list.getAttribute('aria-describedby') ?? '');
    if (!instruction || !visible(instruction)) errors.push('missing shared modifier instruction');
    const keys = [...list.querySelectorAll('kbd')].filter(visible);
    const expected = ['O', '←', '→', '↑', '↓', 'U', 'I', 'J', 'K', platform === 'windows' ? 'Enter' : 'Return', 'C'];
    if (JSON.stringify(keys.map((e) => e.innerText.trim())) !== JSON.stringify(expected)) {
      errors.push('default tiles must show eleven terminal keys without repeated modifiers');
    }
    const ui = getComputedStyle(document.body).fontFamily;
    for (const key of [...document.querySelectorAll('.steps kbd, .keymap kbd')].filter(visible)) {
      const type = getComputedStyle(key);
      if (type.fontFamily !== ui || parseFloat(type.fontSize) < 15) {
        errors.push(`keycap ${key.innerText.trim()} must use readable UI type (${type.fontFamily}, ${type.fontSize})`);
      }
      const container = key.closest('li').getBoundingClientRect();
      const box = key.getBoundingClientRect();
      if (box.left < container.left - 1 || box.right > container.right + 1) {
        errors.push(`keycap ${key.innerText.trim()} exceeds its instruction or tile`);
      }
    }
    if ([...document.querySelectorAll('.steps svg .combo')].some(visible)) {
      errors.push('walkthrough chord scales inside a diagram instead of reading as HTML');
    }
    const steps = [...document.querySelectorAll('.steps > li')];
    const custom = platform === 'windows' ? 'Win+Ctrl+Shift+T' : '⌃⌥2';
    for (const step of steps.slice(1)) {
      if (![...step.querySelectorAll('p kbd')].some((e) => visible(e) && e.innerText.trim() === custom)) {
        errors.push('bind and reuse instructions must both show the full custom chord');
      }
    }
    const diagrams = steps.flatMap((e) => [...e.querySelectorAll('svg')].filter(visible));
    if (diagrams.length !== 3) errors.push('expected three visible fraction diagrams');
    if (width >= 760 && diagrams.length === 3) {
      const boxes = diagrams.map((e) => e.getBoundingClientRect());
      if (Math.max(...boxes.map((b) => b.top)) - Math.min(...boxes.map((b) => b.top)) > 1 ||
          Math.max(...boxes.map((b) => b.height)) - Math.min(...boxes.map((b) => b.height)) > 1) {
        errors.push('walkthrough fraction diagrams must align');
      }
    }
    const notes = [...document.querySelectorAll('.strip .note')];
    const noteLines = notes.map(lineCount);
    if (width >= 1440 && noteLines.some((lines) => lines !== 1)) {
      errors.push(`wide-desktop fact notes wrap (${noteLines.join(', ')} lines)`);
    }
    return { errors, noteLines };
  }, { platform, width });
  for (const error of found.errors) failures.push(`${label}: ${error}`);
  console.log(`${label}: fact note lines=${found.noteLines.join(',')}`);
}

for (const scheme of ['light', 'dark']) {
  await page.emulateMedia({ colorScheme: scheme });
  for (const width of [320, 390, 759, 768, 1440, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    for (const platform of ['macos', 'windows']) {
      await page.goto(`${base}/?platform=${platform}`, { waitUntil: 'load' });
      await checkHomepageTypography(page, `/ @${width}px ${platform} ${scheme}`, platform, width);
      // Exercise the switch as well as the initial platform query.
      const other = platform === 'macos' ? 'windows' : 'macos';
      await page.locator(`[data-platform-choice="${other}"]`).click();
      await checkHomepageTypography(page, `/ @${width}px switched ${other} ${scheme}`, other, width);
    }
  }
}
await page.emulateMedia({ colorScheme: 'light' });
const noScript = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
const fallback = await noScript.newPage();
await fallback.goto(base + '/', { waitUntil: 'load' });
await checkHomepageTypography(fallback, '/ @390px no-script macOS fallback', 'macos', 390);
await noScript.close();

// Start each homepage check at the top: a link scrolled into view by a prior
// interaction does not prove a first-time phone visitor can reach it.
for (const viewport of [
  { width: 375, height: 667 },
  { width: 390, height: 844 },
  { width: 979, height: 900 },
  { width: 980, height: 900 },
  { width: 1440, height: 900 },
]) {
  await page.setViewportSize(viewport);
  await page.goto(base + '/', { waitUntil: 'load' });
  const links = page.getByRole('link', { name: 'See it work', exact: true });
  const count = await links.count();
  const label = `/ @${viewport.width}x${viewport.height}`;
  if (count !== 1) {
    failures.push(`${label} exposes ${count} See it work links, expected one`);
    continue;
  }
  const link = links.first();
  if (await link.getAttribute('href') !== '#see-it-work') {
    failures.push(`${label} See it work does not target #see-it-work`);
  }
  if (viewport.width < 980) {
    const heading = await page.locator('.hero h1').boundingBox();
    const target = await link.boundingBox();
    const figure = await page.locator('.hero figure').boundingBox();
    if (!heading || !target || !figure) {
      failures.push(`${label} cannot measure the headline, link and figure`);
      continue;
    }
    const headingBottom = heading.y + heading.height;
    const linkBottom = target.y + target.height;
    console.log(`${label}: heading.bottom=${headingBottom}, link.top=${target.y}, link.bottom=${linkBottom}, figure.top=${figure.y}`);
    if (headingBottom > target.y || linkBottom > figure.y || linkBottom > viewport.height) {
      failures.push(`${label} See it work must fit below the headline and before the figure on the initial screen`);
    }
    if (!await link.evaluate((e) => Boolean(e.compareDocumentPosition(document.querySelector('.hero figure')) & Node.DOCUMENT_POSITION_FOLLOWING))) {
      failures.push(`${label} See it work must precede the figure in source order`);
    }
  } else if (!await link.evaluate((e) => Boolean(e.closest('.hero .cta')))) {
    failures.push(`${label} See it work must remain in the download action group`);
  }
}

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

        /*
         * What is left once every link's text is removed has to contain an
         * actual WORD, not merely characters.
         *
         * Counting leftover length exempted a comma-separated list of links:
         * `<p><a>A</a>, <a>B</a>, <a>C</a></p>` leaves ", , ", four characters,
         * which passed a length threshold. That is a link list, not a sentence,
         * and it is exactly the standalone-link shape this check exists to
         * find. Requiring three consecutive letters keeps WCAG's real exemption
         * ("See <link>." is a sentence, and "See" is a word) while refusing
         * punctuation and whitespace as evidence of prose.
         */
        let remainder = prose;
        for (const t of [...p.querySelectorAll('a')].map((a) => (a.textContent || '').trim())) {
          if (t) remainder = remainder.replace(t, ' ');
        }
        return /[A-Za-z]{3,}/.test(remainder) && prose.length > linkText.length;
      };

      /*
       * ⚠️ `checkVisibility()` bare is weaker than it looks: it catches
       * `display: none` and a closed <details>, and returns TRUE for
       * `visibility: hidden`, `opacity: 0`, and the clip-path technique this
       * site uses for `.visually-hidden`. A visually-hidden link measures about
       * 1x1, so bare it would be reported as a real 1x1 target — a false
       * positive, which is how a CI gate ends up switched off.
       *
       * The options below cover the first two. Clip-path is not expressible
       * here, so the class is named: it is the site's own technique and is what
       * `.visually-hidden` means.
       */
      const isVisible = (e) =>
        e.checkVisibility({
          contentVisibilityAuto: true,
          opacityProperty: true,
          visibilityProperty: true,
        }) && !e.closest('.visually-hidden');

      const targets = [...document.querySelectorAll('a, button')].filter((e) => {
        if (!isVisible(e)) return false;
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
