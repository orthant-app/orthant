#!/usr/bin/env bash
#
# Build, sign, notarize and package Orthant for distribution.
#
#   tool/release.sh 1.0.1              # the whole pipeline
#   tool/release.sh 1.0.1 --sign-only  # stop after signing (M8 Task 1's gate)
#
# WHY THIS IS NOT A MODE ON tool/dev_signing.sh
#   That script is load-bearing for the entire acceptance suite, and it omits
#   --options runtime *on purpose*: the hardened runtime turns on library
#   validation, which requires every loaded library to share the main binary's
#   Team ID. A self-signed certificate has no Team ID, so a dev build signed
#   that way dies at launch with "different Team IDs" (see the comment at
#   tool/dev_signing.sh:161). Release needs exactly the opposite, because
#   notarization *requires* --options runtime. Two paths, two scripts.
#
# WHAT IT ASSUMES
#   - A "Developer ID Application" certificate in the login keychain.
#   - App Sandbox stays off in macos/Runner/Release.entitlements. The AX API
#     does not work sandboxed, which rules out the Mac App Store permanently
#     and makes Developer ID + notarization the only distribution path.
#   - Bundle id and Team ID never change. The TCC (Accessibility) grant keys on
#     the designated requirement, which is derived from both; moving either
#     silently costs every user their grant on the next update.
#
# CI-shaped: no interactive prompts, every input available as an environment
# variable, so a workflow can call it later without a rewrite.
#
set -euo pipefail
# shellcheck source=tool/ci/release_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ci/release_lib.sh"

VERSION="${1:?usage: tool/release.sh <version> [--sign-only]}"
MODE="${2:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/build/macos/Build/Products/Release/Orthant.app"
DIST="$REPO_ROOT/build/dist"
DMG="$DIST/Orthant-$VERSION.dmg"
ZIP="$DIST/Orthant-$VERSION.zip"

: "${SIGN_IDENTITY:=Developer ID Application}"
: "${NOTARY_PROFILE:=orthant}"

info() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

redacting_output() {
  [[ "${REDACT_IDENTITY_OUTPUT-}" == 1 ]]
}

record_sensitive_output() {
  local label="$1" text="$2"
  write_sensitive_diagnostic "$label" "$text" ||
    die "could not record redacted release diagnostics"
}

sensitive_info() {
  local label="$1" public_text="$2" detailed_text="$3"
  if redacting_output; then
    record_sensitive_output "$label" "$detailed_text"
    info "$public_text"
  else
    info "$detailed_text"
  fi
}

sensitive_ok() {
  local label="$1" public_text="$2" detailed_text="$3"
  if redacting_output; then
    record_sensitive_output "$label" "$detailed_text"
    ok "$public_text"
  else
    ok "$detailed_text"
  fi
}

sensitive_die() {
  local label="$1" public_text="$2" detailed_text="$3"
  if redacting_output; then
    record_sensitive_output "$label" "$detailed_text"
    die "$public_text — see release-diagnostics.log in the encrypted diagnostics archive"
  fi
  die "$detailed_text"
}

run_redacted_check() {
  local label="$1" error_file output rc
  shift
  if ! redacting_output; then
    "$@"
    return
  fi

  [[ -n "${RUNNER_TEMP-}" ]] ||
    release_lib_error 'RUNNER_TEMP is required for redacted diagnostics' || return 1
  mkdir -p "$RUNNER_TEMP" || return 1
  error_file="$RUNNER_TEMP/release-check.$$.log"
  : >"$error_file" || return 1
  chmod 600 "$error_file" || return 1
  if "$@" 2>"$error_file"; then
    rc=0
  else
    rc=$?
  fi
  output="$(<"$error_file")"
  rm -f "$error_file"
  [[ -z "$output" ]] || record_sensitive_output "$label" "$output"
  return "$rc"
}

run_codesign() {
  local label="$1" output rc
  shift
  if ! redacting_output; then
    codesign "$@"
    return
  fi

  if output="$(codesign "$@" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  record_sensitive_output "$label" "$output"
  if (( rc == 0 )); then
    ok "$label"
  else
    warn "$label failed — see release-diagnostics.log in the encrypted diagnostics archive"
  fi
  return "$rc"
}

