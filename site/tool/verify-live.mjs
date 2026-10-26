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
const TRANSIENT = new Set([408, 429, 500, 502, 503, 504]);

/**
 * A Cloudflare bot challenge, which is not a fact about the site.
 *
 * Measured from a GitHub runner: `/` intermittently answers 403 with
 * `cf-mitigated: challenge` and Cloudflare's "Just a moment..." interstitial,
 * because Bot Fight Mode challenges automated clients from datacenter IPs. It
 * is probabilistic, hits the same edge that serves 200 a second later, and no
 * real visitor sees it.
 *
 * ⚠️ A bare 403 is deliberately NOT retried. Retrying every 403 would also
 * swallow a genuine one (a WAF rule, a broken route, a misconfigured origin),
 * which is precisely the "retry until green" habit that turns a check into
 * decoration. Only a 403 that Cloudflare itself labels a challenge is waited
 * out; anything else fails on the first response.
 */
const isChallenge = (res) => res.status === 403 && res.headers.has('cf-mitigated');

async function getPage(url) {
  let res;
  for (let attempt = 1; attempt <= 3; attempt++) {
    res = await get(url);
    if (!TRANSIENT.has(res.status) && !isChallenge(res)) {
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
// NAV's User-Agent names no platform, so /download answers it as a Mac.
//
// /download chooses by platform and is cacheable, so it must say it varies by
// the headers it reads, or a shared cache could hand one platform's download
// to the other. A named platform's route does not vary.
const VARY = 'User-Agent, Sec-CH-UA-Platform';
{
  for (const path of ['/download', '/download/', '/download/macos']) {
    const res = await get(BASE + path);
    const loc = res.headers.get('location') || '';
    check(res.status === 302, `GET ${path} redirects`, `status ${res.status}`);
    check(
      loc.endsWith('.dmg'),
      `GET ${path} resolves a DMG rather than falling back`,
      loc || 'no location',
    );
    const vary = res.headers.get('vary');
    if (path === '/download/macos') {
      check(vary === null, `GET ${path} does not vary`, `vary: ${vary}`);
    } else {
      check(vary === VARY, `GET ${path} varies by the visitor's platform`, `vary: ${vary}`);
    }
  }
}

/*
 * Windows. Its feed is a 404 until the first Windows stable is published, and
 * until then /download/windows falls back to the releases page and a Windows
 * visitor at /download is offered the DMG, as before. Once the feed exists,
 * both must resolve the installer, and the feed must be served exactly as the
 * macOS one is (it is compiled into every Windows copy the same way).
 *
 * Whether Windows has shipped is asked of the release, not of the feed being
 * checked: every stable since the first Windows one carries its installer
 * beside its DMG, so a Windows feed that went missing after then fails here
 * rather than passing as "not yet".
 */
{
  const mac = await fetch('https://updates.orthant.app/appcast.xml', { signal: AbortSignal.timeout(20_000) });
  const xml = mac.ok ? await mac.text() : '';
  let newest = null;
  for (const item of xml.match(/<item>[\s\S]*?<\/item>/g) ?? []) {
    const build = /<sparkle:version>(\d+)<\/sparkle:version>/.exec(item);
    const dmg = /<enclosure[^>]*\burl="([^"]+\.dmg)"/.exec(item);
    if (build && dmg && (newest === null || Number(build[1]) > newest.build)) newest = { build: Number(build[1]), dmg: dmg[1] };
  }
  const installer = newest ? newest.dmg.replace(/\.dmg$/, '-setup.exe') : '';
  const asset = installer
    ? await fetch(installer, { method: 'HEAD', redirect: 'manual', signal: AbortSignal.timeout(20_000) })
    : null;
  check(
    asset !== null && (asset.status === 302 || asset.status === 404),
    'the latest stable says whether it carries a Windows installer',
    asset ? `${installer}: status ${asset.status}` : 'no DMG in appcast.xml',
  );
  const published = asset?.status === 302;
  const feed = await fetch('https://updates.orthant.app/appcast-win.xml', {
    signal: AbortSignal.timeout(20_000),
  });
  console.log(`  note  appcast-win.xml: status ${feed.status}${published ? '' : ' (no Windows stable yet)'}`);
  if (published) {
    check(feed.ok, 'Windows appcast reachable once Windows has shipped', `status ${feed.status}`);
    check(
      (feed.headers.get('server') || '').includes('GitHub'),
      'Windows appcast served by GitHub Pages directly',
      `server: ${feed.headers.get('server')}`,
    );
    check(!feed.headers.get('cf-ray'), 'Windows appcast is NOT behind the Cloudflare proxy', `cf-ray: ${feed.headers.get('cf-ray')}`);
  } else {
    check(feed.status === 404, 'Windows appcast is absent, not failing', `status ${feed.status}`);
  }
  const windowsVisitor = { ...NAV, 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) orthant-verify-live' };
  const named = await get(`${BASE}/download/windows`);
  const auto = await get(`${BASE}/download`, { headers: windowsVisitor });
  const namedLoc = named.headers.get('location') || '';
  const autoLoc = auto.headers.get('location') || '';
  check(named.status === 302 && auto.status === 302, 'the Windows downloads redirect', `status ${named.status}, ${auto.status}`);
  check(auto.headers.get('vary') === VARY, 'GET /download varies for a Windows visitor too', `vary: ${auto.headers.get('vary')}`);
  check(named.headers.get('vary') === null, 'GET /download/windows does not vary', `vary: ${named.headers.get('vary')}`);
  if (published) {
    check(namedLoc.endsWith('-setup.exe'), 'GET /download/windows resolves the installer', namedLoc || 'no location');
    check(autoLoc.endsWith('-setup.exe'), 'GET /download offers a Windows visitor the installer', autoLoc || 'no location');
  } else {
    check(namedLoc === 'https://github.com/orthant-app/orthant/releases/latest',
      'GET /download/windows falls back while there is no Windows stable', namedLoc || 'no location');
    check(autoLoc.endsWith('.dmg'), 'GET /download offers a Windows visitor the DMG, as before', autoLoc || 'no location');
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
  check(csp.includes("script-src 'self' https://static.cloudflareinsights.com;"),
    'CSP: script-src is self plus the analytics beacon', csp.slice(0, 90));
  check(csp.includes("connect-src 'self' https://cloudflareinsights.com;"),
    'CSP: connect-src admits the beacon endpoint', csp.slice(0, 200));
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
