# Releasing Orthant

The whole release is driven by pushing a `v*` tag, and one tag ships both platforms: the
macOS DMG and the Windows installer, from the same commit, under one approval. This is the
checklist, in order, with what each step is protecting against.

Publication is **irreversible**: releases are immutable, and a published build number
can never be lowered. Everything before the tag push is cheap to fix; nothing after it
is. So the preflight is not ceremony.

## The one-line summary

Write the changelog entry and bump `pubspec.yaml` in **one** commit → push `main` →
push the tag → approve the `release` environment → verify → flip `published: true` in a
**separate** commit.

Two commits, and they are deliberately not one. See step 7.

---

## Before you start (once per machine)

Two gitignored files hold the signing identity, so it never enters the repo:

- `macos/Runner/Configs/Local.xcconfig`: `DEVELOPMENT_TEAM` for the Release config.
- `tool/release.local`: `EXPECTED_TEAM`, which `tool/release.sh` checks against the
  identity it actually signs with.

The release tooling exits with instructions if either is missing. You also need the
Developer ID in the login keychain and a notarization profile.

Windows needs no signing identity on your machine: it is built and signed in CI only.
One check, the winget manifest's (step 4), runs on any Windows.

## Before the first Windows release (once per repository)

The Windows job signs with Azure Artifact Signing, signed in to Azure with OpenID Connect,
so no signing key is stored anywhere. In the `release` environment, beside the macOS
secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` (the app
registration, which holds the "Artifact Signing Certificate Profile Signer" role and
whose federated credential trusts
`repo:orthant-app@308256916/orthant@1350370232:environment:release`, the subject this
repository presents because its OIDC subject is immutable and names owner and repository
by numeric ID, so a credential written with the names never matches), and
`ARTIFACT_SIGNING_ENDPOINT`, `ARTIFACT_SIGNING_ACCOUNT` and `ARTIFACT_SIGNING_PROFILE`.
The Windows job fails before it builds if any is empty.

winget: a `winget` environment, limited to `v*` tags, holding `WINGET_TOKEN`, a classic
token with `public_repo` from the account whose fork of `microsoft/winget-pkgs` opens the
pull requests. Microsoft's CLA is signed once, on the first pull request.

**Run releases on an unlocked machine.** A locked screen seals the login keychain, and
`notarytool` reports that as "No Keychain password item found", which reads like a
missing credential rather than a locked one.

## 1. Choose the version and the build number

`pubspec.yaml` carries both: `version: X.Y.Z+N`.

- `X.Y.Z` is the marketing version. It must be **three integers**. A pre-release label
  like `-beta.2` lives only in the tag, the DMG filename and the release title.
- **`N` is the only thing Sparkle compares**, and it must increase across betas *and*
  stables, in one sequence. A stable numbered below a published beta reads as older, and
  its users are never offered it.

`N` must be greater than every `<sparkle:version>` in **all four** live feeds
(`appcast.xml`, `appcast-beta.xml`, `appcast-win.xml` and `appcast-win-beta.xml`): the
two platforms share one counter. `max_feed_version` in `tool/ci/release_lib.sh` enforces
this, but check it locally first: a rejection after the tag is pushed is far more
annoying than one before.

## 2. Write the changelog entry, a hard precondition

Create `site/src/content/changelog/<X.Y.Z>.md`:

```markdown
---
version: 1.0.2
build: 6
channel: stable
published: false
date: 2026-09-05
---

