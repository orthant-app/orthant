#!/usr/bin/env node
/**
 * Post-deploy verification, run against a real deployment.
 *
 * WHY THIS EXISTS. The first launch shipped two defects that every local check
 * reported as fine, and both were only visible in production:
 *
 *   1. index.ts passed an unbound `globalThis.fetch` into the deps object.
 *      workerd rejects a detached global fetch called as a method with
 *      "Illegal invocation", handleDownload catches every fetch failure, and
 *      /download quietly served the releases listing instead of the DMG.
 *      `wrangler dev` does not enforce that binding, so the workerd smoke test
 *      resolved the DMG happily.
 *
 *   2. Asset routing runs BEFORE the Worker, and `not_found_handling:
 *      404-page` answers a NAVIGATION request for an asset-less path with the
 *      404 page without invoking the Worker at all. /download served "That
 *      page isn't here." to every visitor who clicked the button, while every
 *      `curl` check passed, because curl sends `Accept: *​/*` and falls through
 *      to the Worker. `wrangler dev` does not reproduce that precedence
 *      either.
 *
 * The common shape: a local runtime more permissive than the edge, plus checks
 * whose default request is not the request a visitor makes. Neither is fixable
 * by adding assertions locally, so this runs against the deployed origin and
 * asks the questions in the shape a browser asks them.
 *
 *   npm run verify:live                 # https://orthant.app
 *   npm run verify:live -- https://...  # any other origin
 */

const BASE = (process.argv[2] || 'https://orthant.app').replace(/\/$/, '');

/** The header set that distinguishes a navigation from a bare fetch. Getting
 *  this wrong is defect 2 above, so it is not optional anywhere below. */
const NAV = {
  accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'sec-fetch-mode': 'navigate',
  'sec-fetch-dest': 'document',
  'user-agent': 'orthant-verify-live',
};

const PAGES = [
  '/', '/compare/', '/faq/', '/changelog/', '/privacy/', '/docs/',
  '/docs/getting-started/', '/docs/shortcuts/', '/docs/grid-overlay/',
  '/docs/custom-regions/', '/docs/multiple-displays/', '/docs/troubleshooting/',
  '/docs/settings/', '/docs/updates/', '/docs/uninstall/',
];

const failures = [];
const check = (ok, what, detail) => {
  console.log(`${ok ? '  ok  ' : '  FAIL'} ${what}${detail ? ` (${detail})` : ''}`);
  if (!ok) failures.push(`${what}: ${detail}`);
};

const get = (url, opts = {}) =>
  fetch(url, { redirect: 'manual', headers: NAV, signal: AbortSignal.timeout(20_000), ...opts });

console.log(`Verifying ${BASE}\n`);

for (const path of PAGES) {
  const res = await get(BASE + path);
  check(res.status === 200, `GET ${path}`, `status ${res.status}`);
}

// The single most important control on the site, asked the way a visitor asks.
{
  for (const path of ['/download', '/download/']) {
    const res = await get(BASE + path);
    const loc = res.headers.get('location') || '';
    check(res.status === 302, `GET ${path} redirects`, `status ${res.status}`);
    check(
      loc.endsWith('.dmg'),
      `GET ${path} resolves a DMG rather than falling back`,
      loc || 'no location',
    );
  }
}

// A real miss must still miss: run_worker_first must not swallow 404s.
{
  const res = await get(`${BASE}/definitely-not-a-page`);
  check(res.status === 404, 'GET /definitely-not-a-page still 404s', `status ${res.status}`);
}

// The policy the privacy page describes. Asserted on a live response because
// public/_headers and the Worker's own copy are two files, and only one of
// them applies to any given response.
{
  const csp = (await get(`${BASE}/`)).headers.get('content-security-policy') || '';
  check(csp.includes("script-src 'self';"), 'CSP: script-src is self only', csp.slice(0, 60));
  check(!csp.includes('cloudflareinsights'), 'CSP: no analytics beacon origin');
  check(csp.includes("frame-ancestors 'none'"), 'CSP: frame-ancestors none');
}

/*
 * ⚠️ The update feed must NOT be proxied, and this is the check that would
 * notice if it ever were.
 *
 * updates.orthant.app is GitHub Pages behind a DNS-only (grey cloud) CNAME. It
 * is compiled into every installed copy of the app as SUFeedURL and cannot be
 * changed for copies already out there; proxying it breaks GitHub's
 * certificate issuance and takes updates down for every existing user. It is
 * checked here, next to the site, precisely because the site is what shares
 * its zone.
 */
{
  const res = await fetch('https://updates.orthant.app/appcast.xml', {
    signal: AbortSignal.timeout(20_000),
  });
  check(res.ok, 'appcast reachable', `status ${res.status}`);
  check(
    (res.headers.get('server') || '').includes('GitHub'),
    'appcast served by GitHub Pages directly',
    `server: ${res.headers.get('server')}`,
  );
  check(
    !res.headers.get('cf-ray'),
    'appcast is NOT behind the Cloudflare proxy (must stay grey cloud)',
    `cf-ray: ${res.headers.get('cf-ray')}`,
  );
}

console.log();
if (failures.length) {
  console.error(`verify-live: ${failures.length} failure(s) against ${BASE}`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`verify-live: clean against ${BASE}`);
