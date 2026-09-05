#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="$SCRIPT_DIR/release_workflow.sh"
TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/fake-bin"
FIXTURES="$TMP_DIR/fixtures"
WORKSPACE="$TMP_DIR/workspace"
CALL_LOG="$TMP_DIR/calls.log"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s\n' "$1" >&2
}

assert_ok() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_fails() {
  local label="$1"
  shift
  if "$@"; then
    fail "$label (unexpected success)"
  else
    pass "$label"
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_file_eq() {
  local label="$1" expected="$2" actual="$3"
  if cmp -s "$expected" "$actual"; then
    pass "$label"
  else
    fail "$label (files differ: $expected $actual)"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing '$needle')"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (unexpected '$needle')"
  fi
}

assert_before() {
  local label="$1" first="$2" second="$3" haystack="$4"
  local first_line second_line
  first_line="$(printf '%s\n' "$haystack" | awk -v needle="$first" 'index($0, needle) { print NR; exit }')"
  second_line="$(printf '%s\n' "$haystack" | awk -v needle="$second" 'index($0, needle) { print NR; exit }')"
  if [[ -n "$first_line" && -n "$second_line" ]] && (( first_line < second_line )); then
    pass "$label"
  else
    fail "$label (expected '$first' before '$second')"
  fi
}

[[ -f "$WORKFLOW" ]] || {
  printf 'release_workflow: missing %s\n' "$WORKFLOW" >&2
  exit 1
}

mkdir -p "$FAKE_BIN" "$FIXTURES" "$WORKSPACE"

cat >"$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
printf 'git' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
if [[ "${1-}" == merge-base && "${2-}" == --is-ancestor ]]; then
  exit "$(<"$FIXTURES/git_ancestor_exit")"
fi
printf 'unexpected fake git invocation\n' >&2
exit 97
EOF

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
output=''
url=''
while (( $# > 0 )); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --write-out) shift 2 ;;
    --header|--connect-timeout|--max-time) shift 2 ;;
    --location|--silent|--show-error|--head) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  */appcast.xml\?run=*) name=stable ;;
  */appcast-beta.xml\?run=*) name=beta ;;
  https://github.com/orthant-app/orthant/releases/download/v1.0.0/Orthant-1.0.0.dmg|\
  https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg|\
  https://github.com/orthant-app/orthant/releases/download/v1.0.2-beta.1/Orthant-1.0.2-beta.1.dmg) name=history ;;
  *) printf 'unexpected fake curl URL: %s\n' "$url" >&2; exit 96 ;;
esac
exit_code="$(<"$FIXTURES/curl_${name}_exit")"
if [[ "$exit_code" != 0 ]]; then
  exit "$exit_code"
fi
if [[ -n "$output" ]]; then
  cp "$FIXTURES/curl_${name}_body" "$output"
fi
printf '%s' "$(<"$FIXTURES/curl_${name}_status")"
EOF

cat >"$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh' >>"$CALL_LOG"
printf ' <%s>' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
if [[ "${1-}" == api ]]; then
  response_path="$(/usr/sbin/lsof -a -p $$ -d 1 -Fn | sed -n 's/^n//p')"
  printf 'gh-api-stdout-mode <%s>\n' "$(stat -f '%Lp' "$response_path")" >>"$CALL_LOG"
  exit_code="$(<"$FIXTURES/gh_api_exit")"
  if [[ "$exit_code" != 0 ]]; then
    printf 'opaque API failure\n' >&2
    exit "$exit_code"
  fi
  status="$(<"$FIXTURES/gh_api_status")"
  printf 'HTTP/2.0 %s Fixture\r\ncontent-type: application/json\r\n\r\n' "$status"
  if [[ "$status" == 200 ]]; then
    cat "$FIXTURES/gh_api_body"
  else
    printf '{"message":"fixture"}\n'
  fi
  exit "$(<"$FIXTURES/gh_api_response_exit")"
fi
if [[ "${1-}" != release ]]; then
  printf 'unexpected fake gh invocation\n' >&2
  exit 95