capture_codesign() {
  local label="$1" rc
  shift
  if CODESIGN_CAPTURE="$(codesign "$@" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  if redacting_output; then
    record_sensitive_output "$label" "$CODESIGN_CAPTURE"
    if (( rc == 0 )); then
      ok "$label"
    else
      warn "$label failed — see release-diagnostics.log in the encrypted diagnostics archive"
    fi
  fi
  return "$rc"
}

cd "$REPO_ROOT"

# ---------------------------------------------------------------- preflight --

run_redacted_check 'release version validation' validate_release_version "$VERSION"

# The expected team is read from a gitignored per-machine file, and the bundle
# id stays a plain assignment — deliberately not `: "${VAR:=default}"` like
# SIGN_IDENTITY/NOTARY_PROFILE above. Those pick a KIND of identity/profile,
# and any value the caller supplies is fine. These two pin the WHICH: Team ID
# and bundle id are the two halves of the designated requirement the TCC
# Accessibility grant keys on (see the file header), and SIGN_IDENTITY's own
# default is a substring match that any "Developer ID Application" certificate
# satisfies — from ANY team. Honouring the environment would reopen exactly
# that hole one step further out: a wrong-team build would still pass, just by
# exporting a variable instead of by having two certificates in the keychain.
# A file the machine's owner writes once keeps that pin without committing an
# Apple identity to a public tree — and sourcing it after this point means the
# environment cannot override it either.
RELEASE_LOCAL="$REPO_ROOT/tool/release.local"
[[ -f "$RELEASE_LOCAL" ]] ||
  sensitive_die 'local release configuration path' \
    'local release signing configuration is missing' \
    "$RELEASE_LOCAL not found — create it (gitignored) containing: EXPECTED_TEAM=<your Apple Team ID>"
# shellcheck source=/dev/null
source "$RELEASE_LOCAL"
[[ -n "${EXPECTED_TEAM:-}" ]] ||
  sensitive_die 'local release configuration path' \
    'local release signing configuration is incomplete' \
    "$RELEASE_LOCAL must set EXPECTED_TEAM=<your Apple Team ID>"
EXPECTED_BUNDLE_ID="app.orthant.orthant"

# pubspec.yaml is the source of truth for what gets built. Release labels may
# carry a prerelease suffix for artifact naming, while Flutter's marketing
# version remains the three-integer base version.
PUBSPEC_FILE="$REPO_ROOT/pubspec.yaml"
run_redacted_check 'pubspec version validation' parse_pubspec_version "$PUBSPEC_FILE" ||
  sensitive_die 'pubspec path' 'could not parse the release version' \
    "could not parse release version from $PUBSPEC_FILE"
[[ "$PUBSPEC_BASE_VERSION" == "$RELEASE_BASE_VERSION" ]] ||
  sensitive_die 'pubspec version mismatch' 'the requested release version does not match pubspec' \
    "$PUBSPEC_FILE says $PUBSPEC_BASE_VERSION but $VERSION has base version $RELEASE_BASE_VERSION — bump it first"

if SECURITY_OUT="$(security find-identity -v -p codesigning 2>&1)"; then
  SECURITY_RC=0
else
  SECURITY_RC=$?
fi
if (( SECURITY_RC != 0 )) || ! grep -qF "$SIGN_IDENTITY" <<<"$SECURITY_OUT"; then
  if [[ "${REDACT_IDENTITY_OUTPUT-}" == 1 ]]; then
    print_sensitive_or_record 'signing identity lookup' "$SECURITY_OUT" ||
      die "could not record signing identity lookup"
    die "no matching release signing identity in the keychain"
  fi
  die "no '$SIGN_IDENTITY' in the keychain — create one in Xcode ▸ Settings ▸ Accounts (requires an Apple Developer Program membership)"
fi

