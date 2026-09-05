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
