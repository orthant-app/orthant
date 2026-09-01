export interface ReleaseEntry {
  version: string;
  build: number;
  channel: 'stable' | 'beta';
  published: boolean;
  date: Date;
}

/**
 * Entries the site may show, newest first.
 *
 * Sorted by `build`, not by version string or date: CFBundleVersion is the one
 * monotonic sequence across betas and stables, and it is what Sparkle compares.
 */
export function publishedStable<T extends ReleaseEntry>(entries: T[]): T[] {
  return entries
    .filter((e) => e.published && e.channel === 'stable')
    .sort((a, b) => b.build - a.build);
}

/** The version the site advertises, or null before anything is published. */
export function currentVersion(entries: ReleaseEntry[]): string | null {
  const [newest] = publishedStable(entries);
  return newest ? newest.version : null;
}
