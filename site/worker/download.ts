import { resolveDownloadUrl, type Platform } from './appcast';

// Workers-only default cache. @cloudflare/workers-types declares the same
// global name as the DOM lib (which the project keeps for the hero's client
// script), and the two do not merge, so `caches.default` does not typecheck
// without this. Augmenting is additive and keeps DOM available everywhere
// else, unlike narrowing the project's `lib`. The cost is that `caches.default`
// would also typecheck in browser code, where it does not exist at runtime —
// inert today, since nothing under src/ touches `caches` at all.
declare global {
  interface CacheStorage {
    readonly default: Cache;
  }
}

/** Each platform's stable feed. The Windows one is a 404 until the first
 *  Windows stable is published, and a 404 is the one answer that means "no
 *  release yet" rather than "could not tell". */
export const FEED_URLS: Record<Platform, string> = {
  macos: 'https://updates.orthant.app/appcast.xml',
  windows: 'https://updates.orthant.app/appcast-win.xml',
};
export const FEED_URL = FEED_URLS.macos;
export const FALLBACK_URL = 'https://github.com/orthant-app/orthant/releases/latest';

/** 300 s. The GitHub API's rate limit drove the original long-TTL design; the
 *  appcast is our own CDN-served document with no limit, so the TTL now only
 *  saves latency. A new release therefore takes up to 5 minutes to appear here
 *  — the post-release check must wait that out. */
const TTL_SECONDS = 300;
/** macOS keeps the key it has always had, so a deploy does not empty it. */
const CACHE_KEYS: Record<Platform, string> = {
  macos: 'download-target',
  windows: 'download-target-windows',
};

/** 3 s to fetch the feed AND read its body, after which the fallback wins.
 *
 *  Without a deadline this handler had no bounded running time. The catch
 *  below turns a *rejected* fetch into the fallback, but a request that simply
 *  never settles never reaches it — the visitor sits on /download with nothing
 *  happening, which is strictly worse than being sent to the releases page.
 *
 *  It has to cover the body read too, not just the connection: a response
 *  whose headers arrive and whose body never finishes is the same stall
 *  wearing a different face. One AbortSignal does both, because aborting after
 *  the response is returned errors its body stream as well.
 *
 *  An explicit controller rather than AbortSignal.timeout(): that schedules on
 *  a native timer, which fake timers do not intercept, so the stall would only
 *  be testable in real time. */
const DEADLINE_MS = 3000;

/** What asking for one feed came to: its body, `absent` when the feed answers
 *  404 (nothing published there yet), or `failed` for every other way it can
 *  fail to arrive usably: rejected, any other non-200, or too slow. */
type Feed = { body: string } | 'absent' | 'failed';

async function fetchFeed(deps: Deps, url: string): Promise<Feed> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEADLINE_MS);
  try {
    const res = await deps.fetch(url, { signal: controller.signal });
    if (res.status === 404) return 'absent';
    if (!res.ok) return 'failed';
    return { body: await res.text() };
  } catch {
    return 'failed';
  } finally {
    clearTimeout(timer);
  }
}