# The check above guards the marketing string (CFBundleShortVersionString);
# this one guards the BUILD number next to it (the `+N`, CFBundleVersion).
# Sparkle compares CFBundleVersion, not the marketing string, to decide
# whether an update is newer, so a release can pass the check above with a
# fresh marketing version and still never be offered if the +N didn't move.
# Parsed and checked here, before the build, so a stale +N costs a small edit
# rather than a full Release build and a signing pass.
#
# Blind spot: these feeds are local and gitignored, so a fresh clone or a
# cleaned build directory reports "first release" even when a published feed
# already holds a higher build number. The workflow restores the canonical
# feed history before calling this script.
BUILD_NUMBER="$PUBSPEC_BUILD_NUMBER"
run_redacted_check 'appcast output selection' select_appcast_output "$DIST"
FEED_HISTORY=("$DIST/appcast.xml")
if [[ "${INCLUDE_BETA_APPCAST_HISTORY-}" == 1 ]]; then
  FEED_HISTORY+=("$DIST/appcast-beta.xml")
fi
run_redacted_check 'release feed history validation' \
  max_feed_version "${FEED_HISTORY[@]}" ||
  sensitive_die 'release feed history paths' 'could not inspect release feed history' \
    "could not inspect release feed history: ${FEED_HISTORY[*]}"

