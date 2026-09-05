import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import handler from './index';
import { FALLBACK_URL, SECURITY_HEADERS, handleDownload, runtimeDeps, type CacheLike } from './download';

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

  // The privacy page makes a factual claim about this policy. It said the site
  // used Cloudflare Web Analytics while the site had never been deployed, so
  // the claim had never once been true; the beacon's origins are now out of
  // the CSP and the claim is gone. Pinning both together means removing one
  // without the other fails rather than quietly re-opening the permission.
  it('permits no third-party script or connect origin', () => {
    const csp = SECURITY_HEADERS['content-security-policy'];
    expect(csp).toContain("script-src 'self';");
    expect(csp).toContain("connect-src 'self';");
    expect(csp).not.toContain('cloudflareinsights');

    const privacy = readFileSync('src/pages/privacy.astro', 'utf8');
    expect(privacy).not.toContain('Cloudflare Web Analytics');
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
