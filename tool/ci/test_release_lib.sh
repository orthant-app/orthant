#!/usr/bin/env bash
# shellcheck disable=SC2034

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/release_lib.sh"
TMP_DIR="$(mktemp -d)"
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

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected $expected, got $actual)"
  fi
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

[[ -f "$LIB" ]] || {
  printf 'release_lib: missing %s\n' "$LIB" >&2
  exit 1
}
# shellcheck disable=SC1090,SC1091
source "$LIB"

version_state_is() {
  validate_release_version "$1" &&
    [[ "$RELEASE_BASE_VERSION" == "$2" ]] &&
    [[ "$RELEASE_PRERELEASE" == "$3" ]]
}

pubspec_state_is() {
  parse_pubspec_version "$1" &&
    [[ "$PUBSPEC_BASE_VERSION" == "$2" ]] &&
    [[ "$PUBSPEC_BUILD_NUMBER" == "$3" ]]
}

notary_profile_is() {
  unset NOTARY_KEY_FILE NOTARY_KEY_ID NOTARY_ISSUER
  NOTARY_PROFILE='orthant-profile'
  configure_notary_auth &&
    [[ "${NOTARY_AUTH_ARGS[*]}" == '--keychain-profile orthant-profile' ]]
}

notary_p8_is() {
  NOTARY_KEY_FILE='/tmp/AuthKey.p8'
  NOTARY_KEY_ID='key-id'
  NOTARY_ISSUER='issuer-id'
  configure_notary_auth &&
    [[ "${NOTARY_AUTH_ARGS[*]}" == '--key /tmp/AuthKey.p8 --key-id key-id --issuer issuer-id' ]]
}

notary_partial_fails() {
  NOTARY_KEY_FILE='/tmp/AuthKey.p8'
  unset NOTARY_KEY_ID NOTARY_ISSUER
  ! configure_notary_auth
}

notary_two_partials_fail() {
  NOTARY_KEY_FILE='/tmp/AuthKey.p8'
  NOTARY_KEY_ID='key-id'
  unset NOTARY_ISSUER
  ! configure_notary_auth
}

redaction_unset_prints_raw() {
  unset REDACT_IDENTITY_OUTPUT RUNNER_TEMP
  local output
  output="$(print_sensitive_or_record 'notary output' 'TeamIdentifier=secret-team' 2>&1)"
  [[ "$output" == *'TeamIdentifier=secret-team'* ]]
}

redaction_enabled_records_raw() {
  REDACT_IDENTITY_OUTPUT=1
  RUNNER_TEMP="$TMP_DIR/runner"
  mkdir -p "$RUNNER_TEMP"
  local output diagnostics mode
  output="$(print_sensitive_or_record 'notary output' 'TeamIdentifier=secret-team' 2>&1)"
  diagnostics="$RUNNER_TEMP/release-diagnostics.log"
  mode="$(stat -f '%Lp' "$diagnostics")"
  [[ "$output" != *'TeamIdentifier=secret-team'* ]] &&
    [[ "$output" == *'notary output'* ]] &&
    [[ "$(<"$diagnostics")" == *'TeamIdentifier=secret-team'* ]] &&
    [[ "$mode" == '600' ]]
}

assert_ok 'stable version exposes base and prerelease state' \
  version_state_is '1.2.3' '1.2.3' 'false'
assert_ok 'prerelease version exposes base and prerelease state' \
  version_state_is '1.2.3-beta.1' '1.2.3' 'true'
assert_ok 'hyphenated prerelease identifier is accepted' \
  version_state_is '0.0.1-rc-1' '0.0.1' 'true'
assert_fails 'major version with leading zero is rejected' \
  validate_release_version '01.2.3'
assert_fails 'minor version with leading zero is rejected' \
  validate_release_version '1.02.3'
assert_fails 'patch version with leading zero is rejected' \
  validate_release_version '1.2.03'