if [[ -n "$FEED_MAX_VERSION" ]]; then
  (( 10#$BUILD_NUMBER > 10#$FEED_MAX_VERSION )) ||
    sensitive_die 'release feed monotonicity paths' \
      'the build number is not newer than the release feed history' \
      "$PUBSPEC_FILE's build number ($BUILD_NUMBER) is not greater than the newest version ($FEED_MAX_VERSION) in ${FEED_HISTORY[*]} — Sparkle compares CFBundleVersion, so this release would never be offered as an update; bump the +N in $PUBSPEC_FILE, UNLESS this run immediately follows one that died signing the selected appcast for this same +N — that leaves a partially-written feed behind, which is what this check is actually reading, and the fix is to remove or regenerate that file, not bump $PUBSPEC_FILE"
else
  sensitive_info 'release feed history paths' \
    'no prior release found — skipping the monotonic build-number check (first release)' \
    "no prior release found in ${FEED_HISTORY[*]} — skipping the monotonic build-number check (first release)"
fi

# ------------------------------------------------------------------- build ---

info "Building Release…"
flutter build macos --release

[[ -d "$APP" ]] ||
  sensitive_die 'release app path' 'the Release build produced no app' \
    "no app at $APP — did the build actually succeed?"

# -------------------------------------------------------------------- sign ---

# Signed **inside-out and explicitly**, never with --deep. Apple discourages
# --deep; it applies one set of entitlements to everything it touches and
# silently skips nested bundles it does not recognise. Deepest first, app last,
# or the outer signature is invalidated by the inner ones.
sign_nested() {
  run_codesign 'Nested code signing' \
    --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$1"
}

# Everything inside the bundle that is code. Deliberately NOT limited to
# Contents/Frameworks/*.{framework,dylib}: that is true of today's bundle but
# encodes where nested code happens to live. M12 adds Sparkle.framework, which
# ships two .xpc services, one nested .app bundle, and Autoupdate — a bare
# Mach-O helper tool with no extension at all, matched only by literal name.
# -depth so the deepest paths are signed first, and -mindepth 1 so the outer
# .app does not match *.app and get signed here (it is signed below, with
# entitlements).
#
# Note there is no "find the executables" shortcut available: Flutter's
# App.framework/Versions/A/App is mode 0644, so a -perm test would skip the
# entire AOT snapshot. Autoupdate is proof this cuts both ways: measured, it
# stayed adhoc-signed (TeamIdentifier=not set) straight through a full
# sign+verify pass until named explicitly here — `codesign --verify --deep
# --strict` reported "valid on disk" for it regardless, because that only
# asks whether an (ad-hoc) signature is internally consistent, not whether it
# would pass library validation against this Team ID. Only inspecting the
# Team ID on the actual file (`codesign -dv`) caught the gap.
info "Signing nested code…"
NESTED_COUNT=0
while IFS= read -r -d '' item; do
  printf '    %s\n' "${item#"$APP"/}"
  sign_nested "$item"
  NESTED_COUNT=$((NESTED_COUNT + 1))
done < <(find "$APP" -mindepth 1 -depth \
              \( -name '*.framework' -o -name '*.dylib' -o -name '*.so' \
                 -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \
                 -o -name 'Autoupdate' \) -print0)

# A count of zero means the find patterns stopped matching reality — the app
# has always had at least FlutterMacOS.framework and App.framework. Silence
# here would surface much later as a notarization rejection naming a path.
(( NESTED_COUNT > 0 )) ||
  die "signed no nested code — the find patterns no longer match the bundle"

info "Signing the app…"
run_codesign 'Release app signing' \
  --force --timestamp --options runtime \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$SIGN_IDENTITY" "$APP"

# ------------------------------------------------------------------ verify ---

info "Verifying…"
run_codesign 'Release app signature verification' \
  --verify --deep --strict --verbose=2 "$APP" ||
  die "signature does not verify"

# Not the same check: --verify asks whether the signature is internally sound,
# this asks whether Gatekeeper would accept it. Before notarization it will not,
# and that is expected rather than a failure.
SPCTL_OUT="$(spctl -a -vvv -t exec "$APP" 2>&1 || true)"
print_sensitive_or_record 'Gatekeeper pre-notarization output' \
  "    ${SPCTL_OUT//$'\n'/$'\n    '}" ||
  die "could not record Gatekeeper pre-notarization output"
grep -q 'accepted' <<<"$SPCTL_OUT" ||
  warn "not yet accepted by Gatekeeper — expected until notarization has run"

capture_codesign 'Code-signing identity inspection' -dv --verbose=4 "$APP"
CODESIGN_DV="$CODESIGN_CAPTURE"
TEAM="$(sed -n 's/^TeamIdentifier=//p' <<<"$CODESIGN_DV")"
if [[ -z "$TEAM" || "$TEAM" == "not set" ]]; then
  if [[ "${REDACT_IDENTITY_OUTPUT-}" == 1 ]]; then
    print_sensitive_or_record 'Team ID verification' \
      "TeamIdentifier is '${TEAM:-empty}' — library validation will kill this at launch" ||
      die "could not record Team ID verification failure"
    die "the signing Team ID is missing — see release-diagnostics.log in the encrypted diagnostics archive"
  fi
  die "TeamIdentifier is '${TEAM:-empty}' — library validation will kill this at launch"
fi

# A non-empty TeamIdentifier only proves SOME certificate signed the app —
# SIGN_IDENTITY's substring match is satisfied by any "Developer ID
# Application" certificate, from any team. The two checks below are what
# EXPECTED_TEAM/EXPECTED_BUNDLE_ID exist for (see their definition above):
# a wrong-team signature is not a build failure the way a missing cert is —
# the app still signs, still verifies, would still notarize — and the
# failure is silent, discovered only when every user's Accessibility grant
# is gone on their next update, because the designated requirement it keys
# on just changed. A stale or hand-edited bundle id would be exactly as
# silent. Both come off the one `codesign -dv` call above, not a second one.
if [[ "$TEAM" != "$EXPECTED_TEAM" ]]; then
  if [[ "${REDACT_IDENTITY_OUTPUT-}" == 1 ]]; then
    print_sensitive_or_record 'Team ID verification' \
      "signed with Team $TEAM, expected $EXPECTED_TEAM — wrong certificate" ||
      die "could not record Team ID verification failure"
    die "the signing Team ID does not match the expected release identity — see release-diagnostics.log in the encrypted diagnostics archive"
  fi
  die "signed with Team $TEAM, expected $EXPECTED_TEAM — wrong certificate: shipping this would silently revoke every user's Accessibility grant on update"
fi

BUNDLE_ID="$(sed -n 's/^Identifier=//p' <<<"$CODESIGN_DV")"
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] ||
  die "signed bundle id is '$BUNDLE_ID', expected '$EXPECTED_BUNDLE_ID' — wrong build: shipping this would silently revoke every user's Accessibility grant on update"

if [[ "${REDACT_IDENTITY_OUTPUT-}" == 1 ]]; then
  print_sensitive_or_record 'Team ID verification' "Signed with Team $TEAM" ||
    die "could not record Team ID verification"
  ok "Signing Team ID verified"
else
  ok "Signed with Team $TEAM"
fi

# An AND-list as the final statement would make the script's exit status the
# status of the *test*, so a full run would sign successfully and then report
# failure. Explicit, so it stays correct wherever this line ends up.
if [[ "$MODE" == "--sign-only" ]]; then
  ok "--sign-only: stopping before notarization"
  exit 0
fi

# --------------------------------------------------------------- notarize ---
#
# Everything past this point uploads to Apple under the account stored in the
# '$NOTARY_PROFILE' keychain profile. One full run submits TWICE (app, then
# DMG). Credentials are stored once, by hand, and never by this script:
#
#   xcrun notarytool store-credentials orthant \
#     --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
#
# The password is the app-specific one from appleid.apple.com, not the account
# password. It lives in the login keychain, which is why nothing here holds a
# secret and this file is safe to commit.

configure_notary_auth || die "invalid notary authentication configuration"
mkdir -p "$DIST"

# `notarytool submit --wait` has been observed to exit 0 on a terminal *Invalid*
# status — it reports "the submission finished", not "the submission passed". So
# the exit code is not the check; the status line is. A pipeline that fails
# toward "fine" is worse than one that fails toward "broken", because nobody
# investigates a pass.
notarize() {
  local artifact="$1" label="$2" out id log submit_rc
  # Braced deliberately. `$label…` puts a multi-byte ellipsis hard against the
  # name and bash takes the first byte of it as part of the identifier, so this
  # died with `label<?>: unbound variable` under `set -u` — after signing, right
  # before the first upload. shellcheck passes it. Every other `…` in this file
  # follows a literal word, which is why this was the only place it could bite.
  info "Notarizing the ${label}…"
  if out="$(xcrun notarytool submit "$artifact" "${NOTARY_AUTH_ARGS[@]}" --wait 2>&1)"; then
    submit_rc=0
  else
    submit_rc=$?
  fi
  print_sensitive_or_record "${label} notary submit output" \
    "    ${out//$'\n'/$'\n    '}" ||
    die "could not record $label notary submit output"
  if (( submit_rc != 0 )) || ! grep -qE '^[[:space:]]*status: Accepted$' <<<"$out"; then
    id="$(sed -n 's/^[[:space:]]*id: \([0-9a-fA-F-]\{36\}\)$/\1/p' <<<"$out" | head -1)"
    if [[ -n "$id" ]]; then
      log="$(xcrun notarytool log "$id" "${NOTARY_AUTH_ARGS[@]}" 2>&1)" || true
      print_sensitive_or_record "${label} notary log output" \
        "    ${log//$'\n'/$'\n    '}" ||
        die "could not record $label notary log output"
    fi
    if [[ "${REDACT_IDENTITY_OUTPUT-}" == 1 ]]; then
      die "$label was not Accepted — see release-diagnostics.log in the encrypted diagnostics archive"
    fi
    die "$label was not Accepted"
  fi
  ok "$label accepted"
}

# **Notarized twice, and the second one is not ceremony.** Stapling only the DMG
# leaves the *extracted* app without a ticket, so its first launch depends on a
# Gatekeeper network check — which fails offline, behind a captive portal, or
# when Apple's service is slow. Stapling the app first means the copy the user
# drags into /Applications carries its own proof.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # ditto, not zip: preserves the bundle
notarize "$ZIP" "app"
xcrun stapler staple "$APP"
ok "App stapled"

# ------------------------------------------------------------------- pack ---

info "Building the DMG…"
STAGE="$(mktemp -d)"
# hdiutil failing would otherwise leak the staging directory, since set -e exits
# before any cleanup line further down.
trap 'rm -rf "$STAGE"' EXIT

# ditto rather than cp -R: the app has just been stapled, and ditto is the tool
# that preserves a signed bundle byte-for-byte, xattrs included. Re-verified
# below rather than assumed.
ditto "$APP" "$STAGE/Orthant.app"
# The drag-to-install affordance, with no dependency beyond hdiutil. A DMG
# without this shows a lone .app and leaves "now what?" to the user.
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Orthant $VERSION" -srcfolder "$STAGE" \
               -ov -format UDZO "$DMG"

# The disk image is signed too, not just notarized. Task 4 expects
# `spctl -t open` to report "source=Notarized Developer ID"; that source name
# requires the DMG to carry a Developer ID signature of its own, and a ticket
# alone does not supply one. No --options runtime here: that flag describes how
# a *process* is launched, and a disk image is not one.
info "Signing the DMG…"
run_codesign 'Release DMG signing' \
  --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

notarize "$DMG" "DMG"
xcrun stapler staple "$DMG"

# ----------------------------------------------------------------- verify ---

info "Verifying the finished artifacts…"
xcrun stapler validate "$APP" || die "the app has no stapled ticket"
xcrun stapler validate "$DMG" || die "the DMG has no stapled ticket"
run_codesign 'Stapled app signature verification' \
  --verify --deep --strict "$APP" || die "the stapled app no longer verifies"

# Under `pipefail` a bare `spctl … | sed` would abort the script with no
# explanation, so the verdict is captured and named.
SPCTL_OUT="$(spctl -a -vvv -t exec "$APP" 2>&1 || true)"
print_sensitive_or_record 'Gatekeeper notarized-app output' \
  "    ${SPCTL_OUT//$'\n'/$'\n    '}" ||
  die "could not record Gatekeeper notarized-app output"
grep -q 'source=Notarized Developer ID' <<<"$SPCTL_OUT" ||
  die "Gatekeeper does not see a notarized Developer ID app — stapling did not take"

sensitive_ok 'release DMG path' 'Release artifact ready' "Ready: $DMG"

# ---------------------------------------------------------------- appcast ---
#
# Sparkle's signing tools (sign_update, generate_appcast) ship as prebuilt
# binaries inside the Sparkle Swift package now, not a CocoaPods pod — M12
# moved distribution to SPM, so the plan's original `macos/Pods/Sparkle/bin`
# paths no longer exist. Two ways to find the real ones: read the path SPM
# already resolved into DerivedData while building above, or resolve the
# package a second time into a path this script controls. DerivedData loses:
# measured, this machine alone has produced well over a dozen distinct
# `Runner-<hash>` directories from old builds, and the hash a *fresh* build
# will pick is not knowable in advance — exactly the kind of
# environment-dependent lookup the file header's "a workflow can call this
# later without a rewrite" promise rules out. Resolving again is cheap once
# Xcode's package cache is warm (seconds — "(cached)" in the output below)
# and it puts the tools at a path of this script's own choosing.
#
# Resolving a second time here cannot pick a different Sparkle than the app
# build above used: both read the same macos/Runner.xcodeproj entry, and
# that entry is pinned with exactVersion (task #12), so the two resolution
# contexts have nothing to diverge on.
info "Resolving Sparkle's CLI tools…"
xcodebuild -resolvePackageDependencies -project macos/Runner.xcodeproj \
           -clonedSourcePackagesDirPath build/spm ||
  die "xcodebuild could not resolve the Sparkle package — see output above"

SPARKLE_BIN="$REPO_ROOT/build/spm/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/sign_update" && -x "$SPARKLE_BIN/generate_appcast" ]] ||
  sensitive_die 'Sparkle tool path' 'Sparkle command-line tools were not resolved' \
    "no sign_update/generate_appcast under $SPARKLE_BIN — resolvePackageDependencies above should have produced them; confirm macos/Runner.xcodeproj still depends on the Sparkle package"

