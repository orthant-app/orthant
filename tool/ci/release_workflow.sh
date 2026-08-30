#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/release_lib.sh"

workflow_error() {
  printf 'release_workflow: %s\n' "$*" >&2
  return 1
}

require_mode() {
  case "${1-}" in
    stable|beta|dry-run) ;;
    *) workflow_error "invalid mode: ${1-}" || return 1 ;;
  esac
}

feed_url() {
  local repo="$1" name="$2" owner project
  owner="${repo%%/*}"
  project="${repo#*/}"
  [[ -n "$owner" && -n "$project" && "$owner" != "$project" ]] ||
    workflow_error "invalid repository: $repo" || return 1
  printf 'https://%s.github.io/%s/%s?run=%s-%s\n' \
    "$owner" "$project" "$name" "${GITHUB_RUN_ID-}" "${GITHUB_RUN_ATTEMPT-}"
}

fetch_feed() {
  local url="$1" destination="$2" temporary status_file status curl_exit
  mkdir -p "$(dirname "$destination")" || return 1
  temporary="$(mktemp "${destination}.tmp.XXXXXX")" || return 1
  status_file="$(mktemp "${destination}.status.XXXXXX")" || {
    rm -f "$temporary"
    return 1
  }

  curl --location --silent --show-error \
    --connect-timeout 15 --max-time 60 \
    --header 'Cache-Control: no-cache' \
    --output "$temporary" --write-out '%{http_code}' \
    "$url" >"$status_file"
  curl_exit=$?
  status="$(<"$status_file")"
  rm -f "$status_file"

  if (( curl_exit != 0 )); then
    rm -f "$temporary"
    workflow_error "feed transport failed for $url (curl exit $curl_exit)" || return 1
  fi
  case "$status" in
    200)
      mv "$temporary" "$destination" || return 1
      ;;
    404)
      rm -f "$temporary" "$destination"
      ;;
    *)
      rm -f "$temporary"
      workflow_error "feed returned HTTP ${status:-unknown}: $url" || return 1
      ;;
  esac
}

