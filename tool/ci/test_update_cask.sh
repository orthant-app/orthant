#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATER="$SCRIPT_DIR/update_cask.sh"
TMP_DIR="$(mktemp -d)"
TAP_ROOT="$TMP_DIR/homebrew-orthant"
PASS_COUNT=0
FAIL_COUNT=0

VERSION_ONE='1.2.3'
SHA_ONE='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
VERSION_TWO='1.2.4'
SHA_TWO='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

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

assert_file_eq() {
  local label="$1" expected="$2" actual="$3"
  if cmp -s "$expected" "$actual"; then
    pass "$label"
  else
    fail "$label (files differ: $expected $actual)"
  fi
}

write_expected_cask() {
  local destination="$1" version="$2" sha256="$3"
  cat >"$destination" <<EOF
cask "orthant" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/orthant-app/orthant/releases/download/v#{version}/Orthant-#{version}.dmg",
      verified: "github.com/orthant-app/orthant/"
  name "Orthant"
  desc "Grid-based window manager: snap windows with shortcuts or a drag-on-a-grid overlay"
  homepage "https://github.com/orthant-app/orthant"

  livecheck do
    url "https://orthant-app.github.io/orthant/appcast.xml"
    strategy :sparkle do |items|
      items.find { |item| item.channel.nil? }&.short_version
    end
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "Orthant.app"

  uninstall quit: "app.orthant.orthant"

  zap script: {
        executable: "/bin/sh",
        args: ["-c", "defaults delete app.orthant.orthant 2>/dev/null; /usr/bin/tccutil reset Accessibility app.orthant.orthant"],
        must_succeed: true,
      },
      trash: [
        "~/Library/Caches/app.orthant.orthant",
        "~/Library/HTTPStorages/app.orthant.orthant",
        "~/Library/Preferences/app.orthant.orthant.plist",
        "~/Library/Saved Application State/app.orthant.orthant.savedState",
      ]
end
EOF
}

staged_update_changes_only_values() {
  local line changes=0
  while IFS= read -r line; do
    case "$line" in
      'diff --git '*|'index '*|'--- '*|'+++ '*|'@@ '*) ;;
      "-  version \"$VERSION_ONE\""|"+  version \"$VERSION_TWO\""|\
      "-  sha256 \"$SHA_ONE\""|"+  sha256 \"$SHA_TWO\"")
        changes=$((changes + 1))
        ;;
      *) return 1 ;;
    esac
  done < <(git -C "$TAP_ROOT" diff --cached --unified=0 -- Casks/orthant.rb)
  [[ "$changes" == 4 ]]
}

rejects_without_rendering() {
  local version="$1" sha256="$2" invalid_tap="$TMP_DIR/invalid-tap"
  mkdir -p "$invalid_tap"
  if bash "$UPDATER" "$version" "$sha256" "$invalid_tap"; then
    return 1
  fi
  [[ ! -e "$invalid_tap/Casks/orthant.rb" ]]
}

rejects_empty_tap_before_mkdir() {
  local fake_bin="$TMP_DIR/empty-tap-bin" call_log="$TMP_DIR/empty-tap-mkdir.log" output
  mkdir -p "$fake_bin"
  cat >"$fake_bin/mkdir" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$EMPTY_TAP_MKDIR_LOG"
exit 99
EOF
  chmod +x "$fake_bin/mkdir"

  if output="$(env PATH="$fake_bin:$PATH" EMPTY_TAP_MKDIR_LOG="$call_log" \
    bash "$UPDATER" "$VERSION_ONE" "$SHA_ONE" '' 2>&1)"; then
    return 1
  fi
  [[ ! -s "$call_log" ]] && [[ "$output" == *'missing tap path'* ]]
}

if [[ ! -x "$UPDATER" ]]; then
  printf 'update_cask: missing or not executable: %s\n' "$UPDATER" >&2
  exit 1
fi

mkdir -p "$TAP_ROOT"
git -C "$TAP_ROOT" init -q
write_expected_cask "$TMP_DIR/expected-one.rb" "$VERSION_ONE" "$SHA_ONE"
write_expected_cask "$TMP_DIR/expected-two.rb" "$VERSION_TWO" "$SHA_TWO"

assert_ok 'renders the first stable cask' \
  bash "$UPDATER" "$VERSION_ONE" "$SHA_ONE" "$TAP_ROOT"
assert_file_eq 'first render matches the complete cask' \
  "$TMP_DIR/expected-one.rb" "$TAP_ROOT/Casks/orthant.rb"
git -C "$TAP_ROOT" add Casks/orthant.rb
assert_fails 'first staged cask is a new diff' \
  git -C "$TAP_ROOT" diff --cached --quiet
assert_ok 'commits the first rendered cask' \
  git -C "$TAP_ROOT" -c commit.gpgSign=false -c user.name='Test User' -c user.email='test@example.invalid' commit -qm 'initial cask'

assert_ok 'updates the cask for the next stable version' \
  bash "$UPDATER" "$VERSION_TWO" "$SHA_TWO" "$TAP_ROOT"
assert_file_eq 'updated render preserves the complete cask template' \
  "$TMP_DIR/expected-two.rb" "$TAP_ROOT/Casks/orthant.rb"
git -C "$TAP_ROOT" add Casks/orthant.rb
assert_ok 'update changes only version checksum and derived URL' staged_update_changes_only_values
assert_ok 'commits the updated cask' \
  git -C "$TAP_ROOT" -c commit.gpgSign=false -c user.name='Test User' -c user.email='test@example.invalid' commit -qm 'updated cask'

assert_ok 'renders the same stable cask again' \
  bash "$UPDATER" "$VERSION_TWO" "$SHA_TWO" "$TAP_ROOT"
git -C "$TAP_ROOT" add Casks/orthant.rb
assert_ok 'same input is a staged cached-diff no-op' \
  git -C "$TAP_ROOT" diff --cached --quiet

assert_ok 'accepts zero-valued canonical version components' \
  bash "$UPDATER" '0.1.0' "$SHA_ONE" "$TMP_DIR/zero-version-tap"
assert_ok 'rejects a prerelease version before rendering' \
  rejects_without_rendering '1.2.3-beta.1' "$SHA_ONE"
assert_ok 'rejects a leading-zero version before rendering' \
  rejects_without_rendering '01.2.3' "$SHA_ONE"
assert_ok 'rejects an incomplete version before rendering' \
  rejects_without_rendering '1.2' "$SHA_ONE"
assert_ok 'rejects a non-hex checksum before rendering' \
  rejects_without_rendering "$VERSION_ONE" 'gaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
assert_ok 'rejects an uppercase checksum before rendering' \
  rejects_without_rendering "$VERSION_ONE" 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
assert_ok 'rejects a short checksum before rendering' \
  rejects_without_rendering "$VERSION_ONE" 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
assert_ok 'rejects a long checksum before rendering' \
  rejects_without_rendering "$VERSION_ONE" 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
assert_fails 'rejects a missing tap path' \
  bash "$UPDATER" "$VERSION_ONE" "$SHA_ONE"
assert_ok 'rejects an empty tap path before creating directories' rejects_empty_tap_before_mkdir
touch "$TMP_DIR/not-a-tap-directory"
assert_fails 'rejects a tap whose Casks parent cannot be created' \
  bash "$UPDATER" "$VERSION_ONE" "$SHA_ONE" "$TMP_DIR/not-a-tap-directory"

if (( FAIL_COUNT > 0 )); then
  printf '%d of %d assertions failed\n' "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))" >&2
  exit 1
fi

printf '%d assertions passed\n' "$PASS_COUNT"