configure_sparkle_args

# generate_appcast refuses to write anything — not just skip the newest file
# — when a .zip and a .dmg in its target directory share a CFBundleVersion:
# "Duplicate updates are not supported." $DIST always has both, because the
# .zip a few lines up exists only to give notarization something to staple
# onto the .app *before* the .dmg is even built (see "notarize" above);
# nothing reads it again afterward. Clear every release .zip before
# generate_appcast looks at the directory — not just this run's, in case an
# older one was ever left behind — rather than special-case the one just
# created.
rm -f "$DIST"/Orthant-*.zip

# The EdDSA signature is what makes the feed trustworthy: without it, anyone
# who can serve the URL can serve an update. Sparkle refuses an item whose
# signature does not match SUPublicEDKey, which is checked by hand in Task 7.
# Signed one at a time, ahead of generate_appcast, so a human reading this
# output sees the exact signature that was computed for each artifact. The
# loop checks the assignment explicitly rather than trusting `set -e` to
# catch a command-substitution failure here: an uncaught one would still stop
# the script, but with none of this script's own naming of which DMG or why
# — and a masked failure is indistinguishable from an empty signature, which
# is the one outcome that must never reach the feed silently.
DMG_COUNT=0
while IFS= read -r -d '' dmg; do
  info "Signing $(basename "$dmg") for the appcast…"
  SIG="$("$SPARKLE_BIN/sign_update" "${SIGN_UPDATE_ARGS[@]}" "$dmg")" ||
    die "sign_update failed on $(basename "$dmg") — see output above"
  [[ -n "$SIG" ]] ||
    die "sign_update produced an empty signature for $(basename "$dmg")"
  ok "appcast entry: $SIG"
  DMG_COUNT=$((DMG_COUNT + 1))
