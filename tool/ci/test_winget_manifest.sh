#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/winget_manifest.py"
TMP_DIR="$(mktemp -d)"
PASS_COUNT=0
FAIL_COUNT=0

SHA='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'

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

assert_file_eq() {
  local label="$1" expected="$2" actual="$3"
  if cmp -s "$expected" "$actual"; then
    pass "$label"
  else
    fail "$label (files differ: $expected $actual)"
    diff "$expected" "$actual" >&2
  fi
}

# The whole manifest for one release, byte for byte: winget's validation reads
# every field, and a field that drifts here drifts in every later version.
mkdir -p "$TMP_DIR/expected"
cat >"$TMP_DIR/expected/Orthant.Orthant.yaml" <<'EOF'
# yaml-language-server: $schema=https://aka.ms/winget-manifest.version.1.12.0.schema.json
PackageIdentifier: Orthant.Orthant
PackageVersion: 1.2.3
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.12.0
EOF
cat >"$TMP_DIR/expected/Orthant.Orthant.installer.yaml" <<'EOF'
# yaml-language-server: $schema=https://aka.ms/winget-manifest.installer.1.12.0.schema.json
PackageIdentifier: Orthant.Orthant
PackageVersion: 1.2.3
InstallerType: inno
Scope: user
InstallModes:
- interactive
- silent
- silentWithProgress
UpgradeBehavior: install
ProductCode: '{2CB97B64-A74B-4CDD-8EB5-5C67F7689DDD}_is1'
ReleaseDate: 2026-10-20
MinimumOSVersion: 10.0.17763.0
Installers:
- Architecture: x64
  InstallerUrl: https://github.com/orthant-app/orthant/releases/download/v1.2.3/Orthant-1.2.3-setup.exe
  InstallerSha256: 0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
ManifestType: installer
ManifestVersion: 1.12.0
EOF
cat >"$TMP_DIR/expected/Orthant.Orthant.locale.en-US.yaml" <<'EOF'
# yaml-language-server: $schema=https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json
PackageIdentifier: Orthant.Orthant
PackageVersion: 1.2.3
PackageLocale: en-US
Publisher: Orthant
PublisherUrl: https://orthant.app
PublisherSupportUrl: https://github.com/orthant-app/orthant/issues
PackageName: Orthant
PackageUrl: https://orthant.app
License: MIT
LicenseUrl: https://github.com/orthant-app/orthant/blob/main/LICENSE
ShortDescription: Grid-based window manager. Snap the frontmost window with keyboard shortcuts, or draw where it goes on a grid.
Moniker: orthant
Tags:
- window-manager
- tiling
- keyboard-shortcuts
- productivity
ReleaseNotesUrl: https://orthant.app/changelog/
ManifestType: defaultLocale
ManifestVersion: 1.12.0
EOF

assert_ok 'writes a manifest for a stable release' \
  python3 "$WRITER" --version 1.2.3 --sha256 "$SHA" --date 2026-10-20 --out "$TMP_DIR/out"
for name in Orthant.Orthant.yaml Orthant.Orthant.installer.yaml Orthant.Orthant.locale.en-US.yaml; do
  assert_file_eq "$name is exactly the manifest" "$TMP_DIR/expected/$name" "$TMP_DIR/out/$name"
done
count="$(find "$TMP_DIR/out" -type f | wc -l | tr -d ' ')"
if [[ "$count" == 3 ]]; then
  pass 'writes the three files and nothing else'
else
  fail "writes the three files and nothing else (wrote $count)"
fi

# Each refusal writes nothing at all.
refuses() {
  local out="$TMP_DIR/refused-$PASS_COUNT-$FAIL_COUNT"
  if python3 "$WRITER" "$@" --out "$out" 2>/dev/null; then
    return 1
  fi
  [[ ! -e "$out" ]]
}
assert_ok 'refuses a beta, which winget does not carry' \
  refuses --version 1.2.3-beta.1 --sha256 "$SHA" --date 2026-10-20
assert_ok 'refuses a version that is not three integers' \
  refuses --version 1.2 --sha256 "$SHA" --date 2026-10-20
assert_ok 'refuses a short SHA-256' \
  refuses --version 1.2.3 --sha256 "${SHA%?}" --date 2026-10-20
assert_ok 'refuses a SHA-256 that is not hex' \
  refuses --version 1.2.3 --sha256 "g${SHA#?}" --date 2026-10-20
assert_ok 'refuses a date that is not YYYY-MM-DD' \
  refuses --version 1.2.3 --sha256 "$SHA" --date 20/10/2026

if (( FAIL_COUNT > 0 )); then
  printf '%d of %d assertions failed\n' "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))" >&2
  exit 1
fi

printf '%d assertions passed\n' "$PASS_COUNT"
