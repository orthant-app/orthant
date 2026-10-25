import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import handler from './index';
import {
  FALLBACK_URL,
  FEED_URLS,
  SECURITY_HEADERS,
  downloadRoute,
  handleDownload,
  platformOf,
  runtimeCache,
  runtimeDeps,
  type CacheLike,
} from './download';

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

  /*
   * The stall cases. Every other failure here REJECTS, which the catch has
   * always handled; a request that simply never settles reached nothing at
   * all, so /download hung for as long as the runtime allowed.
   *
   * Two shapes, because they fail at different points and a deadline on the
   * connection alone would only catch the first: headers that never arrive,
   * and headers that arrive over a body that never finishes.
   *
   * Both fetches honour the abort signal, which is what the real one does.
   * Fake timers are why the deadline uses an explicit AbortController —
   * AbortSignal.timeout() schedules natively and would not advance here.
   */
  /** Never answers; rejects when aborted, as a real fetch does. */
  const neverAnswers = ((_url: string, init?: RequestInit) =>
    new Promise<Response>((_, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new Error('aborted')));
    })) as unknown as typeof fetch;

  /** 200 whose body never completes. Aborting ERRORS the stream, which is what
   *  a real fetch does to a response body when its signal fires — modelling it
   *  any other way would test a deadline that cannot fail. */
  const stallsMidBody = ((_url: string, init?: RequestInit) => {
    let ctrl!: ReadableStreamDefaultController<Uint8Array>;
    const body = new ReadableStream<Uint8Array>({ start: (c) => { ctrl = c; } });
    init?.signal?.addEventListener('abort', () => ctrl.error(new Error('aborted')));
    return Promise.resolve(new Response(body, { status: 200 }));
  }) as unknown as typeof fetch;

  it.each([
    ['never answers', neverAnswers],
    ['answers and then stalls mid-body', stallsMidBody],
  ])('falls back when the feed %s', async (_name, stalling) => {
    vi.useFakeTimers();
    try {
      const pending = handleDownload({ fetch: stalling, cache: memoryCache() });
      await vi.advanceTimersByTimeAsync(5000);
      const res = await pending;
      expect(res.status).toBe(302);
      expect(res.headers.get('location')).toBe(FALLBACK_URL);
      expect(res.headers.get('cache-control')).toBe('no-store');
    } finally {
      vi.useRealTimers();
    }
  });

  /*
   * The two copies of the policy must agree.
   *
   * download.ts says "matching public/_headers exactly - keep the two in sync
   * by hand; nothing shares them at build time", and nothing did. They are
   * genuinely two files (Cloudflare does not apply _headers to a Worker
   * response, which is why the Worker carries its own set), so they cannot be
   * collapsed into one - but they can be asserted equal, which is the part
   * that was missing. Drift here means a page served through the Worker and
   * the same page served as a static asset ship different policies, and only
   * one of them gets reviewed.
   */
  it('declares the same CSP as public/_headers', () => {
    const headers = readFileSync('public/_headers', 'utf8');
    const line = /^\s*Content-Security-Policy:\s*(.+)$/m.exec(headers);
    expect(line, 'no Content-Security-Policy line in public/_headers').not.toBeNull();
    expect(SECURITY_HEADERS['content-security-policy']).toBe(line![1].trim());
  });

  // The privacy page makes a factual claim about this policy, and the two
  // have disagreed before: for a while the page claimed Cloudflare Web
  // Analytics while the CSP blocked its beacon, then the reverse. The beacon
  // is the ONE third-party origin the policy admits (decided 2026-09-05: page
  // views are wanted, and the beacon is cookieless), and the privacy page
  // must say so. Pinning both together means changing one without the other
  // fails rather than quietly making the page untrue in either direction.
  it('permits exactly one third-party origin, the analytics beacon, and says so', () => {
    const csp = SECURITY_HEADERS['content-security-policy'];
    expect(csp).toContain("script-src 'self' https://static.cloudflareinsights.com;");
    expect(csp).toContain("connect-src 'self' https://cloudflareinsights.com;");
    // Nothing else third-party: every other directive is 'self' (plus data: images).
    expect(csp.replace(/https:\/\/(static\.)?cloudflareinsights\.com/g, '')).not.toMatch(/https?:/);

    const privacy = readFileSync('src/pages/privacy.astro', 'utf8');
    expect(privacy).toContain('Cloudflare Web Analytics');
  });

  /*
   * The bug this whole file could not see.
   *
   * index.ts passed `globalThis.fetch` into the deps object, which detaches
   * it, so `deps.fetch(...)` ran with `this === deps`. workerd rejects that
   * with "Illegal invocation", handleDownload catches every fetch failure, and
   * the result was a /download that silently served the releases listing
   * instead of the DMG on every single request.
   *
   * Every test above injects a plain async function, which has no `this`
   * requirement, so none of them could reach it; the workerd smoke test
   * asserted the fallback URL, i.e. it asserted the bug. This models workerd's
   * actual rule instead, which is why it fails when the bind is removed.
   */
  it('binds the global fetch, so calling it as a method is legal', async () => {
    const real = globalThis.fetch;
    globalThis.fetch = function (this: unknown) {
      if (this !== globalThis && this !== undefined) {
        throw new TypeError('Illegal invocation: function called with incorrect `this` reference.');
      }
      return Promise.resolve(ok(FEED));
    } as unknown as typeof fetch;
    try {
      // Called as a METHOD of the deps object, exactly as handleDownload calls it.
      const deps = runtimeDeps();
      await expect(deps.fetch('https://example.com/')).resolves.toBeInstanceOf(Response);
    } finally {
      globalThis.fetch = real;
    }
  });

  it('resolves the DMG end to end through the production deps', async () => {
    const real = globalThis.fetch;
    globalThis.fetch = function (this: unknown) {
      if (this !== globalThis && this !== undefined) {
        throw new TypeError('Illegal invocation: function called with incorrect `this` reference.');
      }
      return Promise.resolve(ok(FEED));
    } as unknown as typeof fetch;
    try {
      // The real deps' fetch, but a memory cache: runtimeCache() reaches for
      // caches.default, which only exists inside workerd.
      const res = await handleDownload({ fetch: runtimeDeps().fetch, cache: memoryCache() });
      expect(res.headers.get('location')).toBe(GOOD);
    } finally {
      globalThis.fetch = real;
    }
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

  it('carries the CSP and Permissions-Policy too, not just three of the five', async () => {
    const res = await handleDownload({ fetch: async () => ok(FEED), cache: memoryCache() });
    expect(res.headers.get('content-security-policy')).toContain("default-src 'self'");
    expect(res.headers.get('permissions-policy')).toBe('camera=(), microphone=(), geolocation=()');
  });
});