done < <(find "$DIST" -maxdepth 1 -name 'Orthant-*.dmg' -print0)
(( DMG_COUNT > 0 )) ||
  sensitive_die 'release artifact directory' 'no DMG was available for the appcast' \
    "no DMG in $DIST to sign for the appcast"

# generate_appcast reads a directory of signed DMGs and writes the whole
# feed, so the feed is derived from the artifacts rather than hand-edited
# alongside them — two places to update is one place to forget.
#
# Bare like this, every enclosure URL it writes is derived from SUFeedURL's
# own directory in Info.plist — the GitHub Pages URL, not wherever these
# DMGs actually live. That's harmless for a local run, where nothing ever
# fetches the enclosure, but the decided artifact home is GitHub
# **Releases**, not Pages, so the real publish run MUST add
# --download-url-prefix pointing at that release's own download URL, or the
# first shipped feed 404s on every enclosure the moment a real client
# fetches it. Task 7's localhost acceptance used exactly this flag, pointed
# at a throwaway server, for the same reason — ed25519 signing is
# deterministic, so adding the flag on the real publish run does not change
# any signature already computed above.
#
# It also takes no list of artifacts to ingest: it signs and reads every
# Orthant-*.dmg it finds under $DIST itself, the same directory the loop
# above just walked. $DIST accumulates DMGs across releases, so a publish
# run must start from one holding exactly the artifacts meant to ship — a
# foreign or scratch DMG left sitting in it (a tamper fixture sat right
# here once, during Task 7's acceptance) would be swept into a real, signed
# feed alongside the intended ones.
info "Regenerating the appcast…"
"$SPARKLE_BIN/generate_appcast" "${GENERATE_APPCAST_ARGS[@]}" "$DIST" ||
  sensitive_die 'appcast generation paths' 'generate_appcast failed' \
    "generate_appcast failed over $DIST — see output above"

