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
 *  Applied to every Worker-generated response AND re-attached to every
 *  ASSETS fallthrough response below, including the 404 page. Cloudflare
 *  does NOT apply public/_headers to a response a Worker returns, even one
 *  obtained by calling env.ASSETS.fetch() and passing it straight through —
 *  so without this, every non-asset path (which is everything except a
 *  handful of static files, once a Worker route exists at all) would ship
 *  with no CSP. Pages reached without going through a Worker fetch handler
 *  at all still get the same set directly from public/_headers. */
const SECURITY_HEADERS: Record<string, string> = {
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

/** Re-emits a response with SECURITY_HEADERS attached, rather than mutating
 *  it in place — a Response's headers are not guaranteed mutable once
 *  constructed, and env.ASSETS.fetch() results are exactly that case. */
function withSecurityHeaders(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(name, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export async function handleDownload(deps: Deps): Promise<Response> {
  const cached = await deps.cache.match(CACHE_KEY).catch(() => null);
  if (cached) return redirect(cached, `public, max-age=${TTL_SECONDS}`);

  let xml: string;
  try {
    const res = await deps.fetch(FEED_URL);
    if (!res.ok) return redirect(FALLBACK_URL, 'no-store');
    xml = await res.text();
  } catch {
    return redirect(FALLBACK_URL, 'no-store');
  }

  const target = resolveDownloadUrl(xml);
  // A failure is never cached: a transient bad feed must not pin the download
  // button to the fallback for the whole TTL.
  if (target === null) return redirect(FALLBACK_URL, 'no-store');

  await deps.cache.put(CACHE_KEY, target).catch(() => {});
  return redirect(target, `public, max-age=${TTL_SECONDS}`);
}

/** Adapts Workers' Cache API — which stores Responses, not strings — to CacheLike. */
function runtimeCache(): CacheLike {
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

export default {
  async fetch(request: Request, env: { ASSETS: { fetch: typeof fetch } }): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/download' || url.pathname === '/download/') {
      return handleDownload({ fetch: globalThis.fetch, cache: runtimeCache() });
    }
    return withSecurityHeaders(await env.ASSETS.fetch(request));
  },
};