assert_fails 'short version is rejected' validate_release_version '1.2'
assert_fails 'empty prerelease is rejected' validate_release_version '1.2.3-'
assert_fails 'build metadata is rejected' validate_release_version '1.2.3+4'
assert_fails 'slash in version is rejected' validate_release_version '1.2.3/foo'
assert_fails 'space in version is rejected' validate_release_version '1.2.3 beta'

printf 'version: 1.2.3+4\n' >"$TMP_DIR/pubspec.yaml"
assert_ok 'canonical pubspec version exposes base and build number' \
  pubspec_state_is "$TMP_DIR/pubspec.yaml" '1.2.3' '4'
printf 'version: 1.2.3\n' >"$TMP_DIR/missing-build.yaml"
assert_fails 'pubspec version without build number is rejected' \
  parse_pubspec_version "$TMP_DIR/missing-build.yaml"
printf 'version: 1.2.3+4\nversion: 1.2.4+5\n' >"$TMP_DIR/duplicate.yaml"
assert_fails 'duplicate pubspec version is rejected' \
  parse_pubspec_version "$TMP_DIR/duplicate.yaml"
printf 'version: 1.2.3+0\n' >"$TMP_DIR/zero-build.yaml"
assert_fails 'zero pubspec build number is rejected' \
  parse_pubspec_version "$TMP_DIR/zero-build.yaml"
printf 'version: 1.2.3-beta.1+4\n' >"$TMP_DIR/prerelease.yaml"
assert_fails 'prerelease pubspec version is rejected' \
  parse_pubspec_version "$TMP_DIR/prerelease.yaml"

printf '<sparkle:version>7</sparkle:version>\n' >"$TMP_DIR/appcast.xml"
printf '<sparkle:version>9</sparkle:version>\n' >"$TMP_DIR/appcast-beta.xml"
assert_ok 'combined stable and beta feeds select numeric maximum' \
  max_feed_version "$TMP_DIR/appcast.xml" "$TMP_DIR/appcast-beta.xml"
assert_eq 'combined stable and beta feeds produce 9' '9' "$FEED_MAX_VERSION"
assert_ok 'absent feeds succeed' max_feed_version "$TMP_DIR/missing.xml"
assert_eq 'absent feeds produce no maximum' '' "$FEED_MAX_VERSION"
printf '<sparkle:version>abc</sparkle:version>\n' >"$TMP_DIR/malformed.xml"
assert_fails 'non-decimal sparkle version is rejected' \
  max_feed_version "$TMP_DIR/malformed.xml"

unset APPCAST_OUTPUT_FILENAME
assert_ok 'unset appcast output selects default' select_appcast_output "$TMP_DIR/dist"
assert_eq 'unset appcast output path is default' "$TMP_DIR/dist/appcast.xml" "$APPCAST_FILE"
APPCAST_OUTPUT_FILENAME='appcast.xml'
assert_ok 'explicit stable appcast output is accepted' select_appcast_output "$TMP_DIR/dist"
assert_eq 'explicit stable appcast output path is default' "$TMP_DIR/dist/appcast.xml" "$APPCAST_FILE"
APPCAST_OUTPUT_FILENAME='appcast-beta.xml'
assert_ok 'beta appcast output is accepted' select_appcast_output "$TMP_DIR/dist"
assert_eq 'beta appcast output path is selected' "$TMP_DIR/dist/appcast-beta.xml" "$APPCAST_FILE"
APPCAST_OUTPUT_FILENAME='../feed.xml'
assert_fails 'unsafe appcast output is rejected' select_appcast_output "$TMP_DIR/dist"

assert_ok 'no P8 values select the notary keychain profile' notary_profile_is
assert_ok 'all P8 values select exact notary arguments' notary_p8_is
assert_ok 'partial P8 configuration is rejected' notary_partial_fails
assert_ok 'two-part P8 configuration is rejected' notary_two_partials_fail

assert_ok 'unredacted diagnostics print sensitive output' redaction_unset_prints_raw
assert_ok 'redacted diagnostics record raw output privately' redaction_enabled_records_raw

printf 'release_lib: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