# generate_appcast can exit 0 having silently skipped signing: observed on
# this machine, it printed "Private key for account ed25519 not found in the
# Keychain" and still wrote an item with no sparkle:edSignature attribute —
# immediately after sign_update above found that exact key without
# complaint. Each Sparkle CLI tool apparently needs its own Keychain access
# grant, and an unsigned item is worse than none at all: Sparkle's client
# refuses it, but only after a user's machine has already downloaded it. So
# this trusts the file, not the exit code, matching the "not cannotComplete
# is not succeeded" rule elsewhere in this codebase — an unrecognised outcome
# belongs with "did not land."
#
# Counted, not merely detected with `grep -q` — but counted in two parts, not
# one. A flat `sparkle:edSignature=` count against $DMG_COUNT (this line's
# first version) breaks the moment a second release exists: generate_appcast's
# default --maximum-deltas 5 also emits a binary delta between consecutive
# versions, each in its own <enclosure> nested inside <sparkle:deltas>, each
# independently signed. That's one more signed enclosure than there are DMGs
# in $DIST on a perfectly correct run — found live, on Task 7's real
# two-version dist (2 DMGs, 1 delta, 3 signatures), where the flat count died
# on artifacts that were entirely correct. A delta is exactly as real an
# update as a full DMG, and an unsigned one is exactly as bad: Sparkle's
# client refuses it too, stranding delta-path updaters on a broken entry
# rather than falling back to the full DMG. So this verifies both regions of
# the feed independently instead of shrinking the check to only what it
# originally anticipated (or forgoing deltas — smaller downloads for users —
# just to keep one grep simple). sed finds the boundary generate_appcast's
# own output already gives it: <sparkle:deltas> is either a real tag pair
# bracketing a delta, or absent — never empty or self-closing.
TOP_XML="$(sed '/<sparkle:deltas>/,/<\/sparkle:deltas>/d' "$APPCAST_FILE")"
DELTA_XML="$(sed -n '/<sparkle:deltas>/,/<\/sparkle:deltas>/p' "$APPCAST_FILE")"

