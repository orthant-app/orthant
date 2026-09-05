import { handleDownload, runtimeDeps, SECURITY_HEADERS } from './download';

// This is the Worker's entry module (`main` in wrangler.jsonc). workerd
// treats every NAMED export of the entry module as a candidate entrypoint,
// so each one must be a function, a class, or an ExportedHandler — a plain
// constant fails the runtime's own boot with "Incorrect type for map entry
// '<name>': the provided value is not of type 'function or ExportedHandler'"
// before a single request is served. That failure is invisible to both
// `npm test` (vitest imports this module directly with no workerd involved)
// and `wrangler deploy --dry-run` (which bundles but never boots the
// runtime) — see worker/smoke-test.mjs, which does boot it. Keep this
// module's exports to `default` alone; anything else (constants, helper
// functions, types) belongs in a sibling module like ./download, which is
// never the entry point and so has no such restriction.
export default {
  async fetch(request: Request, env: { ASSETS: { fetch: typeof fetch } }): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/download' || url.pathname === '/download/') {
      return handleDownload(runtimeDeps());
    }
    return withSecurityHeaders(await env.ASSETS.fetch(request));
  },
};

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