fi
case "${2-}" in
  list)
    if [[ " $* " == *' --limit 1 '* ]]; then
      cat "$FIXTURES/prior_tag"
    elif [[ " $* " == *' --limit 3 '* ]]; then
      cat "$FIXTURES/stable_tags"
    else
      printf 'unexpected release list limit\n' >&2
      exit 94
    fi
    ;;
  download)
    tag="${3-}"
    dir=''
    shift 3
    while (( $# > 0 )); do
      case "$1" in
        --dir) dir="$2"; shift 2 ;;
        --repo|--pattern) shift 2 ;;
        *) printf 'unexpected release download argument: %s\n' "$1" >&2; exit 93 ;;
      esac
    done
    mkdir -p "$dir"
    printf 'downloaded %s\n' "$tag" >"$dir/Orthant-${tag#v}.dmg"
    ;;
  create)
    shift 2
    while (( $# > 0 )); do
      case "$1" in
        --notes-file) cp "$2" "$FIXTURES/actual_notes"; shift 2 ;;
        *) shift ;;
      esac
    done
    ;;
  view)
    cat "$FIXTURES/actual_assets"
    ;;
  delete-asset)
    name="${4-}"
    awk -v doomed="$name" '$0 != doomed' "$FIXTURES/actual_assets" >"$FIXTURES/actual_assets.next"
    mv "$FIXTURES/actual_assets.next" "$FIXTURES/actual_assets"
    ;;
  upload)
    shift 3
    : >"$FIXTURES/actual_assets"
    while (( $# > 0 )); do
      case "$1" in
        --clobber) shift ;;
        --repo) shift 2 ;;
        *) basename "$1" >>"$FIXTURES/actual_assets"; shift ;;
      esac
    done
    if [[ -n "${GH_UPLOAD_OVERRIDE_FILE-}" ]]; then
      cp "$GH_UPLOAD_OVERRIDE_FILE" "$FIXTURES/actual_assets"
    fi
    ;;
  edit) ;;
  *) printf 'unexpected fake gh release command: %s\n' "${2-}" >&2; exit 92 ;;
esac
EOF
chmod +x "$FAKE_BIN/git" "$FAKE_BIN/curl" "$FAKE_BIN/gh"

reset_fixture() {
  rm -rf "$WORKSPACE"
  mkdir -p "$WORKSPACE"
  : >"$CALL_LOG"
  printf 'version: 1.0.0+1\n' >"$WORKSPACE/pubspec.yaml"
  mkdir -p "$WORKSPACE/site/src/content/changelog"
  cat >"$WORKSPACE/site/src/content/changelog/1.0.0.md" <<'ENTRY'
---
version: 1.0.0
build: 1
channel: stable
published: false
date: 2026-08-31
---

First stable release.
ENTRY
  # Named and declared by BASE version, not the full tag: a beta tag
  # (v1.1.0-beta.1) and its eventual stable (v1.1.0) share this one entry, so
  # this fixture is deliberately shaped to match what
  # test/site_docs_test.dart's own guard requires — frontmatter `version:`
  # equal to pubspec.yaml's marketing version, which never carries a
  # "-beta.N" label. A file named 1.1.0-beta.1.md would satisfy this harness
  # but fail that Dart guard the moment pubspec.yaml read version: 1.1.0.
  cat >"$WORKSPACE/site/src/content/changelog/1.1.0.md" <<'ENTRY'
---
version: 1.1.0
build: 2
channel: beta
published: false
date: 2026-08-31
---

Beta body.
ENTRY
  : >"$FIXTURES/actual_notes"
  printf '0\n' >"$FIXTURES/git_ancestor_exit"
  printf '0\n' >"$FIXTURES/gh_api_exit"
  printf '0\n' >"$FIXTURES/gh_api_response_exit"
  printf '404\n' >"$FIXTURES/gh_api_status"
  printf '{"draft":true}\n' >"$FIXTURES/gh_api_body"
  : >"$FIXTURES/prior_tag"
  : >"$FIXTURES/stable_tags"
  : >"$FIXTURES/actual_assets"
  printf '404\n' >"$FIXTURES/curl_stable_status"
  printf '0\n' >"$FIXTURES/curl_stable_exit"
  : >"$FIXTURES/curl_stable_body"
  printf '404\n' >"$FIXTURES/curl_beta_status"
  printf '0\n' >"$FIXTURES/curl_beta_exit"
  : >"$FIXTURES/curl_beta_body"
  printf '200\n' >"$FIXTURES/curl_history_status"
  printf '0\n' >"$FIXTURES/curl_history_exit"
  : >"$FIXTURES/curl_history_body"
}

run_workflow() {
  (cd "$WORKSPACE" && env \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    CALL_LOG="$CALL_LOG" \
    FIXTURES="$FIXTURES" \
    GITHUB_RUN_ID=123 \
    GITHUB_RUN_ATTEMPT=4 \
    bash "$WORKFLOW" "$@")
}

metadata_main() {
  reset_fixture
  run_workflow metadata workflow_dispatch branch main orthant-app/orthant "$WORKSPACE/output"
}

metadata_beta() {
  reset_fixture
  printf 'version: 1.1.0+2\n' >"$WORKSPACE/pubspec.yaml"
  run_workflow metadata push tag v1.1.0-beta.1 orthant-app/orthant "$WORKSPACE/output"
}

assert_ok 'dispatch metadata succeeds' metadata_main
assert_eq 'dispatch metadata is exact' \
  $'version=1.0.0\nbase_version=1.0.0\nprerelease=false\npublish=false\nmode=dry-run' \
  "$(<"$WORKSPACE/output")"
assert_eq 'dispatch does not query GitHub or git' '' "$(<"$CALL_LOG")"

reset_fixture
assert_ok 'dispatch against a tag ref still does not publish' \
  run_workflow metadata workflow_dispatch tag v9.9.9 orthant-app/orthant "$WORKSPACE/output"
