#!/usr/bin/env node
// Boots the real Worker under `wrangler dev` (real workerd, not a mock) and
// exercises /download and /download/ over real HTTP.
//
// This exists because neither of the two checks that already covered
// worker/index.ts can catch a workerd-only boot failure:
//   - `npm test` imports index.ts through vitest's own module resolution,
//     which has no workerd in it at all.
//   - `wrangler deploy --dry-run` only bundles the Worker; it never boots
//     the runtime, so it is silent about a boot-time failure too.
// Concretely: workerd treats every named export of the entry module (`main`
// in wrangler.jsonc) as a candidate entrypoint, so a plain constant export
// (rather than a function, a class, or an ExportedHandler) fails the
// runtime's own boot before a single request is served — see the comment on
// worker/index.ts's default export. Only actually starting `wrangler dev`
// and making a real request exercises that failure mode, which is what this
// script does.
//
// Usage:   node worker/smoke-test.mjs
// Precondition: dist/ must exist (`npm run build`) — wrangler dev serves
// static assets from there, and without it fails for an unrelated reason.

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE_DIR = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const PORT = Number(process.env.SMOKE_PORT ?? 18787);
const HOST = '127.0.0.1';
const BASE = `http://${HOST}:${PORT}`;
const READY_TIMEOUT_MS = 20_000;
const READY_POLL_MS = 250;
const KILL_GRACE_MS = 5_000;
// The exact phrase workerd's own fatal-boot log line carries (verified
// against wrangler 4.127.1 by reproducing the original defect — see the
// task-6C report). Watched for so a boot crash fails fast, rather than only
// via the READY_TIMEOUT_MS fallback below.
const FATAL_MARKER = 'The Workers runtime failed to start';
// Both a resolved-feed redirect and the hardcoded fallback point here (see
// worker/download.ts's FALLBACK_URL and appcast.ts's REPO_PREFIX), so this
// prefix is a real assertion about "did the route actually run its logic
// and produce a genuine target" regardless of whether the live appcast
// fetch itself succeeds in this environment.
const EXPECTED_LOCATION_PREFIX = 'https://github.com/orthant-app/orthant/';

// ⚠️ The prefix alone accepts the FALLBACK, so a /download that never once
// resolved a real asset passed this test while printing the evidence.
//
// So when the feed is reachable FROM HERE, the Worker has no excuse for
// falling back, and landing on this URL is a failure rather than a pass. When
// it is not reachable, the strict check is skipped OUT LOUD. A check that
// cannot tell "the feed is down" from "resolution is broken" reports the
// second as the first.
//
// ⚠️ What this still CANNOT catch, measured rather than assumed: `wrangler
// dev` runs a local workerd that does NOT enforce the `this` binding on the
// global fetch. Deleting the .bind(globalThis) in download.ts's runtimeDeps()
// leaves this test resolving the DMG and exiting 0; the same code on the real
// edge throws "Illegal invocation" on every request. That is exactly the
// defect this strict check was written for, and it is out of its reach.
// The guard for it is the unit test in index.test.ts, which models the rule
// directly. Only `wrangler dev --remote` or a deployment reproduces it here.
const FALLBACK_LOCATION = 'https://github.com/orthant-app/orthant/releases/latest';
const FEED_URL = 'https://updates.orthant.app/appcast.xml';

async function feedIsReachable() {
  try {
    const res = await fetch(FEED_URL, { signal: AbortSignal.timeout(10_000) });
    return res.ok;
  } catch {
    return false;
  }
}

if (!existsSync(path.join(SITE_DIR, 'dist', '_headers'))) {
  console.error('worker/smoke-test.mjs: dist/ is missing or incomplete — run `npm run build` first.');
  process.exit(1);
}

const wranglerBin = path.join(SITE_DIR, 'node_modules', '.bin', 'wrangler');

let output = '';
let fatalDetected = null;
let exited = false;
let exitCode = null;
let exitSignal = null;

console.log(`Starting wrangler dev on ${BASE} ...`);
const child = spawn(wranglerBin, ['dev', '--port', String(PORT), '--ip', HOST], {
  cwd: SITE_DIR,
  stdio: ['ignore', 'pipe', 'pipe'],
});

for (const stream of [child.stdout, child.stderr]) {
  stream.on('data', (chunk) => {
    const text = chunk.toString();
    output += text;
    process.stdout.write(text); // mirror live into the CI log for diagnosis
    if (!fatalDetected && text.includes(FATAL_MARKER)) fatalDetected = text.trim();
  });
}

child.on('exit', (code, signal) => {
  exited = true;
  exitCode = code;
  exitSignal = signal;
});

async function waitForReady() {
  const deadline = Date.now() + READY_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (fatalDetected) {
      throw new Error(`wrangler dev reported a fatal boot error:\n${fatalDetected}`);
    }
    if (exited) {
      throw new Error(
        `wrangler dev exited early (code=${exitCode}, signal=${exitSignal}) before its port opened.\nCaptured output:\n${output}`,
      );
    }
    try {
      await fetch(BASE + '/');
      return; // any HTTP response at all means the local server is listening
    } catch {
      // connection refused / not listening yet — keep polling
    }
    await new Promise((resolve) => setTimeout(resolve, READY_POLL_MS));
  }
  throw new Error(`wrangler dev did not become ready within ${READY_TIMEOUT_MS}ms.\nCaptured output:\n${output}`);
}

async function checkDownloadPath(pathname, strict) {
  const res = await fetch(BASE + pathname, { redirect: 'manual' });
  if (res.status !== 302) {
    throw new Error(`GET ${pathname}: expected 302, got ${res.status}`);
  }
  const location = res.headers.get('location');
  if (!location || !location.startsWith(EXPECTED_LOCATION_PREFIX)) {
    throw new Error(
      `GET ${pathname}: expected a location starting with ${EXPECTED_LOCATION_PREFIX}, got ${JSON.stringify(location)}`,
    );
  }
  if (strict && location === FALLBACK_LOCATION) {
    throw new Error(
      `GET ${pathname}: the appcast is reachable from this machine, so the Worker had no reason to fall back. ` +
        `It redirected to ${location} instead of a release asset, which means the feed fetch failed INSIDE the Worker.`,
    );
  }
  console.log(`  ✓ GET ${pathname} -> 302 ${location}`);
}

function killChild() {
  return new Promise((resolve) => {
    if (exited) return resolve();
    const forceKill = setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch {
        // already gone
      }
    }, KILL_GRACE_MS);
    child.once('exit', () => {
      clearTimeout(forceKill);
      resolve();
    });
    try {
      child.kill('SIGTERM');
    } catch {
      clearTimeout(forceKill);
      resolve();
    }
  });
}

let failureMessage = null;
try {
  await waitForReady();
  console.log('wrangler dev is ready. Checking routes...');
  const strict = await feedIsReachable();
  if (strict) {
    console.log('  the appcast is reachable from here, so a fallback redirect is a FAILURE');
  } else {
    console.log('  ⚠️  the appcast is NOT reachable from here; skipping the strict resolution check');
  }
  await checkDownloadPath('/download', strict);
  await checkDownloadPath('/download/', strict);
} catch (err) {
  failureMessage = err?.message ?? String(err);
} finally {
  await killChild();
}

if (failureMessage) {
  console.error(`\n✗ smoke test FAILED: ${failureMessage}`);
  process.exit(1);
}

console.log(
  '\n✓ smoke test passed: the entry module boots under a real workerd runtime and /download + /download/ both redirect.',
);
process.exit(0);
