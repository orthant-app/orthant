import { resolveDownloadUrl } from './appcast';

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

export const FEED_URL = 'https://updates.orthant.app/appcast.xml';
export const FALLBACK_URL = 'https://github.com/orthant-app/orthant/releases/latest';

/** 300 s. The GitHub API's rate limit drove the original long-TTL design; the
 *  appcast is our own CDN-served document with no limit, so the TTL now only
 *  saves latency. A new release therefore takes up to 5 minutes to appear here
 *  — the post-release check must wait that out. */
const TTL_SECONDS = 300;
const CACHE_KEY = 'download-target';

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

/** The feed's body, or null for every way it can fail to arrive usably —
 *  rejected, non-200, or too slow. All three take the same fallback, so the
 *  caller does not need to tell them apart. */
async function fetchFeed(deps: Deps): Promise<string | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEADLINE_MS);
  try {
    const res = await deps.fetch(FEED_URL, { signal: controller.signal });
    if (!res.ok) return null;
    return await res.text();
  } catch {
    return null;
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

function redirect(location: string, cacheControl: string): Response {
  return new Response(null, {
    status: 302,
    headers: { location, 'cache-control': cacheControl, ...SECURITY_HEADERS },
  });
}

export async function handleDownload(deps: Deps): Promise<Response> {
  const cached = await deps.cache.match(CACHE_KEY).catch(() => null);
  if (cached) return redirect(cached, `public, max-age=${TTL_SECONDS}`);

  const xml = await fetchFeed(deps);
  if (xml === null) return redirect(FALLBACK_URL, 'no-store');

  const target = resolveDownloadUrl(xml);
  // A failure is never cached: a transient bad feed must not pin the download
  // button to the fallback for the whole TTL.
  if (target === null) return redirect(FALLBACK_URL, 'no-store');

  await deps.cache.put(CACHE_KEY, target).catch(() => {});
  return redirect(target, `public, max-age=${TTL_SECONDS}`);
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

/** Adapts Workers' Cache API — which stores Responses, not strings — to CacheLike. */
export function runtimeCache(): CacheLike {
  const key = new Request(`https://orthant.app/__cache/${CACHE_KEY}`);
  return {
    async match() {
      const hit = await caches.default.match(key);
      return hit ? await hit.text() : null;
    },
    async put(_k, value) {
      await caches.default.put(
        key,
        new Response(value, { headers: { 'cache-control': `max-age=${TTL_SECONDS}` } }),
      );
    },
  };
}