assert_eq 'dispatch tag ref still reads pubspec base' \
  $'version=1.0.0\nbase_version=1.0.0\nprerelease=false\npublish=false\nmode=dry-run' \
  "$(<"$WORKSPACE/output")"

reset_fixture
assert_ok 'push branch does not publish' \
  run_workflow metadata push branch main orthant-app/orthant "$WORKSPACE/output"
assert_contains 'push branch emits publish false' 'publish=false' "$(<"$WORKSPACE/output")"

assert_ok 'beta tag metadata succeeds' metadata_beta
assert_eq 'beta tag metadata is exact' \
  $'version=1.1.0-beta.1\nbase_version=1.1.0\nprerelease=true\npublish=true\nmode=beta' \
  "$(<"$WORKSPACE/output")"
assert_contains 'tag metadata checks ancestry' 'git <merge-base> <--is-ancestor> <HEAD> <origin/main>' "$(<"$CALL_LOG")"
assert_contains 'tag metadata queries the explicit repository release endpoint' \
  'gh <api> <--include> <repos/orthant-app/orthant/releases/tags/v1.1.0-beta.1>' "$(<"$CALL_LOG")"
assert_contains 'release API response file is mode 600' 'gh-api-stdout-mode <600>' "$(<"$CALL_LOG")"

for invalid_tag in 'v1/1.0' 'v1.1.0+meta' 'v01.1.0' 'v1.1.0'; do
  reset_fixture
  printf 'version: 1.2.0+2\n' >"$WORKSPACE/pubspec.yaml"
  assert_fails "invalid or mismatched tag $invalid_tag fails" \
    run_workflow metadata push tag "$invalid_tag" orthant-app/orthant "$WORKSPACE/output"
done

reset_fixture
printf 'version: 1.1.0+2\n' >"$WORKSPACE/pubspec.yaml"
printf '1\n' >"$FIXTURES/git_ancestor_exit"
assert_fails 'non-ancestral tag commit fails' \
  run_workflow metadata push tag v1.1.0 orthant-app/orthant "$WORKSPACE/output"

reset_fixture
printf '200\n' >"$FIXTURES/gh_api_status"
printf '{"metadata":{"draft":true},"draft":false}\n' >"$FIXTURES/gh_api_body"
assert_fails 'nested draft cannot hide a current public release' \
  run_workflow metadata push tag v1.0.0 orthant-app/orthant "$WORKSPACE/output"

reset_fixture
printf '200\n' >"$FIXTURES/gh_api_status"
printf '{"draft":true}\n' >"$FIXTURES/gh_api_body"
assert_ok 'current draft release permits metadata retry' \
  run_workflow metadata push tag v1.0.0 orthant-app/orthant "$WORKSPACE/output"

for invalid_body in \
  '{}' \
  '{"draft":null}' \
  '{"draft":"true"}' \
  '{"draft":true,"draft":false}' \
  '{"draft":true,"invalid":NaN}' \
  '{"draft":true'; do
  reset_fixture
  printf '200\n' >"$FIXTURES/gh_api_status"
  printf '%s\n' "$invalid_body" >"$FIXTURES/gh_api_body"
  assert_fails "invalid release draft JSON fails closed: $invalid_body" \
    run_workflow metadata push tag v1.0.0 orthant-app/orthant "$WORKSPACE/output"
done

reset_fixture
printf '1\n' >"$FIXTURES/gh_api_response_exit"
assert_ok 'confirmed release 404 permits metadata' \
  run_workflow metadata push tag v1.0.0 orthant-app/orthant "$WORKSPACE/output"

for status in 401 403 429 500 503; do
  reset_fixture
  printf '%s\n' "$status" >"$FIXTURES/gh_api_status"
  assert_fails "release API HTTP $status fails closed" \
    run_workflow metadata push tag v1.0.0 orthant-app/orthant "$WORKSPACE/output"
done

reset_fixture
printf '1\n' >"$FIXTURES/gh_api_exit"
assert_fails 'release API transport failure fails closed' \
  run_workflow metadata push tag v1.0.0 orthant-app/orthant "$WORKSPACE/output"

# This file has no $STDERR fixture, so stderr is captured directly: swap fds so
# the command substitution collects fd 2 while fd 1 (the metadata output file
# path is a positional argument, not stdout) is discarded.
reset_fixture
rm -f "$WORKSPACE/site/src/content/changelog/1.0.0.md"
stderr="$(run_workflow metadata push tag v1.0.0 orthant-app/orthant "$WORKSPACE/output" 2>&1 1>/dev/null)"
status=$?
assert_eq 'metadata rejects a tag with no changelog entry' 1 "$status"
assert_contains 'metadata names the missing entry' \
  'changelog entry missing: site/src/content/changelog/1.0.0.md' "$stderr"