- What changed, in the user's terms.
- One bullet per user-visible change.
```

Rules the tooling enforces, so getting these wrong fails the release rather than
shipping something wrong:

- **Named by BASE version, never by tag.** A beta and its eventual stable share one
  entry: `1.0.2-beta.1` and `1.0.2` both resolve to `1.0.2.md`. A per-tag filename
  cannot satisfy both this and the Dart guard below.
- **`version:` must equal the pubspec marketing version.** `test/site_docs_test.dart`
  asserts exactly one entry matches, and that version never carries a `-beta.N` label.
- **The body must not be blank.** `metadata()` aborts the tag push if the file is
  missing or has no body, *before* build, sign and notarize rather than after.
- **`published: false` at this stage.** See step 7.

**This file is the single source for the release notes.** `publish()` passes it to
`gh release create --notes-file` with the frontmatter stripped. There is no
`--generate-notes`, deliberately: one artifact with two authors is one artifact that
can disagree with itself.

## 3. Commit the bump and the entry together

The version bump and its changelog entry go in **one commit**. A version-bump commit
builds the site, and an entry that arrived later would mean a build that advertises a
version `/download` cannot serve yet.

```sh
git add pubspec.yaml site/src/content/changelog/X.Y.Z.md
git commit -m "release: prepare X.Y.Z"
git push origin main
```

CI runs. The site deploys automatically (see step 8), but because the entry is
`published: false` it does not yet advertise the new version.

## 4. For a stable release: render the cask and the winget manifest first

`bump-cask` runs **after** the release is immutable, and the workflow does **not** run
`brew style`, so a non-conforming cask ships silently rather than failing the job.
Homebrew refuses to lint a cask outside a tap:

```sh
brew tap orthant-app/tap
# drop the rendered cask into the tap's Casks/ then:
brew style --cask orthant
```

`bump-winget` is the same for Windows, and Microsoft's own validation reads its manifest
after the release is immutable. Render it and validate it on Windows first (any 64 hex
digits stand in for the installer's SHA-256, which does not exist yet):

```sh
python3 tool/ci/winget_manifest.py --version X.Y.Z --sha256 <64 hex digits> \
  --date YYYY-MM-DD --out build/winget/X.Y.Z
# on Windows:
winget validate --manifest build\winget\X.Y.Z
```

Skip for pre-releases; `bump-cask` and `bump-winget` are stable-only.

## 5. Preflight, then tag

Check locally, because publishing cannot be undone:

- tag base version == pubspec marketing version;
- build number greater than all four live feeds;
- the tag commit is an ancestor of `origin/main`;
- `site/src/content/changelog/<base>.md` exists with a body;
- the Windows secrets are set (above), or the Windows job, and with it the release, fails.

```sh
git tag -a vX.Y.Z -m "vX.Y.Z"        # or vX.Y.Z-beta.N
git push origin vX.Y.Z
```

## 6. Approve, then verify the release

The `release` environment requires an individual approval before any job can read a
secret. That approval is the reason keeping signing keys in CI was judged acceptable. It lives under
Actions ▸ the running workflow ▸ Review deployments. The Windows job and the macOS job wait
for it together, and one approval admits both; the macOS job then waits for the Windows
installer, which it signs for updates.

When it finishes, verify:

- the DMG downloads and mounts;
- `spctl -a -vv` on the mounted app reports `source=Notarized Developer ID`;
- the appcast lists the new `<sparkle:version>`;
- for a second-or-later stable, the feed carries a `.delta` and it is signed;
- the installer, `Orthant-<version>-setup.exe`, downloads, and on Windows
  `Get-AuthenticodeSignature` reports it `Valid` with a `TimeStamperCertificate`;
- `appcast-win.xml` (or `appcast-win-beta.xml`) lists the new `<sparkle:version>` with an
  `edSignature`;
- for a stable, `bump-winget` opened a pull request to `microsoft/winget-pkgs`. Microsoft
  validates and merges it, hours to days later; it is not part of this verification.

**If a job fails after publication, use "Re-run failed jobs", never "Re-run all".** The
first job deliberately rejects a tag whose release is already public rather than
rebuild different signed bytes.

**If a job fails before publication, use "Re-run all jobs".** The macOS job waits for the
installer the Windows job uploads in the same attempt, so re-running only a failed macOS
job waits for an upload that never comes, and fails. Re-running all asks for the one
approval again. A failed Windows job leaves its diagnostics in its artifact,
`orthant-windows-<run>-<attempt>`, kept for one day: download it from the run's summary and
decrypt it with the release key:

```sh
openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -md sha256 \
  -pass env:DRYRUN_ARTIFACT_KEY -in windows.tar.enc -out windows.tar
