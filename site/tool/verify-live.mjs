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

/**
 * Retry a status that can be transient, and describe one that is not.
 *
 * "status 403" on its own is not a finding, it is a mystery: a Cloudflare bot
 * mitigation, a WAF rule and a genuinely broken origin all look identical from
 * the exit code. Any check that can fail against a CDN has to report cf-ray
 * and cf-mitigated, or the next person is left rerunning it and guessing.
 *
 * The retry is bounded and only covers statuses that are actually transient,
 * so a persistent block still fails the deploy rather than being waited out.
 */
const TRANSIENT = new Set([403, 408, 429, 500, 502, 503, 504]);

async function getPage(url) {
  let res;
  for (let attempt = 1; attempt <= 3; attempt++) {
    res = await get(url);
    if (!TRANSIENT.has(res.status)) {
      // ⚠️ A silent retry is a check that lies about how healthy its subject
      // is: "green" and "green only on the third try" are different facts, and
      // the second one is the interesting one. Say so.
      if (attempt > 1) {
        console.log(`  note  ${url} needed ${attempt} attempts (earlier: ${res.status})`);
      }
      return res;
    }
    // Full diagnostics on the FAILED attempt, not just the final one. Whether
    // a 403 is a bot mitigation aimed at datacenter IPs (harness noise, no
    // real visitor affected) or a bad response cached at one edge (a live
    // outage for everyone routed there) is the whole question, and only
    // cf-mitigated, cf-cache-status and the body can answer it.
    console.log(`  retry ${url} -> ${await describe(res)}`);
    if (attempt < 3) await new Promise((r) => setTimeout(r, 2000 * attempt));
  }
  return res;
}

async function describe(res) {
  const bits = [`status ${res.status}`];
  for (const h of ['cf-ray', 'cf-mitigated', 'server', 'cf-cache-status']) {
    const v = res.headers.get(h);
    if (v) bits.push(`${h}: ${v}`);
  }
  if (!res.ok) {
    const body = await res.clone().text().catch(() => '');
    const snippet = body.replace(/\s+/g, ' ').trim().slice(0, 140);
    if (snippet) bits.push(`body: ${snippet}`);
  }
  return bits.join(' | ');
}

console.log(`Verifying ${BASE}\n`);

for (const path of PAGES) {
  const res = await getPage(BASE + path);
  check(res.status === 200, `GET ${path}`, await describe(res));
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