# A beta tag must resolve against the BASE-version entry (1.1.0.md), not a
# per-tag filename (1.1.0-beta.1.md) — the fixture only ever provides the
# former. This is the harness case for the beta-tag path: it fails exactly
# the way the pre-fix code (which read `site/src/content/changelog/$version.md`,
# where $version still carried the "-beta.1" suffix) would have looked for a
# file that can never exist under the one-entry-per-marketing-version rule.
reset_fixture
rm -f "$WORKSPACE/site/src/content/changelog/1.1.0.md"
printf 'version: 1.1.0+2\n' >"$WORKSPACE/pubspec.yaml"
stderr="$(run_workflow metadata push tag v1.1.0-beta.1 orthant-app/orthant "$WORKSPACE/output" 2>&1 1>/dev/null)"
status=$?
assert_eq 'metadata rejects a beta tag with no BASE-version changelog entry' 1 "$status"
assert_contains 'metadata names the missing base-version entry for a beta tag' \
  'changelog entry missing: site/src/content/changelog/1.1.0.md' "$stderr"

reset_fixture
mkdir -p "$WORKSPACE/site/src/content/changelog"
printf 'version: 1.2.0+3\n' >"$WORKSPACE/pubspec.yaml"
cat >"$WORKSPACE/site/src/content/changelog/1.2.0.md" <<'ENTRY'
---
version: 1.2.0
build: 3
channel: beta
published: false
date: 2026-08-31
---
ENTRY
stderr="$(run_workflow metadata push tag v1.2.0-beta.1 orthant-app/orthant "$WORKSPACE/output" 2>&1 1>/dev/null)"
status=$?
assert_eq 'metadata rejects a beta tag whose base-version entry has no body' 1 "$status"
assert_contains 'metadata names the empty base-version entry for a beta tag' \
  'changelog entry has no body: site/src/content/changelog/1.2.0.md' "$stderr"

reset_fixture
assert_ok 'no release and two missing feeds is first publication' \
  run_workflow check-settled orthant-app/orthant

for feed in stable beta; do
  reset_fixture
  printf 'v0.9.0\n' >"$FIXTURES/prior_tag"
  printf '200\n' >"$FIXTURES/curl_${feed}_status"
  printf '<enclosure url="https://github.com/orthant-app/orthant/releases/download/v0.9.0/Orthant-0.9.0.dmg"/>\n' \
    >"$FIXTURES/curl_${feed}_body"
  assert_ok "prior public release in $feed feed is settled" \
    run_workflow check-settled orthant-app/orthant
done

reset_fixture
printf 'v0.9.0\n' >"$FIXTURES/prior_tag"
printf '200\n' >"$FIXTURES/curl_stable_status"
printf '<rss><channel>\n<!-- <enclosure\n  url="https://example.invalid/releases/download/v0.9.0/commented.dmg"/> -->\n<enclosure\n  length="10"\n  url="https://example.invalid/releases/download/v0.8.0/old.dmg"/>\n</channel></rss>\n' \
  >"$FIXTURES/curl_stable_body"
assert_fails 'commented enclosure cannot settle the prior public release' \
  run_workflow check-settled orthant-app/orthant

reset_fixture
printf 'v0.9.0\n' >"$FIXTURES/prior_tag"
printf '200\n' >"$FIXTURES/curl_stable_status"
printf '<rss><channel><![CDATA[<enclosure url="https://example.invalid/releases/download/v0.9.0/cdata.dmg"/>]]><enclosure url="https://example.invalid/releases/download/v0.8.0/old.dmg"/></channel></rss>\n' \
  >"$FIXTURES/curl_stable_body"
assert_fails 'CDATA enclosure text cannot settle the prior public release' \
  run_workflow check-settled orthant-app/orthant

for status in 401 500; do
  reset_fixture
  printf '%s\n' "$status" >"$FIXTURES/curl_beta_status"
  assert_fails "feed HTTP $status fails closed" \
    run_workflow restore beta orthant-app/orthant "$WORKSPACE/dist"
  [[ ! -e "$WORKSPACE/dist/appcast-beta.xml" ]] || fail "feed HTTP $status leaves no destination"
done

reset_fixture
printf '7\n' >"$FIXTURES/curl_beta_exit"
assert_fails 'feed curl exit 7 fails closed' \
  run_workflow restore beta orthant-app/orthant "$WORKSPACE/dist"
if [[ ! -e "$WORKSPACE/dist/appcast-beta.xml" ]]; then
  pass 'feed transport failure leaves no destination'
else
  fail 'feed transport failure leaves no destination'
fi

reset_fixture
printf '200\n' >"$FIXTURES/curl_beta_status"
printf 'beta feed bytes\n' >"$FIXTURES/curl_beta_body"
assert_ok 'feed HTTP 200 restores body' \
  run_workflow restore beta orthant-app/orthant "$WORKSPACE/dist"
assert_file_eq 'feed restore is byte-identical' "$FIXTURES/curl_beta_body" "$WORKSPACE/dist/appcast-beta.xml"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf 'stale\n' >"$WORKSPACE/dist/appcast-beta.xml"
assert_ok 'feed HTTP 404 restore succeeds' \
  run_workflow restore beta orthant-app/orthant "$WORKSPACE/dist"