// Cloudflare does not apply public/_headers to a response this Worker
// returns, even one obtained by passing env.ASSETS.fetch() straight through
// — so the ASSETS fallthrough (everything except /download, including a 404
// served via wrangler.jsonc's not_found_handling) must carry the same
// headers itself or it ships with no CSP at all.
describe('the ASSETS fallthrough', () => {
  const env = { ASSETS: { fetch: async () => new Response('page body', {
    status: 200,
    headers: { 'content-type': 'text/html' },
  }) } };

  it('attaches every security header to an ordinary page response', async () => {
    const res = await handler.fetch(new Request('https://orthant.app/faq/'), env);
    expect(res.headers.get('content-security-policy')).toContain("default-src 'self'");
    expect(res.headers.get('permissions-policy')).toBe('camera=(), microphone=(), geolocation=()');
    expect(res.headers.get('x-content-type-options')).toBe('nosniff');
    expect(res.headers.get('referrer-policy')).toBe('strict-origin-when-cross-origin');
    expect(res.headers.get('strict-transport-security')).toBe('max-age=31536000; includeSubDomains');
  });

  it('preserves the original response body and headers alongside the added ones', async () => {
    const res = await handler.fetch(new Request('https://orthant.app/faq/'), env);
    expect(res.headers.get('content-type')).toBe('text/html');
    expect(await res.text()).toBe('page body');
  });

  it('attaches the same headers to a 404 (the case the review flagged as likely bare)', async () => {
    const notFoundEnv = { ASSETS: { fetch: async () => new Response('not found', { status: 404 }) } };
    const res = await handler.fetch(new Request('https://orthant.app/does/not/exist'), notFoundEnv);
    expect(res.status).toBe(404);
    expect(res.headers.get('content-security-policy')).toContain("default-src 'self'");
  });
});

const GOOD_WIN = 'https://github.com/orthant-app/orthant/releases/download/v1.0.4/Orthant-1.0.4-setup.exe';

