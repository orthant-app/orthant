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
  # /usr/bin/stat explicitly: Homebrew coreutils shadows `stat` on PATH for many
  # macOS developers, and GNU stat reads -f as "filesystem status", so the bare
  # form silently returns filesystem info instead of a permission mode and this
  # assertion fails on a dev machine while passing on a clean CI runner.
  # test_release_workflow.sh avoids this by pinning PATH; this suite does not.
  mode="$(/usr/bin/stat -f '%Lp' "$diagnostics")"
  [[ "$output" != *'TeamIdentifier=secret-team'* ]] &&
    [[ "$output" == *'notary output'* ]] &&
    [[ "$(<"$diagnostics")" == *'TeamIdentifier=secret-team'* ]] &&
    [[ "$mode" == '600' ]]
}

redaction_without_runner_temp_fails() {
  REDACT_IDENTITY_OUTPUT=1
  unset RUNNER_TEMP
  ! print_sensitive_or_record 'notary output' 'TeamIdentifier=secret-team'
}

setup_redacted_release_fixture() {
  [[ -n "${REDACT_FIXTURE_ROOT-}" ]] && return 0

  REDACT_FIXTURE_ROOT="$TMP_DIR/WORKSPACE_MARKER-release-fixture"
  REDACT_FIXTURE_BIN="$REDACT_FIXTURE_ROOT/stub-bin"
  mkdir -p "$REDACT_FIXTURE_ROOT/tool/ci" \
    "$REDACT_FIXTURE_ROOT/macos/Runner" "$REDACT_FIXTURE_BIN" \
    "$REDACT_FIXTURE_ROOT/build/spm/artifacts/sparkle/Sparkle/bin"
  cp "$SCRIPT_DIR/../release.sh" "$REDACT_FIXTURE_ROOT/tool/release.sh"
  cp "$LIB" "$REDACT_FIXTURE_ROOT/tool/ci/release_lib.sh"
  printf 'version: 1.2.3+4\n' >"$REDACT_FIXTURE_ROOT/pubspec.yaml"
  printf 'EXPECTED_TEAM=TEAM_MARKER\n' >"$REDACT_FIXTURE_ROOT/tool/release.local"
  : >"$REDACT_FIXTURE_ROOT/macos/Runner/Release.entitlements"

  cat >"$REDACT_FIXTURE_BIN/security" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '1) CERT_MARKER Developer ID Application'
EOF
  # Writes an Info.plist as well as the bundle, because a real build does and
  # release.sh stamps the release name into it before signing. `plutil` is not
  # stubbed, so that stamp is genuinely exercised here rather than mocked.
  cat >"$REDACT_FIXTURE_BIN/flutter" <<'EOF'
#!/usr/bin/env bash
app=build/macos/Build/Products/Release/Orthant.app
mkdir -p "$app/Contents/Frameworks/Injected.framework"
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0">' \
  '<dict>' \
  '<key>CFBundleShortVersionString</key><string>1.2.3</string>' \
  '<key>CFBundleVersion</key><string>4</string>' \
  '</dict>' \
  '</plist>' >"$app/Contents/Info.plist"
EOF
  cat >"$REDACT_FIXTURE_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'CODESIGN_RAW CERT_MARKER TEAM_MARKER WORKSPACE_MARKER' >&2
if [[ "${1-}" == '-dv' ]]; then
  printf '%s\n' 'Identifier=app.orthant.orthant' 'TeamIdentifier=TEAM_MARKER' >&2
  exit 0
fi
if [[ "${FAIL_CODESIGN_VERIFY-}" == 1 && "${1-}" == '--verify' ]]; then
  exit 9
fi
EOF
  cat >"$REDACT_FIXTURE_BIN/spctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'SPCTL_RAW CERT_MARKER TEAM_MARKER WORKSPACE_MARKER accepted source=Notarized Developer ID'
EOF
  cat >"$REDACT_FIXTURE_BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == notarytool && "${2-}" == submit ]]; then
  printf '%s\n' 'NOTARY_RAW TEAM_MARKER WORKSPACE_MARKER' \
    '  id: 12345678-1234-1234-1234-123456789abc' '  status: Accepted'
fi
if [[ "${1-}" == stapler ]]; then
  printf 'STAPLER_RAW WORKSPACE_MARKER'
  printf ' %s' "$@"
  printf '\n'
  if [[ "${FAIL_STAPLER_VALIDATE-}" == 1 && "${2-}" == validate ]]; then
    exit 11
  fi
fi
EOF
  cat >"$REDACT_FIXTURE_BIN/ditto" <<'EOF'
#!/usr/bin/env bash
last=''
for arg in "$@"; do last="$arg"; done
if [[ "${1-}" == '-c' ]]; then
  : >"$last"
else
  mkdir -p "$last"
fi
EOF
  cat >"$REDACT_FIXTURE_BIN/hdiutil" <<'EOF'
#!/usr/bin/env bash
last=''
for arg in "$@"; do last="$arg"; done
: >"$last"
EOF
  cat >"$REDACT_FIXTURE_BIN/xcodebuild" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"$REDACT_FIXTURE_ROOT/build/spm/artifacts/sparkle/Sparkle/bin/sign_update" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'sparkle-signature'
EOF
  cat >"$REDACT_FIXTURE_ROOT/build/spm/artifacts/sparkle/Sparkle/bin/generate_appcast" <<'EOF'
#!/usr/bin/env bash
output=''
dist=''
while (( $# > 0 )); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    *) dist="$1"; shift ;;
  esac
done
[[ -n "$output" ]] || output="$dist/appcast.xml"
if [[ "${BAD_APPCAST-}" == 1 ]]; then
  printf '%s\n' '<item><enclosure/><sparkle:version>4</sparkle:version></item>' >"$output"
else
  printf '%s\n' '<item><enclosure sparkle:edSignature="signed"/><sparkle:version>4</sparkle:version></item>' >"$output"
fi
EOF
  chmod +x "$REDACT_FIXTURE_BIN"/* \
    "$REDACT_FIXTURE_ROOT/build/spm/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$REDACT_FIXTURE_ROOT/build/spm/artifacts/sparkle/Sparkle/bin/generate_appcast"
}

run_redacted_release_fixture() {
  local case_name="$1"
  local bad_appcast=0 fail_codesign_verify=0 fail_stapler_validate=0
  local release_args=()
  case "$case_name" in
    bad-appcast) bad_appcast=1 ;;
    verify-failure) fail_codesign_verify=1; release_args=(--sign-only) ;;
    stapler-failure) fail_stapler_validate=1 ;;
    *) return 1 ;;
  esac
  setup_redacted_release_fixture || return 1
  REDACT_FIXTURE_RUNNER_TEMP="$REDACT_FIXTURE_ROOT/runner-$case_name"
  rm -rf "$REDACT_FIXTURE_RUNNER_TEMP" \
    "$REDACT_FIXTURE_ROOT/build/dist" "$REDACT_FIXTURE_ROOT/build/macos"
  if REDACT_FIXTURE_OUTPUT="$(env \
      PATH="$REDACT_FIXTURE_BIN:$PATH" \
      REDACT_IDENTITY_OUTPUT=1 \
      RUNNER_TEMP="$REDACT_FIXTURE_RUNNER_TEMP" \
      SIGN_IDENTITY=CERT_MARKER \
      SPARKLE_ED_KEY_FILE="$REDACT_FIXTURE_ROOT/KEY_MARKER.pem" \
      APPCAST_DOWNLOAD_URL_PREFIX='https://KEY_MARKER.example/v1.2.3/' \
      APPCAST_OUTPUT_FILENAME=appcast-beta.xml \
      INCLUDE_BETA_APPCAST_HISTORY=1 \
      NOTARY_KEY_FILE="$REDACT_FIXTURE_ROOT/KEY_MARKER.p8" \
      NOTARY_KEY_ID=KEY_MARKER \
      NOTARY_ISSUER=TEAM_MARKER \
      BAD_APPCAST="$bad_appcast" \
      FAIL_CODESIGN_VERIFY="$fail_codesign_verify" \
      FAIL_STAPLER_VALIDATE="$fail_stapler_validate" \
      bash "$REDACT_FIXTURE_ROOT/tool/release.sh" 1.2.3-beta.1 ${release_args[@]+"${release_args[@]}"} 2>&1)"; then
    REDACT_FIXTURE_RC=0
  else
    REDACT_FIXTURE_RC=$?
  fi
  REDACT_FIXTURE_DIAGNOSTICS="$REDACT_FIXTURE_RUNNER_TEMP/release-diagnostics.log"
}

redacted_release_stamps_the_release_name() {
  # The pre-release label is the whole point: a bundle built for 1.2.3-beta.1
  # has CFBundleShortVersionString "1.2.3" and cannot say which beta it is.
  # `plutil` is not stubbed in this fixture, so this exercises the real write
  # and the real read-back.
  run_redacted_release_fixture bad-appcast || return 1
  local plist stamped
  plist="$REDACT_FIXTURE_ROOT/build/macos/Build/Products/Release/Orthant.app/Contents/Info.plist"
  [[ -f "$plist" ]] || return 1
  stamped="$(plutil -extract ORTHANTReleaseName raw "$plist")" || return 1
  [[ "$stamped" == '1.2.3-beta.1' ]]
}

redacted_release_hides_sensitive_markers() {
  run_redacted_release_fixture bad-appcast || return 1
  (( REDACT_FIXTURE_RC != 0 )) &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *CERT_MARKER* ]] &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *TEAM_MARKER* ]] &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *KEY_MARKER* ]] &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *WORKSPACE_MARKER* ]]
}

redacted_release_records_private_diagnostics() {
  local diagnostics mode
  diagnostics="$REDACT_FIXTURE_DIAGNOSTICS"
  [[ -f "$diagnostics" ]] || return 1
  # /usr/bin/stat explicitly: Homebrew coreutils shadows `stat` on PATH for many
  # macOS developers, and GNU stat reads -f as "filesystem status", so the bare
  # form silently returns filesystem info instead of a permission mode and this
  # assertion fails on a dev machine while passing on a clean CI runner.
  # test_release_workflow.sh avoids this by pinning PATH; this suite does not.
  mode="$(/usr/bin/stat -f '%Lp' "$diagnostics")"
  [[ "$(<"$diagnostics")" == *CERT_MARKER* ]] &&
    [[ "$(<"$diagnostics")" == *TEAM_MARKER* ]] &&
    [[ "$(<"$diagnostics")" == *KEY_MARKER* ]] &&
    [[ "$(<"$diagnostics")" == *WORKSPACE_MARKER* ]] &&
    [[ "$(<"$diagnostics")" == *STAPLER_RAW* ]] &&
    [[ "$mode" == 600 ]]
}

redacted_codesign_verification_failure_is_fatal() {
  run_redacted_release_fixture verify-failure || return 1
  (( REDACT_FIXTURE_RC != 0 )) &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *CERT_MARKER* ]] &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *TEAM_MARKER* ]] &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *KEY_MARKER* ]] &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *WORKSPACE_MARKER* ]] &&
    [[ "$(<"$REDACT_FIXTURE_DIAGNOSTICS")" == *CODESIGN_RAW* ]]
}

redacted_stapler_validation_failure_is_fatal() {
  run_redacted_release_fixture stapler-failure || return 1
  (( REDACT_FIXTURE_RC != 0 )) &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *STAPLER_RAW* ]] &&
    [[ "$REDACT_FIXTURE_OUTPUT" != *WORKSPACE_MARKER* ]] &&
    [[ "$(<"$REDACT_FIXTURE_DIAGNOSTICS")" == *STAPLER_RAW* ]] &&
    [[ "$(<"$REDACT_FIXTURE_DIAGNOSTICS")" == *WORKSPACE_MARKER* ]]
}

sparkle_args_without_output_flag() {
  unset APPCAST_OUTPUT_FILENAME SPARKLE_ED_KEY_FILE APPCAST_DOWNLOAD_URL_PREFIX
  select_appcast_output "$TMP_DIR/dist" &&
    configure_sparkle_args &&
    [[ "${#SIGN_UPDATE_ARGS[@]}" == 0 ]] &&
    [[ "${#GENERATE_APPCAST_ARGS[@]}" == 0 ]]
}

sparkle_args_with_explicit_stable_output() {
  APPCAST_OUTPUT_FILENAME='appcast.xml'
  unset SPARKLE_ED_KEY_FILE APPCAST_DOWNLOAD_URL_PREFIX
  select_appcast_output "$TMP_DIR/dist" &&
    configure_sparkle_args &&
    [[ "${GENERATE_APPCAST_ARGS[*]}" == "-o $TMP_DIR/dist/appcast.xml" ]]
}

sparkle_args_with_explicit_beta_output() {
  APPCAST_OUTPUT_FILENAME='appcast-beta.xml'
  unset SPARKLE_ED_KEY_FILE APPCAST_DOWNLOAD_URL_PREFIX
  select_appcast_output "$TMP_DIR/dist" &&
    configure_sparkle_args &&
    [[ "${GENERATE_APPCAST_ARGS[*]}" == "-o $TMP_DIR/dist/appcast-beta.xml" ]]
}

sparkle_args_with_key_and_download_prefix() {
  APPCAST_OUTPUT_FILENAME='appcast-beta.xml'
  SPARKLE_ED_KEY_FILE='/tmp/sparkle.key'
  APPCAST_DOWNLOAD_URL_PREFIX='https://example.test/v1.2.3/'
  select_appcast_output "$TMP_DIR/dist" &&
    configure_sparkle_args &&
    [[ "${SIGN_UPDATE_ARGS[*]}" == '-f /tmp/sparkle.key' ]] &&
    [[ "${GENERATE_APPCAST_ARGS[*]}" == "--ed-key-file /tmp/sparkle.key --download-url-prefix https://example.test/v1.2.3/ -o $TMP_DIR/dist/appcast-beta.xml" ]]
}

sparkle_commands_with_ci_inputs_are_exact() {
  APPCAST_OUTPUT_FILENAME='appcast-beta.xml'
  SPARKLE_ED_KEY_FILE='/tmp/sparkle.key'
  APPCAST_DOWNLOAD_URL_PREFIX='https://example.test/v1.2.3/'
  select_appcast_output '/tmp/dist' &&
    configure_sparkle_args || return 1

  local sign_command=(sign_update ${SIGN_UPDATE_ARGS[@]+"${SIGN_UPDATE_ARGS[@]}"} /tmp/Orthant-1.2.3.dmg)
  local generate_command=(generate_appcast ${GENERATE_APPCAST_ARGS[@]+"${GENERATE_APPCAST_ARGS[@]}"} /tmp/dist)
  [[ "${sign_command[*]}" == 'sign_update -f /tmp/sparkle.key /tmp/Orthant-1.2.3.dmg' ]] &&
    [[ "${generate_command[*]}" == 'generate_appcast --ed-key-file /tmp/sparkle.key --download-url-prefix https://example.test/v1.2.3/ -o /tmp/dist/appcast-beta.xml /tmp/dist' ]]
}

sparkle_commands_without_ci_inputs_are_legacy() {
  unset APPCAST_OUTPUT_FILENAME SPARKLE_ED_KEY_FILE APPCAST_DOWNLOAD_URL_PREFIX
  select_appcast_output '/tmp/dist' &&
    configure_sparkle_args || return 1

  local sign_command=(sign_update ${SIGN_UPDATE_ARGS[@]+"${SIGN_UPDATE_ARGS[@]}"} /tmp/Orthant-1.2.3.dmg)
  local generate_command=(generate_appcast ${GENERATE_APPCAST_ARGS[@]+"${GENERATE_APPCAST_ARGS[@]}"} /tmp/dist)
  [[ "${sign_command[*]}" == 'sign_update /tmp/Orthant-1.2.3.dmg' ]] &&
    [[ "${generate_command[*]}" == 'generate_appcast /tmp/dist' ]] &&
    [[ "$APPCAST_FILE" == '/tmp/dist/appcast.xml' ]]
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
printf '<sparkle:version>\nabc\n</sparkle:version>\n' >"$TMP_DIR/malformed-multiline.xml"
assert_fails 'multiline non-decimal sparkle version is rejected' \
  max_feed_version "$TMP_DIR/malformed-multiline.xml"

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

assert_ok 'unset appcast output adds no Sparkle output flag' sparkle_args_without_output_flag
assert_ok 'explicit stable appcast output adds Sparkle output flag' sparkle_args_with_explicit_stable_output
assert_ok 'explicit beta appcast output adds Sparkle output flag' sparkle_args_with_explicit_beta_output
assert_ok 'Sparkle key and download prefix arguments are preserved' sparkle_args_with_key_and_download_prefix
assert_ok 'CI Sparkle inputs render exact commands' sparkle_commands_with_ci_inputs_are_exact
assert_ok 'unset Sparkle inputs preserve legacy commands and feed' sparkle_commands_without_ci_inputs_are_legacy

assert_ok 'unredacted diagnostics print sensitive output' redaction_unset_prints_raw
assert_ok 'redacted diagnostics record raw output privately' redaction_enabled_records_raw
assert_ok 'redacted diagnostics require RUNNER_TEMP' redaction_without_runner_temp_fails
assert_ok 'the release name, label and all, is stamped into the bundle' \
  redacted_release_stamps_the_release_name
assert_ok 'redacted release output hides certificate, Team, key, and workspace markers' \
  redacted_release_hides_sensitive_markers
assert_ok 'redacted release stores complete mode-600 diagnostics' \
  redacted_release_records_private_diagnostics
assert_ok 'redacted codesign verification failure remains fatal' \
  redacted_codesign_verification_failure_is_fatal
assert_ok 'redacted stapler validation failure remains fatal' \
  redacted_stapler_validation_failure_is_fatal

# tool/release.sh expands SIGN_UPDATE_ARGS and GENERATE_APPCAST_ARGS, which
# configure_sparkle_args leaves EMPTY on the legacy path, under `set -euo
# pipefail`. Before bash 4.4 that is an unbound-variable abort, and macOS ships
# 3.2 as /bin/bash, including on the GitHub runner. The failure would land
# after the build and after signing.
#
# Source-level, deliberately: the release fixture always supplies Sparkle
# inputs, so no behavioural test here ever reaches the empty case. This pins
# the `[@]+` guard itself and fails the moment either expansion is written the
# bare way again. Weaker than a behavioural test, and it is the honest extent
# of the coverage.
RELEASE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tool/release.sh"
for arr in SIGN_UPDATE_ARGS GENERATE_APPCAST_ARGS; do
  assert_ok "release.sh guards possibly-empty $arr for bash 3.2" \
    grep -qF -- "${arr}[@]+" "$RELEASE_SH"
done

printf 'release_lib: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