if [[ ! -e "$WORKSPACE/dist/appcast-beta.xml" ]]; then
  pass 'feed HTTP 404 leaves no file'
else
  fail 'feed HTTP 404 leaves no file'
fi

reset_fixture
printf 'v0.9.0\nv0.8.0\n' >"$FIXTURES/stable_tags"
mkdir -p "$WORKSPACE/dist"
printf 'keep\n' >"$WORKSPACE/dist/unrelated.txt"
assert_ok 'stable restore succeeds' \
  run_workflow restore stable orthant-app/orthant "$WORKSPACE/dist"
calls="$(<"$CALL_LOG")"
assert_contains 'stable restore lists three public stable releases' \
  'gh <release> <list> <--exclude-drafts> <--exclude-pre-releases> <--limit> <3> <--repo> <orthant-app/orthant>' "$calls"
assert_contains 'stable restore downloads first explicit tag' 'gh <release> <download> <v0.9.0>' "$calls"
assert_contains 'stable restore downloads second explicit tag' 'gh <release> <download> <v0.8.0>' "$calls"
assert_eq 'restore preserves unrelated dist files' 'keep' "$(<"$WORKSPACE/dist/unrelated.txt")"

reset_fixture
printf 'v0.9.0\n' >"$FIXTURES/stable_tags"
assert_ok 'beta restore succeeds without prior DMG download' \
  run_workflow restore beta orthant-app/orthant "$WORKSPACE/dist"
assert_not_contains 'beta restore skips stable release listing' 'gh <release> <list>' "$(<"$CALL_LOG")"
assert_not_contains 'beta restore skips prior DMG download' 'gh <release> <download>' "$(<"$CALL_LOG")"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf '<rss><channel><title>Stable</title></channel></rss>\n' >"$WORKSPACE/dist/appcast.xml"
assert_ok 'stable Pages assembly succeeds' \
  run_workflow assemble-pages stable "$WORKSPACE/dist" "$WORKSPACE/site"
assert_file_eq 'stable assembly creates stable feed' "$WORKSPACE/dist/appcast.xml" "$WORKSPACE/site/appcast.xml"
assert_file_eq 'stable assembly creates identical beta feed' "$WORKSPACE/dist/appcast.xml" "$WORKSPACE/site/appcast-beta.xml"

reset_fixture
mkdir -p "$WORKSPACE/dist" "$WORKSPACE/site"
printf '<rss><channel><title>Stable</title></channel></rss>\n' >"$WORKSPACE/dist/appcast.xml"
printf '<rss><channel><title>Beta</title></channel></rss>\n' >"$WORKSPACE/dist/appcast-beta.xml"
printf 'stale site\n' >"$WORKSPACE/site/stale"
assert_ok 'beta Pages assembly preserves stable feed' \
  run_workflow assemble-pages beta "$WORKSPACE/dist" "$WORKSPACE/site"
assert_file_eq 'beta assembly copies stable feed' "$WORKSPACE/dist/appcast.xml" "$WORKSPACE/site/appcast.xml"
assert_file_eq 'beta assembly copies beta feed' "$WORKSPACE/dist/appcast-beta.xml" "$WORKSPACE/site/appcast-beta.xml"
if [[ ! -e "$WORKSPACE/site/stale" ]]; then
  pass 'Pages assembly recreates site'
else
  fail 'Pages assembly recreates site'
fi

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf '<rss><channel><title>Beta</title></channel></rss>\n' >"$WORKSPACE/dist/appcast-beta.xml"
assert_ok 'first beta Pages assembly permits absent stable feed' \
  run_workflow assemble-pages beta "$WORKSPACE/dist" "$WORKSPACE/site"
if [[ ! -e "$WORKSPACE/site/appcast.xml" ]]; then
  pass 'first beta leaves stable feed absent'
else
  fail 'first beta leaves stable feed absent'
fi

# A Pages deploy replaces the whole site, so CNAME must be re-emitted by EVERY
# assembly or the custom domain is dropped on the next release and every shipped
# copy's SUFeedURL starts 404ing. Asserted in all three modes because a mode that
# forgot it would break the domain only on the release that used that mode.
for cname_mode in stable dry-run beta; do
  reset_fixture
  mkdir -p "$WORKSPACE/dist"
  printf '<rss><channel><title>Stable</title></channel></rss>\n' >"$WORKSPACE/dist/appcast.xml"
  printf '<rss><channel><title>Beta</title></channel></rss>\n' >"$WORKSPACE/dist/appcast-beta.xml"
  assert_ok "$cname_mode Pages assembly succeeds" \
    run_workflow assemble-pages "$cname_mode" "$WORKSPACE/dist" "$WORKSPACE/site"
  if [[ "$(cat "$WORKSPACE/site/CNAME" 2>/dev/null)" == 'updates.orthant.app' ]]; then
    pass "$cname_mode assembly emits CNAME for the shipped SUFeedURL host"
  else
    fail "$cname_mode assembly emits CNAME for the shipped SUFeedURL host"
  fi
done

