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