```

## 7. Flip `published: true` in a separate commit

Once the release is verified live:

```sh
# edit site/src/content/changelog/<X.Y.Z>.md: published: false -> true
git commit -am "release: publish X.Y.Z"
git push origin main
```

**This is the step that updates the website**, and it is separate on purpose. The
homepage's advertised version and the `/changelog/` page are baked at build time from
this collection, and `currentVersion()` picks the newest **published stable**. Deploying
before the release is verified would advertise a version that `/download` cannot serve.

Keeping the flip manual is deliberate: it is the human gate in front of an irreversible
publish. Automating it would remove the check for the sake of one commit.

## 8. Confirm the site actually updated

Pushing step 7 triggers `.github/workflows/deploy-site.yml` (push to `main` touching
`site/**`), which builds, typechecks, tests, sweeps, deploys to Cloudflare and then
verifies the live origin. Check it went green, or run the verification yourself:

```sh
cd site && npm run verify:live
```

That asserts the pages serve, `/download` **resolves a DMG rather than falling back**,
`/download/windows` resolves the installer once a Windows stable exists,
a real miss still 404s, the CSP is as declared, and the appcast is still served by
GitHub Pages with no `cf-ray`.

⚠️ **`/download` does not go stale and that is exactly why a stale site is easy to
miss.** It resolves the appcast live on a 5 minute TTL, so downloads keep working while
the homepage shows the previous version. Do not use "the download works" as evidence
that the site is up to date.

---

## Things that have actually gone wrong

- **A locked screen** seals the keychain; `notarytool` calls it a missing password item.
- **`flutter build macos --release` alone yields an un-notarizable app.** Xcode injects
  `com.apple.security.get-task-allow` into Release, and Apple rejects notarization
  outright when it is present. `tool/release.sh` strips it by re-signing with explicit
  entitlements, which makes that re-sign load-bearing rather than belt-and-braces.
- **`generate_appcast` hides two failures behind exit 0.** It hard-fails on a
  coexisting same-version `.zip` and `.dmg`, and can exit 0 having silently skipped
  signing. `tool/release.sh` counts signed items instead of trusting the exit code, and
  counts the full-DMG and delta regions separately, because a delta legitimately adds a
  signature of its own.
- **A date-based build number was tried and reverted.** A valid-but-wrong date like
  `2027…` publishes happily and then blocks every release until that date arrives.
- **Release notes are editable after publication; assets are not.** Immutability locks
  the tag and the assets. If a body is wrong, `gh release edit --notes-file` still works.

## What is immutable, and what that costs

The Accessibility grant keys on **bundle id + Team ID**. Both are locked:
`app.orthant.orthant`, signed with the project's Developer ID. Changing either after
publication revokes every existing user's grant, with no migration path.

`SUFeedURL` is compiled into every build and cannot change for copies already
installed. It points at a domain the project owns so hosting can move without orphaning
a client. `updates.orthant.app` must stay **DNS-only (grey cloud)**: proxying it breaks
GitHub's certificate issuance. `npm run verify:live` checks this on every deploy.

On Windows the feed is compiled in the same way (`appcast-win.xml`, or
`appcast-win-beta.xml` in a beta), and so is the installer's `AppId`, by which Windows and
winget know an installed copy; a new one would install a second Orthant beside the first.
The winget identifier, `Orthant.Orthant`, is permanent once Microsoft merges it. The
Authenticode signer is the one thing that can change without breaking an installed copy:
nothing on Windows is keyed to it, though SmartScreen's reputation starts again.