# A real generated feed combines this release's URL prefix with older DMGs.
# The 1.0.0 URL was already corrupt in the feed restored from production, so
# checking only the previous release's prefix would leave that entry broken.
write_history_feed() {
  cat >"$1" <<'FEED'
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Orthant</title>
    <item>
      <title>1.0.2</title><sparkle:version>6</sparkle:version>
      <sparkle:shortVersionString>1.0.2</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>Keep & preserve release notes.</p>]]></description>
      <enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.0.2/Orthant-1.0.2.dmg" length="21300000" sparkle:edSignature="new-full-signature" type="application/octet-stream"/>
      <sparkle:deltas>
        <enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.0.2/Orthant6-5.delta" length="1200000" sparkle:deltaFrom="5" sparkle:edSignature="new-delta-signature" type="application/octet-stream"/>
      </sparkle:deltas>
    </item>
    <item>
      <title>1.0.1</title><sparkle:version>5</sparkle:version>
      <enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.0.2/Orthant-1.0.1.dmg" length="21257025" sparkle:edSignature="old-full-signature" type="application/octet-stream"/>
    </item>
    <item>
      <title>1.0.0</title><sparkle:version>4</sparkle:version>
      <enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.0.dmg" length="21253090" sparkle:edSignature="oldest-full-signature" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
FEED
}

history_urls_are_correct() {
  python3 - "$1" <<'PYTHON'
import sys
import xml.etree.ElementTree as ET
urls = [node.attrib['url'] for node in ET.parse(sys.argv[1]).iter('enclosure')]
assert urls == [
    'https://github.com/orthant-app/orthant/releases/download/v1.0.2/Orthant-1.0.2.dmg',
    'https://github.com/orthant-app/orthant/releases/download/v1.0.2/Orthant6-5.delta',
    'https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg',
    'https://github.com/orthant-app/orthant/releases/download/v1.0.0/Orthant-1.0.0.dmg',
], urls
PYTHON
}

feed_metadata_is_unchanged() {
  python3 - "$1" "$2" <<'PYTHON'
import sys
from xml.dom import minidom
feeds = [minidom.parse(path) for path in sys.argv[1:]]
for feed in feeds:
    for node in feed.getElementsByTagName('enclosure'):
        node.removeAttribute('url')
assert feeds[0].toxml() == feeds[1].toxml()
PYTHON
}

for history_mode in stable dry-run; do
  reset_fixture
  mkdir -p "$WORKSPACE/dist"
  write_history_feed "$WORKSPACE/dist/appcast.xml"
  assert_ok "$history_mode assembly repairs generated and already-corrupt history" \
    run_workflow assemble-pages "$history_mode" "$WORKSPACE/dist" "$WORKSPACE/site"
  assert_ok "$history_mode historical DMGs use their own tags; current DMG and delta stay put" \
    history_urls_are_correct "$WORKSPACE/site/appcast.xml"
  assert_ok "$history_mode feed signatures, versions and release notes are unchanged" \
    feed_metadata_is_unchanged "$WORKSPACE/dist/appcast.xml" "$WORKSPACE/site/appcast.xml"
  assert_file_eq "$history_mode publishes the same repaired feed to beta users" \
    "$WORKSPACE/site/appcast.xml" "$WORKSPACE/site/appcast-beta.xml"
  assert_contains "$history_mode checks the repaired historical asset before publishing" \
    '<https://github.com/orthant-app/orthant/releases/download/v1.0.0/Orthant-1.0.0.dmg>' "$(<"$CALL_LOG")"
  assert_not_contains "$history_mode does not probe the unpublished current release" \
    '<https://github.com/orthant-app/orthant/releases/download/v1.0.2/Orthant-1.0.2.dmg>' "$(<"$CALL_LOG")"
done

reset_fixture
mkdir -p "$WORKSPACE/dist"
write_history_feed "$WORKSPACE/dist/appcast.xml"
cat >"$WORKSPACE/dist/appcast-beta.xml" <<'FEED'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
  <item><title>1.1.0 beta</title><sparkle:version>7</sparkle:version><sparkle:shortVersionString>1.1.0</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel>
    <enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.1.0-beta.1/Orthant-1.1.0-beta.1.dmg" sparkle:edSignature="beta-signature" length="21400000"/>
  </item>
  <item><title>1.0.2 beta</title><sparkle:version>6</sparkle:version><sparkle:shortVersionString>1.0.2</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel>
    <enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.1.0-beta.1/Orthant-1.0.2-beta.1.dmg" sparkle:edSignature="old-beta-signature" length="21300000"/>
  </item>
</channel></rss>
FEED
beta_urls_are_correct() {
  python3 - "$1" <<'PYTHON'
import sys
import xml.etree.ElementTree as ET
urls = [node.attrib['url'] for node in ET.parse(sys.argv[1]).iter('enclosure')]
assert urls == [
    'https://github.com/orthant-app/orthant/releases/download/v1.1.0-beta.1/Orthant-1.1.0-beta.1.dmg',
    'https://github.com/orthant-app/orthant/releases/download/v1.0.2-beta.1/Orthant-1.0.2-beta.1.dmg',
], urls
PYTHON
}
assert_ok 'beta assembly also heals the restored stable feed' \
  run_workflow assemble-pages beta "$WORKSPACE/dist" "$WORKSPACE/site"
