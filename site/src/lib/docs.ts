import type { CollectionEntry } from 'astro:content';

/** The three groups, in reading order: get it working, use it, keep it working. */
export const GROUPS = [
  { id: 'start', title: 'Getting started' },
  { id: 'place', title: 'Placing windows' },
  { id: 'help', title: 'Help & upkeep' },
] as const;

export type DocsPage = CollectionEntry<'docs'>;
export interface DocsGroup { id: string; title: string; pages: DocsPage[] }

/**
 * Group and sort the docs pages.
 *
 * Takes the pages rather than fetching them: `import type` is erased at build
 * time, so this module pulls in nothing from Astro at runtime and can be
 * unit-tested with plain vitest.
 *
 * The sidebar and the /docs/ index both render this, so they cannot disagree
 * about order or membership — which they did when only the sidebar was grouped
 * and the index stayed a flat list.
 */
export function docsGroups(pages: DocsPage[]): DocsGroup[] {
  return GROUPS.map((g) => ({
    id: g.id,
    title: g.title,
    pages: pages
      .filter((p) => p.data.group === g.id)
      .sort((a, b) => a.data.order - b.data.order),
  }));
}

/**
 * The same pages as one flat reading sequence, for "next" links.
 *
 * `order` restarts inside each group, so a flat sort on `order` alone would
 * interleave groups and send a reader backwards.
 */
export function docsSequence(pages: DocsPage[]): DocsPage[] {
  return docsGroups(pages).flatMap((g) => g.pages);
}
