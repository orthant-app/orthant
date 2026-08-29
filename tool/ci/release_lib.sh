#!/usr/bin/env bash
# shellcheck disable=SC2034

# Shared release invariant helpers. Sourcing callers own shell options.

RELEASE_VERSION_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?$'
PUBSPEC_VERSION_RE='^version: ((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))\+([1-9][0-9]*)$'

release_lib_error() {
  printf 'release_lib: %s\n' "$*" >&2
  return 1
}

validate_release_version() {
  local version="${1-}"

  [[ "$version" =~ $RELEASE_VERSION_RE ]] ||
    release_lib_error "invalid release version: $version" || return 1

  RELEASE_BASE_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  if [[ -n "${BASH_REMATCH[4]}" ]]; then
    RELEASE_PRERELEASE=true
  else
    RELEASE_PRERELEASE=false
  fi
}

parse_pubspec_version() {
  local path="${1-}" line

  [[ -f "$path" ]] || release_lib_error "pubspec not found: $path" || return 1
  line="$(awk '/^version:/ { count += 1; line = $0 } END { if (count == 1) print line; else exit 1 }' "$path")" ||
    release_lib_error "pubspec must contain exactly one version line" || return 1
  [[ "$line" =~ $PUBSPEC_VERSION_RE ]] ||
    release_lib_error "invalid pubspec version: $line" || return 1

  PUBSPEC_BASE_VERSION="${BASH_REMATCH[1]}"
  PUBSPEC_BUILD_NUMBER="${BASH_REMATCH[5]}"
}

select_appcast_output() {
  local dist="${1-}"

  if [[ -n "${APPCAST_OUTPUT_FILENAME+x}" ]]; then
    RELEASE_APPCAST_OUTPUT_EXPLICIT=true
    case "$APPCAST_OUTPUT_FILENAME" in
      appcast.xml|appcast-beta.xml) ;;
      *) release_lib_error "invalid appcast output filename: $APPCAST_OUTPUT_FILENAME" || return 1 ;;
    esac
  else
    RELEASE_APPCAST_OUTPUT_EXPLICIT=false
    APPCAST_OUTPUT_FILENAME=appcast.xml
  fi

  APPCAST_FILE="$dist/$APPCAST_OUTPUT_FILENAME"
}

max_feed_version() {
  local file item version

  FEED_MAX_VERSION=''
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    while IFS= read -r item; do
      version="${item#<sparkle:version>}"
      version="${version%</sparkle:version>}"
      [[ "$version" =~ ^[0-9]+$ ]] ||
        release_lib_error "invalid sparkle version in $file: $version" || return 1
      if [[ -z "$FEED_MAX_VERSION" ]] || (( 10#$version > 10#$FEED_MAX_VERSION )); then
        FEED_MAX_VERSION="$version"
      fi
    done < <(grep -o '<sparkle:version>[^<]*</sparkle:version>' "$file" || true)
  done
}

configure_notary_auth() {
  local configured=0

  [[ -n "${NOTARY_KEY_FILE-}" ]] && configured=$((configured + 1))
  [[ -n "${NOTARY_KEY_ID-}" ]] && configured=$((configured + 1))
  [[ -n "${NOTARY_ISSUER-}" ]] && configured=$((configured + 1))

  case "$configured" in
    0) NOTARY_AUTH_ARGS=(--keychain-profile "${NOTARY_PROFILE-}") ;;
    3) NOTARY_AUTH_ARGS=(--key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER") ;;
    *) release_lib_error 'notary P8 configuration requires key, key id, and issuer' || return 1 ;;
  esac
}

configure_sparkle_args() {
  SIGN_UPDATE_ARGS=()
  GENERATE_APPCAST_ARGS=()

  if [[ -n "${SPARKLE_ED_KEY_FILE-}" ]]; then
    SIGN_UPDATE_ARGS=(-f "$SPARKLE_ED_KEY_FILE")
    GENERATE_APPCAST_ARGS=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
  fi
  if [[ -n "${APPCAST_DOWNLOAD_URL_PREFIX-}" ]]; then
    GENERATE_APPCAST_ARGS+=(--download-url-prefix "$APPCAST_DOWNLOAD_URL_PREFIX")
  fi
  if [[ "${RELEASE_APPCAST_OUTPUT_EXPLICIT-false}" == true ]]; then
    GENERATE_APPCAST_ARGS+=(-o "$APPCAST_FILE")
  fi
}

write_sensitive_diagnostic() {
  local label="${1-}" text="${2-}" diagnostics

  [[ -n "${RUNNER_TEMP-}" ]] ||
    release_lib_error 'RUNNER_TEMP is required for redacted diagnostics' || return 1
  diagnostics="$RUNNER_TEMP/release-diagnostics.log"
  mkdir -p "$RUNNER_TEMP" || return 1
  touch "$diagnostics" || return 1
  chmod 600 "$diagnostics" || return 1
  printf '\n[%s]\n%s\n' "$label" "$text" >>"$diagnostics"
}

print_sensitive_or_record() {
  local label="${1-}" text="${2-}"

  if [[ "${REDACT_IDENTITY_OUTPUT-}" == 1 ]]; then
    write_sensitive_diagnostic "$label" "$text" || return 1
    printf '%s details withheld; see release diagnostics\n' "$label"
  else
    printf '%s\n' "$text"
  fi
}