const WIN_FEED = `<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
  <sparkle:shortVersionString>1.0.4</sparkle:shortVersionString>
  <enclosure url="${GOOD_WIN}" length="11572434"/>
</item></channel></rss>`;

/** A fetch that answers each feed URL as `answers` says: a body, a status, or
 *  a promise that never settles until aborted. */
function feeds(answers: Record<string, string | number | 'never'>): typeof fetch {
  return ((url: string, init?: RequestInit) => {
    const answer = answers[url] ?? 404;
    if (answer === 'never') {
      return new Promise<Response>((_, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new Error('aborted')));
      });
    }
    if (typeof answer === 'number') return Promise.resolve(new Response('', { status: answer }));
    return Promise.resolve(ok(answer));
  }) as unknown as typeof fetch;
}

describe('platformOf', () => {
  const headers = (h: Record<string, string>) => new Headers(h);
  const WIN_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  const MAC_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  it('reads the platform hint Chromium sends', () => {
    expect(platformOf(headers({ 'sec-ch-ua-platform': '"Windows"' }))).toBe('windows');
    expect(platformOf(headers({ 'sec-ch-ua-platform': '"macOS"' }))).toBe('macos');
  });

  it('believes the hint over the User-Agent', () => {
    expect(platformOf(headers({ 'sec-ch-ua-platform': '"macOS"', 'user-agent': WIN_UA }))).toBe('macos');
  });

  it('reads the User-Agent when there is no hint, as from Firefox or Safari', () => {
    expect(platformOf(headers({ 'user-agent': WIN_UA }))).toBe('windows');
    expect(platformOf(headers({ 'user-agent': MAC_UA }))).toBe('macos');
  });

  it('offers macOS to anything else', () => {
    expect(platformOf(headers({ 'sec-ch-ua-platform': '"Linux"' }))).toBe('macos');
    expect(platformOf(headers({ 'user-agent': 'curl/8.7.1' }))).toBe('macos');
    expect(platformOf(headers({}))).toBe('macos');
  });
});

describe('downloadRoute', () => {
  const win = new Headers({ 'sec-ch-ua-platform': '"Windows"' });
  const mac = new Headers({ 'sec-ch-ua-platform': '"macOS"' });

  it('answers /download with the visitor\'s platform, then macOS', () => {
    expect(downloadRoute('/download', win)).toEqual({ platforms: ['windows', 'macos'], vary: true });
    expect(downloadRoute('/download/', win)).toEqual({ platforms: ['windows', 'macos'], vary: true });
    expect(downloadRoute('/download', mac)).toEqual({ platforms: ['macos'], vary: true });
  });

  it('answers a named platform with that platform alone, for anyone', () => {
    expect(downloadRoute('/download/windows', mac)).toEqual({ platforms: ['windows'], vary: false });
    expect(downloadRoute('/download/macos/', win)).toEqual({ platforms: ['macos'], vary: false });
  });

  it('is not a download route for anything else', () => {
    for (const path of ['/downloads', '/download/linux', '/download/windows/x', '/download/Windows', '/']) {
      expect(downloadRoute(path, win), path).toBeNull();
    }
  });
});