export interface CacheLike {
  match(key: string): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

export interface Deps {
  fetch: typeof fetch;
  cache: CacheLike;
}

/** The complete set spec §8.1 calls for, matching public/_headers exactly —
 *  keep the two in sync by hand; nothing shares them at build time.
 *
 *  Applied to every Worker-generated response AND re-attached, by index.ts's
 *  fetch handler, to every ASSETS fallthrough response, including the 404
 *  page. Cloudflare does NOT apply public/_headers to a response a Worker
 *  returns, even one obtained by calling env.ASSETS.fetch() and passing it
 *  straight through — so without this, every non-asset path (which is
 *  everything except a handful of static files, once a Worker route exists
 *  at all) would ship with no CSP. Pages reached without going through a
 *  Worker fetch handler at all still get the same set directly from
 *  public/_headers.
 *
 *  Exported (rather than living in index.ts, where this constant used to be)
 *  because index.ts is the Worker's entry module: workerd treats every named
 *  export of the entry module as a candidate entrypoint, so anything that
 *  isn't a function, a class, or an ExportedHandler fails the runtime's own
 *  boot — see worker/index.ts's module comment. */
export const SECURITY_HEADERS: Record<string, string> = {
  'content-security-policy':
    "default-src 'self'; script-src 'self' https://static.cloudflareinsights.com; style-src 'self'; img-src 'self' data:; media-src 'self'; connect-src 'self' https://cloudflareinsights.com; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  'referrer-policy': 'strict-origin-when-cross-origin',
  'x-content-type-options': 'nosniff',
  'strict-transport-security': 'max-age=31536000; includeSubDomains',
  'permissions-policy': 'camera=(), microphone=(), geolocation=()',
};

function redirect(location: string, cacheControl: string, vary: boolean): Response {
  const headers: Record<string, string> = { location, 'cache-control': cacheControl, ...SECURITY_HEADERS };
  // The answer depends on who asks, so a cache that keeps it must keep one
  // per platform.
  if (vary) headers.vary = 'User-Agent, Sec-CH-UA-Platform';
  return new Response(null, { status: 302, headers });
}

/** One platform's current artifact, from the cache or its feed: a `url`,
 *  `absent` when its feed says nothing is published, or `failed` when it
 *  cannot be had for any other reason. A failure is never cached: a transient
 *  bad feed must not pin the download button to the fallback for the whole
 *  TTL. */
type Target = { url: string } | 'absent' | 'failed';

async function resolveTarget(deps: Deps, platform: Platform): Promise<Target> {
  const key = CACHE_KEYS[platform];
  const cached = await deps.cache.match(key).catch(() => null);
  if (cached) return { url: cached };

  const feed = await fetchFeed(deps, FEED_URLS[platform]);
  if (feed === 'absent' || feed === 'failed') return feed;

  const url = resolveDownloadUrl(feed.body, platform);
  if (url === null) return 'failed';

  await deps.cache.put(key, url).catch(() => {});
  return { url };
}

/**
 * A redirect to the first of `platforms` whose artifact can be had, or to the
 * releases page when none can. Every candidate is resolved at once, so the
 * deadline bounds the whole answer rather than each candidate in turn.
 * `vary` marks an answer chosen from the request's headers.
 *
 * A candidate whose feed is absent (404) has no release yet, so the next one
 * answers: that is how a Windows visitor is given the DMG until Windows ships.
 * A candidate whose feed failed in any other way ends the walk at the releases
 * page: it may well have a release, and the visitor should not be handed
 * another platform's artifact in its place. A later candidate's answer is
 * never kept.
 */
export async function handleDownload(
  deps: Deps,
  platforms: Platform[] = ['macos'],
  vary = false,
): Promise<Response> {
  const targets = await Promise.all(platforms.map((p) => resolveTarget(deps, p)));
  const i = targets.findIndex((t) => t !== 'absent');
  const t = i < 0 ? 'absent' : targets[i];
  if (t === 'absent' || t === 'failed') return redirect(FALLBACK_URL, 'no-store', vary);
  return redirect(t.url, i === 0 ? `public, max-age=${TTL_SECONDS}` : 'no-store', vary);
}

/**
 * The platform a visitor's browser runs on: its `Sec-CH-UA-Platform` hint
 * when it sends one (Chromium does, on every request), otherwise its
 * User-Agent, where every Windows browser names "Windows NT". Anything else
 * is offered macOS, as every visitor was before Windows shipped.
 */
export function platformOf(headers: Headers): Platform {
  const hint = headers.get('sec-ch-ua-platform');
  if (hint !== null) {
    return hint.replace(/"/g, '').trim().toLowerCase() === 'windows' ? 'windows' : 'macos';
  }
  return /\bWindows NT\b/.test(headers.get('user-agent') ?? '') ? 'windows' : 'macos';
}

/**
 * What a download path asks for: a platform it names, or, at /download, the
 * visitor's own, with macOS's as the answer only when theirs has no release
 * yet, its feed being absent (as every visitor was answered before Windows
 * shipped). Null for a path that is not a download.
 */
export function downloadRoute(
  pathname: string,
  headers: Headers,
): { platforms: Platform[]; vary: boolean } | null {
  const m = /^\/download(?:\/(macos|windows))?\/?$/.exec(pathname);
  if (m === null) return null;
  if (m[1] !== undefined) return { platforms: [m[1] as Platform], vary: false };
  return platformOf(headers) === 'windows'
    ? { platforms: ['windows', 'macos'], vary: true }
    : { platforms: ['macos'], vary: true };
}

/**
 * The dependencies handleDownload runs with in production.
 *
 * ⚠️ `fetch` is BOUND, and that is the whole point of this function existing.
 *
 * workerd requires the global fetch to be invoked with the global as its
 * `this`. Passing `globalThis.fetch` into an object detaches it, so
 * `deps.fetch(...)` runs with `this === deps` and throws
 * "Illegal invocation: function called with incorrect `this` reference".
 * handleDownload catches every fetch failure and falls back, so the symptom
 * was not an error page: /download quietly redirected to the releases listing
 * instead of the DMG, on every request since the Worker was first written.
 *
 * Nothing caught it. The unit tests inject a plain async function, which has
 * no `this` requirement, and the workerd smoke test asserted the fallback URL
 * — i.e. it asserted the bug. It took a real deployment and `wrangler dev
 * --remote` to see the exception at all.
 *
 * It lives here rather than in index.ts because index.ts is the entry module,
 * whose named exports workerd treats as candidate entrypoints. Here it is an
 * ordinary export, so runtimeDeps() can be unit-tested directly.
 */
export function runtimeDeps(): Deps {
  return { fetch: globalThis.fetch.bind(globalThis), cache: runtimeCache() };
}

/** Adapts Workers' Cache API, which stores Responses rather than strings, to
 *  CacheLike, one entry per key. */
export function runtimeCache(): CacheLike {
  const request = (key: string) => new Request(`https://orthant.app/__cache/${key}`);
  return {
    async match(key) {
      const hit = await caches.default.match(request(key));
      return hit ? await hit.text() : null;
    },
    async put(key, value) {
      await caches.default.put(
        request(key),
        new Response(value, { headers: { 'cache-control': `max-age=${TTL_SECONDS}` } }),
      );
    },
  };
}
