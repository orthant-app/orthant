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

# A changelog entry's body, with YAML frontmatter stripped. Shared by
# metadata()'s early guard and publish()'s --notes-file extraction so the two
# body-blank checks can never drift apart the way the entry PATH once did.
changelog_body() {
  local entry="$1"
  awk 'BEGIN { fences = 0 }
       /^---[[:space:]]*$/ && fences < 2 { fences++; next }
       fences >= 2 { print }' "$entry"
}

require_mode() {
  case "${1-}" in
    stable|beta|dry-run) ;;
    *) workflow_error "invalid mode: ${1-}" || return 1 ;;
  esac
}

# The domain shipped in every build's SUFeedURL. Pages serves the site at this
# name once assemble_pages emits a matching CNAME.
PAGES_CUSTOM_DOMAIN="${PAGES_CUSTOM_DOMAIN:-updates.orthant.app}"

# Deliberately the custom domain rather than <owner>.github.io/<project>. Once a
# custom domain is set the github.io address only reaches the site by redirect,
# so fetching it would still "work" even if CNAME had been dropped and the real
# feed were dead — a check that passes while the thing it protects is broken.
# Fetching the canonical URL means check-settled verifies exactly what installed
# clients poll.
feed_url() {
  local name="$1"
  [[ -n "$name" ]] || workflow_error 'feed name is required' || return 1
  printf 'https://%s/%s?run=%s-%s\n' \
    "$PAGES_CUSTOM_DOMAIN" "$name" "${GITHUB_RUN_ID-}" "${GITHUB_RUN_ATTEMPT-}"
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
  local repo="$1" tag="$2" response exit_code status body draft
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
  draft="$(printf '%s\n' "$body" | python3 -c '
import json
import sys

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result

def reject_constant(value):
    raise ValueError("invalid JSON constant")

try:
    document = json.load(
        sys.stdin,
        object_pairs_hook=unique_object,
        parse_constant=reject_constant,
    )
    if type(document) is not dict or type(document.get("draft")) is not bool:
        raise ValueError("top-level draft must be boolean")
    print("true" if document["draft"] else "false")
except (TypeError, ValueError):
    sys.exit(1)
')" || workflow_error "release API response has invalid top-level draft state for $tag" || return 1
  if [[ "$draft" == true ]]; then
    RELEASE_QUERY_STATE=draft
  else
    RELEASE_QUERY_STATE=public
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

    # Fail here rather than in publish(), which runs after build, sign and
    # notarize. The changelog entry is a precondition of the release, not a
    # detail of publishing it.
    #
    # Keyed by BASE version, not the full tag: a beta (e.g. 1.0.2-beta.1) and
    # its eventual stable (1.0.2) share one entry, because a beta's release
    # notes are the upcoming release's notes and the site lists stable
    # releases only. test/site_docs_test.dart's own guard requires the
    # entry's frontmatter `version:` to equal pubspec.yaml's marketing
    # version, which never carries a "-beta.N" label — so a per-tag filename
    # could never satisfy both guards at once.
    local entry="site/src/content/changelog/$base.md"
    [[ -f "$entry" ]] ||
      workflow_error "changelog entry missing: $entry" || return 1
    changelog_body "$entry" | grep -q '[^[:space:]]' ||
      workflow_error "changelog entry has no body: $entry" || return 1
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
  local file="$1" tag="$2" needle
  [[ -f "$file" ]] || return 1
  needle="/releases/download/$tag/"
  python3 - "$file" "$needle" <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError):
    sys.exit(1)

needle = sys.argv[2]
for element in root.iter():
    if element.tag.rsplit("}", 1)[-1] != "enclosure":
        continue
    url = element.attrib.get("url")
    if isinstance(url, str) and needle in url:
        sys.exit(0)
sys.exit(1)
PY
}

check_settled() {
  local repo="$1" prior temporary stable_url beta_url
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/orthant-settled.XXXXXX")" || return 1
  prior="$(gh release list --repo "$repo" --exclude-drafts --limit 1 \
    --json tagName --jq '.[0].tagName // ""')" || {
    rm -rf "$temporary"
    workflow_error 'could not query previous public release' || return 1
  }
  stable_url="$(feed_url appcast.xml)" || {
    rm -rf "$temporary"
    return 1
  }
  beta_url="$(feed_url appcast-beta.xml)" || {
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
  stable_url="$(feed_url appcast.xml)" || return 1
  beta_url="$(feed_url appcast-beta.xml)" || return 1
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
  # A Pages deploy replaces the WHOLE site, so anything absent from this
  # directory ceases to exist at the next release — which is why both feeds are
  # copied above rather than just the one generated. CNAME is subject to the
  # same rule: without it here, the custom domain is dropped on the first
  # deploy and every installed copy's SUFeedURL starts 404ing. Emitting it on
  # every assembly is what makes the domain durable.
  printf '%s\n' "$PAGES_CUSTOM_DOMAIN" > "$site/CNAME" || return 1
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
      # The changelog entry is the single source for both the site and the
      # GitHub Release. --generate-notes would write the body from commit
      # history instead, giving one artifact two authors that can disagree.
      #
      # gh reads --notes-file VERBATIM, so the YAML frontmatter has to come off
      # first or every release body starts with `---` and `published: false`.
      # The output path is fixed rather than mktemp so the harness's call-log
      # assertions stay deterministic.
      #
      # Keyed by RELEASE_BASE_VERSION (set by validate_release_version above),
      # not $tag: see the matching comment in metadata() for why a beta and
      # its eventual stable must resolve to the same entry.
      local notes_source notes_file
      notes_source="site/src/content/changelog/$RELEASE_BASE_VERSION.md"
      [[ -f "$notes_source" ]] ||
        workflow_error "changelog entry missing: $notes_source" || return 1
      notes_file='build/dist/release-notes.md'
      mkdir -p "$(dirname "$notes_file")" || return 1
      changelog_body "$notes_source" >"$notes_file" || return 1
      # NOT `[[ -s ]]`: the extractor keeps the blank line that follows the
      # frontmatter, so a body-less entry yields a one-newline file, which is
      # non-empty and would publish a blank release body.
      grep -q '[^[:space:]]' "$notes_file" ||
        workflow_error "changelog entry has no body: $notes_source" || return 1
      create_args=(release create "$tag" --draft --verify-tag --notes-file "$notes_file")
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
