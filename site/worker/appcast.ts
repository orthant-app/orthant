const REPO_PREFIX = '/orthant-app/orthant/releases/download/';
const DMG = /^Orthant-(\d+\.\d+\.\d+)\.dmg$/;

/** The first <item>…</item>, or null. */
function firstItem(xml: string): string | null {
  const m = /<item\b[^>]*>([\s\S]*?)<\/item>/.exec(xml);
  return m ? m[1] : null;
}

/** The item with every <sparkle:deltas>…</sparkle:deltas> region removed. */
function withoutDeltas(item: string): string {
  return item.replace(/<sparkle:deltas\b[\s\S]*?<\/sparkle:deltas>/g, '');
}

function enclosureUrls(item: string): string[] {
  const urls: string[] = [];
  const re = /<enclosure\b[^>]*\burl="([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(item)) !== null) urls.push(m[1]);
  return urls;
}

function shortVersion(item: string): string | null {
  const m = /<sparkle:shortVersionString>([^<]*)<\/sparkle:shortVersionString>/.exec(item);
  return m ? m[1].trim() : null;
}

/**
 * The current full-DMG download URL, or null if the feed cannot be trusted.
 *
 * `/download` 302s to whatever this returns, so an unvalidated result would be
 * an open redirect driven by a fetched document. Every field is checked against
 * an allowlist; anything unrecognised returns null and the caller falls back to
 * the releases page.
 */
export function resolveDownloadUrl(xml: string): string | null {
  const item = firstItem(xml);
  if (item === null) return null;

  const full = enclosureUrls(withoutDeltas(item));
  if (full.length !== 1) return null; // zero, or ambiguous — never guess

  let url: URL;
  try {
    url = new URL(full[0]);
  } catch {
    return null;
  }

  if (url.protocol !== 'https:') return null;
  if (url.hostname !== 'github.com') return null;
  if (url.username !== '' || url.password !== '') return null;
  if (url.port !== '') return null;
  if (url.search !== '' || url.hash !== '') return null;
  // URL normalises `..`, so a traversal cannot survive this prefix check.
  if (!url.pathname.startsWith(REPO_PREFIX)) return null;

  const filename = url.pathname.slice(url.pathname.lastIndexOf('/') + 1);
  const named = DMG.exec(filename);
  if (named === null) return null;

  const declared = shortVersion(item);
  if (declared === null || declared !== named[1]) return null;

  return url.href;
}
