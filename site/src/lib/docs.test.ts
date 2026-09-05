import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { GROUPS, docsGroups, docsSequence, type DocsPage } from './docs';

/** Enough of a collection entry to exercise grouping. */
const page = (id: string, group: string, order: number) =>
  ({ id, data: { group, order } }) as unknown as DocsPage;

// Deliberately out of order, so a passing test means sorting happened.
const pages = [
  page('uninstall', 'help', 4),
  page('shortcuts', 'start', 2),
  page('grid-overlay', 'place', 1),
  page('troubleshooting', 'help', 1),
  page('getting-started', 'start', 1),
  page('settings', 'help', 2),
  page('custom-regions', 'place', 2),
  page('updates', 'help', 3),
  page('multiple-displays', 'place', 3),
];

describe('docsGroups', () => {
  it('puts help last and names it for the reader, not the feature', () => {
    expect(GROUPS.map((g) => g.id)).toEqual(['start', 'place', 'help']);
    expect(GROUPS[2].title).toBe('Help & upkeep');
  });

  // The point of the whole regrouping: troubleshooting leads its group rather
  // than sitting fourth inside one named after configuration.
  it('leads Help & upkeep with troubleshooting', () => {
    const help = docsGroups(pages).find((g) => g.id === 'help')!;
    expect(help.pages[0].id).toBe('troubleshooting');
  });

  it('sorts within a group and keeps groups in reading order', () => {
    expect(docsGroups(pages).map((g) => g.pages.map((p) => p.id))).toEqual([
      ['getting-started', 'shortcuts'],
      ['grid-overlay', 'custom-regions', 'multiple-displays'],
      ['troubleshooting', 'settings', 'updates', 'uninstall'],
    ]);
  });
});

describe('docsSequence', () => {
  // `order` restarts per group, so a flat sort would interleave them and the
  // "next" link would send a reader backwards between groups.
  it('is one flat reading order across groups', () => {
    expect(docsSequence(pages).map((p) => p.id)).toEqual([
      'getting-started', 'shortcuts',
      'grid-overlay', 'custom-regions', 'multiple-displays',
      'troubleshooting', 'settings', 'updates', 'uninstall',
    ]);
  });
});

/*
 * The tests above prove the FUNCTION is right. They do not prove the page
 * calls it, and that gap shipped: grouping landed while [...slug].astro still
 * sorted flat on `order`, which restarts per group, so 6 of 9 pages pointed at
 * the wrong next page and every test here stayed green.
 *
 * Reads built output, so `npm run build` must have run. ⚠️ A source-level
 * mutation is invisible to this test without a rebuild first.
 */
describe("the rendered docs pages' next links", () => {
  const DIST = 'dist/docs';
  const expected = docsSequence(pages).map((p) => p.id);

  it('walk the group sequence, and stop at the last page', () => {
    if (!existsSync(DIST)) throw new Error(`${DIST} missing - run \`npm run build\` first`);

    const chain = expected.map((id) => {
      const html = readFileSync(`${DIST}/${id}/index.html`, 'utf8');
      const m = /class="next" href="\/docs\/([^/]+)\//.exec(html);
      return m ? m[1] : null;
    });

    // Each page points at the one after it; the last points nowhere.
    expect(chain).toEqual([...expected.slice(1), null]);
  });
});

/*
 * The desktop sidebar must not be a <details> that CSS forces open.
 *
 * It was, and the cost was invisible to every check this project had: at
 * 1440px WebKit rendered all nine links and exposed ZERO of them to the
 * accessibility tree, while Chromium exposed all nine. `checkVisibility()`
 * said nine in both. The `open` attribute is the element's own state, and an
 * engine may derive semantics from it rather than from computed style, so
 * `::details-content { content-visibility: visible }` bought appearance
 * without meaning.
 *
 * CI's responsive sweep runs Chromium, so no browser check here would have
 * caught it either. These are structural instead: they assert the technique is
 * gone and that the desktop list really is its own element.
 */
describe('the docs sidebar', () => {
  const page = 'src/pages/docs/[...slug].astro';

  it('never reveals collapsed <details> content with CSS', () => {
    const source = readFileSync(page, 'utf8');
    // The <style> block only, with CSS comments stripped. Both the template
    // above it and the comment inside it explain the technique being forbidden
    // by naming it, so scanning the whole file trips on its own prose — the
    // same reason hero-default.test.ts scopes its `order:` check this way.
    const style = /<style>([\s\S]*)<\/style>/.exec(source);
    expect(style, '<style> block not found').not.toBeNull();
    const css = style![1].replace(/\/\*[\s\S]*?\*\//g, '');

    // Both halves of the old technique. Either one alone is enough to
    // reintroduce the split between what is drawn and what is exposed.
    expect(css).not.toContain('::details-content');
    expect(css).not.toContain('content-visibility');
  });

  it('renders the desktop list outside the disclosure', () => {
    const html = readFileSync('dist/docs/shortcuts/index.html', 'utf8');
    const details = /<details[^>]*>[\s\S]*?<\/details>/.exec(html);
    expect(details, 'no <details> in the built docs page').not.toBeNull();

    // Every doc must be linked from markup that is NOT inside the disclosure.
    const outside = html.replace(details![0], '');
    for (const id of docsSequence(pages).map((p) => p.id)) {
      expect(outside, `/docs/${id}/ is only reachable inside <details>`)
        .toContain(`href="/docs/${id}/"`);
    }
  });
});