assert_ok 'beta deployment repairs every restored stable full-DMG URL' \
  history_urls_are_correct "$WORKSPACE/site/appcast.xml"
assert_ok 'current and historical beta filenames retain their own prerelease tags' \
  beta_urls_are_correct "$WORKSPACE/site/appcast-beta.xml"
assert_ok 'beta feed signatures, versions and channel metadata are unchanged' \
  feed_metadata_is_unchanged "$WORKSPACE/dist/appcast-beta.xml" "$WORKSPACE/site/appcast-beta.xml"

# A missing old artifact must fail before Pages can be uploaded. A 200 on a
# different (e.g. latest-release) URL cannot satisfy this fake: it rejects any
# asset URL except the literal historical targets above.
for history_status in 404 503; do
  reset_fixture
  mkdir -p "$WORKSPACE/dist"
  write_history_feed "$WORKSPACE/dist/appcast.xml"
  printf '%s\n' "$history_status" >"$FIXTURES/curl_history_status"
  assert_fails "historical asset HTTP $history_status prevents Pages assembly" \
    run_workflow assemble-pages stable "$WORKSPACE/dist" "$WORKSPACE/site"
done
reset_fixture
mkdir -p "$WORKSPACE/dist"
write_history_feed "$WORKSPACE/dist/appcast.xml"
printf '7\n' >"$FIXTURES/curl_history_exit"
assert_fails 'historical asset transport failure prevents Pages assembly' \
  run_workflow assemble-pages stable "$WORKSPACE/dist" "$WORKSPACE/site"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf 'dmg\n' >"$WORKSPACE/dist/Orthant-1.0.0.dmg"
assert_ok 'draft publication with no delta succeeds' \
  run_workflow publish orthant-app/orthant 1.0.0 false "$WORKSPACE/dist"
calls="$(<"$CALL_LOG")"
assert_contains 'new draft is created explicitly' \
  'gh <release> <create> <v1.0.0> <--draft> <--verify-tag> <--notes-file> <build/dist/release-notes.md> <--repo> <orthant-app/orthant>' "$calls"
assert_contains 'single DMG is uploaded explicitly' \
  "gh <release> <upload> <v1.0.0> <$WORKSPACE/dist/Orthant-1.0.0.dmg> <--clobber> <--repo> <orthant-app/orthant>" "$calls"
assert_contains 'release notes carry the changelog body' \
  'First stable release.' "$(<"$FIXTURES/actual_notes")"
assert_not_contains 'release notes exclude the frontmatter delimiter' \
  '---' "$(<"$FIXTURES/actual_notes")"
assert_not_contains 'release notes exclude the published flag' \
  'published:' "$(<"$FIXTURES/actual_notes")"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf 'dmg\n' >"$WORKSPACE/dist/Orthant-1.1.0-beta.1.dmg"
printf 'delta a\n' >"$WORKSPACE/dist/a.delta"
printf 'delta z\n' >"$WORKSPACE/dist/z.delta"
printf '200\n' >"$FIXTURES/gh_api_status"
printf '{"draft":true}\n' >"$FIXTURES/gh_api_body"
printf 'stale.zip\nOrthant-1.1.0-beta.1.dmg\n' >"$FIXTURES/actual_assets"
assert_ok 'draft retry replaces stale assets and uploads all deltas' \
  run_workflow publish orthant-app/orthant 1.1.0-beta.1 true "$WORKSPACE/dist"
calls="$(<"$CALL_LOG")"
assert_contains 'stale draft asset is deleted' \
  'gh <release> <delete-asset> <v1.1.0-beta.1> <stale.zip> <--yes> <--repo> <orthant-app/orthant>' "$calls"
assert_before 'stale draft asset is deleted before upload' '<delete-asset>' '<upload>' "$calls"
assert_contains 'all explicit delta paths are uploaded' \
  "<$WORKSPACE/dist/a.delta> <$WORKSPACE/dist/z.delta>" "$calls"

reset_fixture
mkdir -p "$WORKSPACE/dist"
assert_fails 'publication requires the expected DMG' \
  run_workflow publish orthant-app/orthant 1.0.0 false "$WORKSPACE/dist"
assert_eq 'missing asset causes no GitHub calls' '' "$(<"$CALL_LOG")"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf 'dmg\n' >"$WORKSPACE/dist/Orthant-1.0.0.dmg"
printf '200\n' >"$FIXTURES/gh_api_status"
printf '{"draft":false}\n' >"$FIXTURES/gh_api_body"
assert_fails 'publication defensively rejects a public release' \
  run_workflow publish orthant-app/orthant 1.0.0 false "$WORKSPACE/dist"