# `|| true` on every count below, same reason as before: grep exits 1 on zero
# matches — an empty $DELTA_XML, because nothing has a delta yet, is the
# common case rather than an error — and under this file's `pipefail` that
# would abort the script at the assignment, before either comparison and its
# named reason ever ran.
#
# Two earlier versions of the full-DMG check (see git history) compared
# FULL_SIG_COUNT against $DMG_COUNT — this run's own DMGs on disk — first
# flat across the whole file, then split by region. Both false-positived the
# same way once a release history existed: generate_appcast's own
# --maximum-versions default (3) prunes older full-DMG items OUT of the
# feed, so a feed that signed everything correctly could still hold fewer
# signed items than there are DMGs sitting in $DIST. $DMG_COUNT describes
# this directory, not the feed, and pruning means the feed is allowed to
# describe less than the directory does — so a count against it can never be
# made reliable, pruned or not. What must still never be true, pruned or
# not, is an item that exists but lost its signature, which is a
# self-consistency question each region can answer about itself with no
# outside count at all.
FULL_ENC_COUNT="$(grep -o '<enclosure' <<<"$TOP_XML" | wc -l | tr -d ' ')" || true
FULL_SIG_COUNT="$(grep -o 'sparkle:edSignature=' <<<"$TOP_XML" | wc -l | tr -d ' ')" || true
(( FULL_SIG_COUNT == FULL_ENC_COUNT )) ||
  sensitive_die 'appcast full-item verification paths' \
    'generate_appcast wrote an unsigned full-DMG item' \
    "generate_appcast wrote $APPCAST_FILE with $FULL_SIG_COUNT of $FULL_ENC_COUNT full-DMG item(s) signed — an unsigned item is refused by Sparkle's client, but only after a user's machine has already downloaded it. Try running '$SPARKLE_BIN/generate_appcast ${GENERATE_APPCAST_ARGS[*]} $DIST' once by hand in an interactive Terminal, so any Keychain access prompt has a screen to appear on, then re-run this script."

DELTA_ENC_COUNT="$(grep -o '<enclosure' <<<"$DELTA_XML" | wc -l | tr -d ' ')" || true
DELTA_SIG_COUNT="$(grep -o 'sparkle:edSignature=' <<<"$DELTA_XML" | wc -l | tr -d ' ')" || true
(( DELTA_SIG_COUNT == DELTA_ENC_COUNT )) ||
  sensitive_die 'appcast delta verification paths' \
    'generate_appcast wrote an unsigned delta update' \
    "generate_appcast wrote $APPCAST_FILE with $DELTA_SIG_COUNT of $DELTA_ENC_COUNT delta update(s) signed — an unsigned delta is refused by Sparkle's client exactly like an unsigned full DMG. Try running '$SPARKLE_BIN/generate_appcast ${GENERATE_APPCAST_ARGS[*]} $DIST' once by hand in an interactive Terminal, so any Keychain access prompt has a screen to appear on, then re-run this script."

# Self-consistency above cannot catch a feed that pruned away the release
# this run just built — --maximum-versions is only ever supposed to drop OLD
# items. $BUILD_NUMBER is the same figure preflight's monotonic check (above)
# already required to be newer than anything the feed held before this run,
# so its presence here is what makes trusting pruning for everything older
# a safe conclusion instead of a hopeful one.
grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$APPCAST_FILE" ||
  sensitive_die 'appcast newest-item verification paths' \
    'generate_appcast omitted the release just built' \
    "generate_appcast wrote $APPCAST_FILE with no item for sparkle:version $BUILD_NUMBER (the release just built) — --maximum-versions pruning must never remove the newest item, so something is wrong beyond ordinary pruning. Try running '$SPARKLE_BIN/generate_appcast ${GENERATE_APPCAST_ARGS[*]} $DIST' once by hand in an interactive Terminal, so any Keychain access prompt has a screen to appear on, then re-run this script."

sensitive_ok 'appcast output path' 'Appcast generated' "appcast: $APPCAST_FILE"