describe('handleDownload for a platform', () => {
  const both = { [FEED_URLS.macos]: FEED, [FEED_URLS.windows]: WIN_FEED };

  it('302s a Windows request to the installer', async () => {
    const res = await handleDownload({ fetch: feeds(both), cache: memoryCache() }, ['windows']);
    expect(res.headers.get('location')).toBe(GOOD_WIN);
  });

  it('answers a Windows visitor with the DMG while Windows has no stable feed, as before', async () => {
    const res = await handleDownload(
      { fetch: feeds({ [FEED_URLS.macos]: FEED, [FEED_URLS.windows]: 404 }), cache: memoryCache() },
      ['windows', 'macos'],
      true,
    );
    expect(res.headers.get('location')).toBe(GOOD);
    // Once Windows ships, the same answer means its feed failed for a moment:
    // the other platform's artifact is never kept.
    expect(res.headers.get('cache-control')).toBe('no-store');
  });

  it('prefers the installer for a Windows visitor once there is one', async () => {
    const res = await handleDownload({ fetch: feeds(both), cache: memoryCache() }, ['windows', 'macos'], true);
    expect(res.headers.get('location')).toBe(GOOD_WIN);
    expect(res.headers.get('cache-control')).toBe('public, max-age=300');
  });

  it('falls back when a named platform has no release, never to the other platform\'s', async () => {
    const res = await handleDownload(
      { fetch: feeds({ [FEED_URLS.macos]: FEED, [FEED_URLS.windows]: 404 }), cache: memoryCache() },
      ['windows'],
    );
    expect(res.headers.get('location')).toBe(FALLBACK_URL);
    expect(res.headers.get('cache-control')).toBe('no-store');
  });

  it('keeps each platform\'s target under its own key', async () => {
    const cache = memoryCache();
    await handleDownload({ fetch: feeds(both), cache }, ['windows']);
    await handleDownload({ fetch: feeds(both), cache }, ['macos']);
    expect(cache.store.get('download-target-windows')).toBe(GOOD_WIN);
    expect(cache.store.get('download-target')).toBe(GOOD);
  });

  it('never serves the cached DMG to a Windows request', async () => {
    const cache = memoryCache();
    await cache.put('download-target', GOOD);
    const res = await handleDownload({ fetch: feeds({ [FEED_URLS.windows]: 404 }), cache }, ['windows']);
    expect(res.headers.get('location')).toBe(FALLBACK_URL);
  });

  it('marks an answer chosen from the visitor\'s headers, and only that one', async () => {
    const chosen = await handleDownload({ fetch: feeds(both), cache: memoryCache() }, ['macos'], true);
    const named = await handleDownload({ fetch: feeds(both), cache: memoryCache() }, ['macos']);
    expect(chosen.headers.get('vary')).toBe('User-Agent, Sec-CH-UA-Platform');
    expect(named.headers.get('vary')).toBeNull();
  });

  it('bounds the whole answer by one deadline, not one per platform', async () => {
    vi.useFakeTimers();
    try {
      let settled = false;
      const pending = handleDownload(
        { fetch: feeds({ [FEED_URLS.macos]: 'never', [FEED_URLS.windows]: 'never' }), cache: memoryCache() },
        ['windows', 'macos'],
        true,
      ).then((res) => { settled = true; return res; });
      await vi.advanceTimersByTimeAsync(3500);
      expect(settled).toBe(true);
      expect((await pending).headers.get('location')).toBe(FALLBACK_URL);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('runtimeCache', () => {
  it('keeps one entry per key', async () => {
    const store = new Map<string, string>();
    const real = (globalThis as { caches?: unknown }).caches;
    (globalThis as { caches?: unknown }).caches = {
      default: {
        async match(req: Request) {
          const v = store.get(req.url);
          return v === undefined ? undefined : new Response(v);
        },
        async put(req: Request, res: Response) { store.set(req.url, await res.text()); },
      },
    };
    try {
      const cache = runtimeCache();
      await cache.put('download-target', GOOD);
      await cache.put('download-target-windows', GOOD_WIN);
      expect(await cache.match('download-target')).toBe(GOOD);
      expect(await cache.match('download-target-windows')).toBe(GOOD_WIN);
    } finally {
      (globalThis as { caches?: unknown }).caches = real;
    }
  });
});

describe('the download routes', () => {
  const env = { ASSETS: { fetch: async () => new Response('the 404 page', { status: 404 }) } };

  it('sends a named platform to its own artifact through the entry module', async () => {
    const realFetch = globalThis.fetch;
    const realCaches = (globalThis as { caches?: unknown }).caches;
    globalThis.fetch = feeds({ [FEED_URLS.macos]: FEED, [FEED_URLS.windows]: WIN_FEED }).bind(globalThis);
    (globalThis as { caches?: unknown }).caches = {
      default: { async match() { return undefined; }, async put() {} },
    };
    try {
      const win = await handler.fetch(new Request('https://orthant.app/download/windows'), env);
      expect(win.headers.get('location')).toBe(GOOD_WIN);
      const mac = await handler.fetch(new Request('https://orthant.app/download/macos/'), env);
      expect(mac.headers.get('location')).toBe(GOOD);
    } finally {
      globalThis.fetch = realFetch;
      (globalThis as { caches?: unknown }).caches = realCaches;
    }
  });

  it('leaves a path that only looks like one to the assets', async () => {
    const res = await handler.fetch(new Request('https://orthant.app/download/linux'), env);
    expect(res.status).toBe(404);
    expect(await res.text()).toBe('the 404 page');
  });
});