assert_not_contains 'public release rejection does not upload' '<upload>' "$(<"$CALL_LOG")"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf 'dmg\n' >"$WORKSPACE/dist/Orthant-1.0.0.dmg"
printf '503\n' >"$FIXTURES/gh_api_status"
assert_fails 'publication defensively rejects indeterminate API state' \
  run_workflow publish orthant-app/orthant 1.0.0 false "$WORKSPACE/dist"
assert_not_contains 'indeterminate release state does not create a draft' '<create>' "$(<"$CALL_LOG")"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf 'dmg\n' >"$WORKSPACE/dist/Orthant-1.0.0.dmg"
printf 'unexpected\n' >"$FIXTURES/upload_override"
export GH_UPLOAD_OVERRIDE_FILE="$FIXTURES/upload_override"
assert_fails 'sorted asset inequality prevents publication' \
  run_workflow publish orthant-app/orthant 1.0.0 false "$WORKSPACE/dist"
unset GH_UPLOAD_OVERRIDE_FILE
assert_not_contains 'asset inequality leaves draft unpublished' '<edit>' "$(<"$CALL_LOG")"

reset_fixture
mkdir -p "$WORKSPACE/dist"
printf 'dmg\n' >"$WORKSPACE/dist/Orthant-1.1.0-beta.1.dmg"
assert_ok 'exact asset equality publishes prerelease' \
  run_workflow publish orthant-app/orthant 1.1.0-beta.1 true "$WORKSPACE/dist"
calls="$(<"$CALL_LOG")"
assert_contains 'prerelease creation flags are exact' \
  'gh <release> <create> <v1.1.0-beta.1> <--draft> <--verify-tag> <--notes-file> <build/dist/release-notes.md> <--prerelease> <--latest=false>' "$calls"
assert_contains 'publication edit carries prerelease latest flags' \
  'gh <release> <edit> <v1.1.0-beta.1> <--draft=false> <--prerelease=true> <--latest=false> <--repo> <orthant-app/orthant>' "$calls"
assert_eq 'publication edit is the final state-changing call' \
  'gh <release> <edit> <v1.1.0-beta.1> <--draft=false> <--prerelease=true> <--latest=false> <--repo> <orthant-app/orthant>' \
  "$(tail -n 1 "$CALL_LOG")"
assert_contains 'a beta publish reads notes from the shared BASE-version entry, not a per-tag file' \
  'Beta body.' "$(<"$FIXTURES/actual_notes")"

reset_fixture
mkdir -p "$WORKSPACE/dist"
rm -f "$WORKSPACE/site/src/content/changelog/1.1.0.md"
printf 'dmg\n' >"$WORKSPACE/dist/Orthant-1.1.0-beta.1.dmg"
stderr="$(run_workflow publish orthant-app/orthant 1.1.0-beta.1 true "$WORKSPACE/dist" 2>&1 1>/dev/null)"
status=$?
assert_eq 'publish rejects a beta version with no BASE-version changelog entry' 1 "$status"
assert_contains 'publish names the missing base-version entry for a beta version' \
  'changelog entry missing: site/src/content/changelog/1.1.0.md' "$stderr"

# RELEASING.md is the tracked runbook, and a runbook that quietly stops matching
# the pipeline is worse than none: it is followed confidently and is wrong. Pin
# the load-bearing facts it states to the code that implements them.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASING="$REPO_ROOT/RELEASING.md"

assert_ok 'RELEASING.md exists' test -f "$RELEASING"

# The collection path. If the changelog moves, the runbook tells you to write
# the entry somewhere the release will not look for it.
changelog_dir_in_code="$(grep -oE 'site/src/content/changelog/' "$REPO_ROOT/tool/ci/release_workflow.sh" | head -n 1)"
assert_contains 'RELEASING.md names the changelog path the pipeline actually reads' \
  "$changelog_dir_in_code" "$(<"$RELEASING")"

# The two frontmatter keys the release and the site each turn on: `version` is
# what test/site_docs_test.dart matches against pubspec, and `published` is what
# gates the site advertising the release at all.
assert_contains 'RELEASING.md documents the version frontmatter key' \
  'version:' "$(<"$RELEASING")"
assert_contains 'RELEASING.md documents the published frontmatter key' \
  'published:' "$(<"$RELEASING")"

# The notes mechanism. If publish() ever went back to --generate-notes, the
# runbook's claim that the entry is the single source would be false.
assert_contains 'publish() still sources release notes from the changelog entry' \
  '--notes-file' "$(<"$REPO_ROOT/tool/ci/release_workflow.sh")"
# Comments stripped first: the line above the create_args assignment explains
# why --generate-notes is NOT used by naming it, so scanning the raw file trips
# on the very prose that documents the decision. Same trap as the docs sidebar
# and hero style guards.
assert_ok 'publish() does not use --generate-notes' \
  bash -c "! sed 's/#.*//' '$REPO_ROOT/tool/ci/release_workflow.sh' | grep -q -- '--generate-notes'"

if (( FAIL_COUNT > 0 )); then
  printf '%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
  exit 1
fi
printf '%d passed, 0 failed\n' "$PASS_COUNT"