query_release_state() {
  local repo="$1" tag="$2" response exit_code status body
  local old_umask
  old_umask="$(umask)"
  umask 077
  response="$(mktemp "${TMPDIR:-/tmp}/orthant-release-api.XXXXXX")" || {
    umask "$old_umask"
    return 1
  }
  umask "$old_umask"
  chmod 600 "$response" || {
    rm -f "$response"
    return 1
  }

  gh api --include "repos/$repo/releases/tags/$tag" >"$response"
  exit_code=$?
  status="$(awk '
    {
      line = $0
      sub(/\r$/, "", line)
      split(line, fields, /[[:space:]]+/)
      if (fields[1] ~ /^HTTP\/[0-9.]+$/ && fields[2] ~ /^[0-9][0-9][0-9]$/) {
        status = fields[2]
      }
    }
    END { print status }
  ' "$response")"

  if [[ "$status" == 404 ]]; then
    rm -f "$response"
    RELEASE_QUERY_STATE=absent
    return 0
  fi
  if (( exit_code != 0 )) || [[ "$status" != 200 ]]; then
    rm -f "$response"
    workflow_error "release API failed for $tag (HTTP ${status:-unknown}, exit $exit_code)" || return 1
  fi

  body="$(awk '
    body { print }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line == "") body = 1
    }
  ' "$response")"
  rm -f "$response"
  if [[ "$body" =~ \"draft\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
    if [[ "${BASH_REMATCH[1]}" == true ]]; then
      RELEASE_QUERY_STATE=draft
    else
      RELEASE_QUERY_STATE=public
    fi
  else
    workflow_error "release API response omitted boolean draft state for $tag" || return 1
  fi
}

metadata() {
  local event="$1" ref_type="$2" ref_name="$3" repo="$4" output="$5"
  local version base prerelease publish mode tag
  parse_pubspec_version pubspec.yaml || return 1

  publish=false
  mode=dry-run
  version="$PUBSPEC_BASE_VERSION"
  base="$PUBSPEC_BASE_VERSION"
  prerelease=false

  if [[ "$event" == push && "$ref_type" == tag ]]; then
    version="${ref_name#v}"
    validate_release_version "$version" || return 1
    base="$RELEASE_BASE_VERSION"
    prerelease="$RELEASE_PRERELEASE"
    [[ "$base" == "$PUBSPEC_BASE_VERSION" ]] ||
      workflow_error "tag base $base does not match pubspec $PUBSPEC_BASE_VERSION" || return 1
    git merge-base --is-ancestor HEAD origin/main ||
      workflow_error 'tag commit is not ancestral to origin/main' || return 1
    tag="v$version"
    query_release_state "$repo" "$tag" || return 1
    [[ "$RELEASE_QUERY_STATE" != public ]] ||
      workflow_error "release $tag is already public" || return 1
    publish=true
    if [[ "$prerelease" == true ]]; then
      mode=beta
    else
      mode=stable
    fi
  fi

  {
    printf 'version=%s\n' "$version"
    printf 'base_version=%s\n' "$base"
    printf 'prerelease=%s\n' "$prerelease"
    printf 'publish=%s\n' "$publish"
    printf 'mode=%s\n' "$mode"
  } >>"$output"
}

feed_encloses_release() {
  local file="$1" tag="$2" content enclosure needle
  [[ -f "$file" ]] || return 1
  content="$(tr '\n' ' ' <"$file")" || return 1
  needle="/releases/download/$tag/"
  while [[ "$content" == *'<enclosure'* ]]; do
    content="${content#*<enclosure}"
    [[ "$content" == *'>'* ]] || return 1
    enclosure="${content%%>*}"
    [[ "$enclosure" == *"$needle"* ]] && return 0
    content="${content#*>}"
  done
  return 1
}

check_settled() {
  local repo="$1" prior temporary stable_url beta_url
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/orthant-settled.XXXXXX")" || return 1
  prior="$(gh release list --repo "$repo" --exclude-drafts --limit 1 \
    --json tagName --jq '.[0].tagName // ""')" || {
    rm -rf "$temporary"
    workflow_error 'could not query previous public release' || return 1
  }
  stable_url="$(feed_url "$repo" appcast.xml)" || {
    rm -rf "$temporary"
    return 1
  }
  beta_url="$(feed_url "$repo" appcast-beta.xml)" || {
    rm -rf "$temporary"
    return 1
  }
  fetch_feed "$stable_url" "$temporary/appcast.xml" || {
    rm -rf "$temporary"
    return 1
  }
  fetch_feed "$beta_url" "$temporary/appcast-beta.xml" || {
    rm -rf "$temporary"
    return 1
  }

  if [[ -z "$prior" ]]; then
    if [[ -e "$temporary/appcast.xml" || -e "$temporary/appcast-beta.xml" ]]; then
      rm -rf "$temporary"
      workflow_error 'Pages deployment unsettled' || return 1
    fi
    rm -rf "$temporary"
    return 0
  fi
  if feed_encloses_release "$temporary/appcast.xml" "$prior" ||
     feed_encloses_release "$temporary/appcast-beta.xml" "$prior"; then
    rm -rf "$temporary"
    return 0
  fi
  rm -rf "$temporary"
  workflow_error 'Pages deployment unsettled' || return 1
}

restore() {
  local mode="$1" repo="$2" dist="$3" stable_url beta_url tags tag
  require_mode "$mode" || return 1
  mkdir -p "$dist" || return 1
  find "$dist" -maxdepth 1 -type f \( \
    -name 'appcast.xml' -o -name 'appcast-beta.xml' -o \
    -name 'Orthant-*.dmg' -o -name '*.delta' \
  \) -delete || return 1
  stable_url="$(feed_url "$repo" appcast.xml)" || return 1
  beta_url="$(feed_url "$repo" appcast-beta.xml)" || return 1
  fetch_feed "$stable_url" "$dist/appcast.xml" || return 1
  fetch_feed "$beta_url" "$dist/appcast-beta.xml" || return 1

  if [[ "$mode" == stable || "$mode" == dry-run ]]; then
    tags="$(gh release list --exclude-drafts --exclude-pre-releases --limit 3 \
      --repo "$repo" --json tagName --jq '.[].tagName')" ||
      workflow_error 'could not list stable releases for restore' || return 1
    while IFS= read -r tag; do
      [[ -n "$tag" ]] || continue
      gh release download "$tag" --repo "$repo" --pattern 'Orthant-*.dmg' --dir "$dist" ||
        workflow_error "could not restore assets for $tag" || return 1
    done <<<"$tags"
  fi
}

assemble_pages() {
  local mode="$1" dist="$2" site="$3"
  require_mode "$mode" || return 1
  [[ -n "$site" && "$site" != / && "$site" != . ]] ||
    workflow_error "unsafe Pages site path: $site" || return 1
  rm -rf "$site" || return 1
  mkdir -p "$site" || return 1
  case "$mode" in
    stable|dry-run)
      [[ -f "$dist/appcast.xml" ]] ||
        workflow_error 'stable appcast is missing' || return 1
      cp "$dist/appcast.xml" "$site/appcast.xml" || return 1
      cp "$dist/appcast.xml" "$site/appcast-beta.xml" || return 1
      ;;
    beta)
      [[ -f "$dist/appcast-beta.xml" ]] ||
        workflow_error 'beta appcast is missing' || return 1
      cp "$dist/appcast-beta.xml" "$site/appcast-beta.xml" || return 1
      if [[ -f "$dist/appcast.xml" ]]; then
        cp "$dist/appcast.xml" "$site/appcast.xml" || return 1
      fi
      ;;
  esac
}

asset_name_expected() {
  local candidate="$1"
  shift
  local expected
  for expected in "$@"; do
    [[ "$candidate" == "$expected" ]] && return 0
  done
  return 1
}

