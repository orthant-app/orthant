import { describe, expect, it, vi } from 'vitest';
import { FALLBACK_URL, handleDownload, type CacheLike } from './index';

const GOOD = 'https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg';

const FEED = `<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
  <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
  <enclosure url="${GOOD}" length="21257025"/>
</item></channel></rss>`;

function memoryCache(): CacheLike & { store: Map<string, string> } {
  const store = new Map<string, string>();
  return {
    store,
    async match(key) { return store.get(key) ?? null; },
    async put(key, value) { store.set(key, value); },
  };
}

const ok = (body: string) => new Response(body, { status: 200 });

describe('handleDownload', () => {
  it('302s to the resolved DMG', async () => {
    const res = await handleDownload({ fetch: async () => ok(FEED), cache: memoryCache() });
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toBe(GOOD);
  });

  it('caches the validated target and does not refetch', async () => {
    const cache = memoryCache();
    const fetchSpy = vi.fn(async () => ok(FEED));
    await handleDownload({ fetch: fetchSpy, cache });
    await handleDownload({ fetch: fetchSpy, cache });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it('serves a cached target without parsing again', async () => {
    const cache = memoryCache();
    await cache.put('download-target', GOOD);
    const res = await handleDownload({ fetch: async () => { throw new Error('must not fetch'); }, cache });
    expect(res.headers.get('location')).toBe(GOOD);
  });

  it('falls back when the feed request fails', async () => {
    const res = await handleDownload({
      fetch: async () => { throw new Error('network'); },
      cache: memoryCache(),
    });
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toBe(FALLBACK_URL);
  });

  it('falls back on a non-200 feed', async () => {
    const res = await handleDownload({
      fetch: async () => new Response('nope', { status: 500 }),
      cache: memoryCache(),
    });
    expect(res.headers.get('location')).toBe(FALLBACK_URL);
  });

  // The plain 500 above cannot verify the `!res.ok` guard: its body is
  // unparseable, so the fallback happens for the wrong reason and the test
  // passes with the guard deleted. This one carries a VALID feed on a 500 —
  // without the guard it resolves and redirects, trusting a response the
  // origin explicitly told us not to.
  it('falls back on a non-200 feed even when its body is a valid appcast', async () => {
    const res = await handleDownload({
      fetch: async () => new Response(FEED, { status: 500 }),
      cache: memoryCache(),
    });
    expect(res.headers.get('location')).toBe(FALLBACK_URL);
  });

  // "caches the validated target" only counts fetches, and "serves a cached
  // target" pre-seeds the cache — so nothing checks that what gets WRITTEN is
  // what was resolved. A cache.put storing the wrong value survives both.
  it('caches the resolved target itself, not merely something', async () => {
    const cache = memoryCache();
    await handleDownload({ fetch: async () => ok(FEED), cache });
    expect(cache.store.get('download-target')).toBe(GOOD);
  });

  it('falls back on an unusable feed', async () => {
    const res = await handleDownload({ fetch: async () => ok('<rss/>'), cache: memoryCache() });
    expect(res.headers.get('location')).toBe(FALLBACK_URL);
  });

  it('does NOT cache a fallback', async () => {
    const cache = memoryCache();
    await handleDownload({ fetch: async () => ok('<rss/>'), cache });
    expect(cache.store.size).toBe(0);
  });

  it('sets no-store on a fallback so a bad answer is never sticky', async () => {
    const res = await handleDownload({ fetch: async () => ok('<rss/>'), cache: memoryCache() });
    expect(res.headers.get('cache-control')).toBe('no-store');
  });

  it('carries the security headers', async () => {
    const res = await handleDownload({ fetch: async () => ok(FEED), cache: memoryCache() });
    expect(res.headers.get('x-content-type-options')).toBe('nosniff');
    expect(res.headers.get('referrer-policy')).toBe('strict-origin-when-cross-origin');
  });
});