query_asset_names() {
  local repo="$1" tag="$2" output="$3"
  gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' >"$output" ||
    workflow_error "could not query draft assets for $tag" || return 1
}

publish() {
  local repo="$1" version="$2" prerelease="$3" dist="$4" tag path name actual
  local temporary actual_file expected_file actual_sorted expected_sorted
  local -a assets deltas expected_names create_args edit_args
  validate_release_version "$version" || return 1
  [[ "$prerelease" == true || "$prerelease" == false ]] ||
    workflow_error "invalid prerelease value: $prerelease" || return 1
  [[ "$prerelease" == "$RELEASE_PRERELEASE" ]] ||
    workflow_error "prerelease value does not match version: $version" || return 1

  assets=("$dist/Orthant-$version.dmg")
  deltas=()
  shopt -s nullglob
  deltas=("$dist"/*.delta)
  shopt -u nullglob
  if [[ -n "${deltas[0]+present}" ]]; then
    assets+=("${deltas[@]}")
  fi
  for path in "${assets[@]}"; do
    [[ -f "$path" ]] || workflow_error "release asset is missing: $path" || return 1
  done

  tag="v$version"
  query_release_state "$repo" "$tag" || return 1
  case "$RELEASE_QUERY_STATE" in
    absent)
      create_args=(release create "$tag" --draft --verify-tag --generate-notes)
      if [[ "$prerelease" == true ]]; then
        create_args+=(--prerelease --latest=false)
      fi
      create_args+=(--repo "$repo")
      gh "${create_args[@]}" || workflow_error "could not create draft $tag" || return 1
      ;;
    draft) ;;
    public) workflow_error "release $tag is already public" || return 1 ;;
    *) workflow_error "indeterminate release state for $tag" || return 1 ;;
  esac

  expected_names=()
  for path in "${assets[@]}"; do
    expected_names+=("$(basename "$path")")
  done
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/orthant-assets.XXXXXX")" || return 1
  actual_file="$temporary/actual"
  expected_file="$temporary/expected"
  actual_sorted="$temporary/actual.sorted"
  expected_sorted="$temporary/expected.sorted"
  query_asset_names "$repo" "$tag" "$actual_file" || {
    rm -rf "$temporary"
    return 1
  }
  while IFS= read -r actual; do
    [[ -n "$actual" ]] || continue
    if ! asset_name_expected "$actual" "${expected_names[@]}"; then
      gh release delete-asset "$tag" "$actual" --yes --repo "$repo" || {
        rm -rf "$temporary"
        workflow_error "could not delete stale asset $actual" || return 1
      }
    fi
  done <"$actual_file"

  gh release upload "$tag" "${assets[@]}" --clobber --repo "$repo" || {
    rm -rf "$temporary"
    workflow_error "could not upload assets for $tag" || return 1
  }
  query_asset_names "$repo" "$tag" "$actual_file" || {
    rm -rf "$temporary"
    return 1
  }
  : >"$expected_file"
  for name in "${expected_names[@]}"; do
    printf '%s\n' "$name" >>"$expected_file"
  done
  LC_ALL=C sort "$actual_file" >"$actual_sorted" || {
    rm -rf "$temporary"
    return 1
  }
  LC_ALL=C sort "$expected_file" >"$expected_sorted" || {
    rm -rf "$temporary"
    return 1
  }
  if ! cmp -s "$actual_sorted" "$expected_sorted"; then
    rm -rf "$temporary"
    workflow_error "draft asset set does not exactly match expected assets for $tag" || return 1
  fi
  rm -rf "$temporary" || return 1

  edit_args=(release edit "$tag" --draft=false "--prerelease=$prerelease")
  if [[ "$prerelease" == true ]]; then
    edit_args+=(--latest=false)
  fi
  edit_args+=(--repo "$repo")
  exec gh "${edit_args[@]}"
}

command="${1-}"
[[ $# -gt 0 ]] && shift
case "$command" in
  metadata)
    [[ $# -eq 5 ]] || workflow_error 'usage: metadata EVENT REF_TYPE REF_NAME OWNER/REPO OUTPUT_FILE' || exit 2
    metadata "$@"
    ;;
  check-settled)
    [[ $# -eq 1 ]] || workflow_error 'usage: check-settled OWNER/REPO' || exit 2
    check_settled "$@"
    ;;
  restore)
    [[ $# -eq 3 ]] || workflow_error 'usage: restore MODE OWNER/REPO DIST' || exit 2
    restore "$@"
    ;;
  assemble-pages)
    [[ $# -eq 3 ]] || workflow_error 'usage: assemble-pages MODE DIST SITE' || exit 2
    assemble_pages "$@"
    ;;
  publish)
    [[ $# -eq 4 ]] || workflow_error 'usage: publish OWNER/REPO VERSION PRERELEASE DIST' || exit 2
    publish "$@"
    ;;
  *)
    workflow_error "unknown command: $command"
    exit 2
    ;;
esac
