#!/usr/bin/env bash
#
# Stable local code-signing identity for Orthant development builds.
#
# WHY THIS EXISTS
#   macOS grants Accessibility (TCC) permission to a *specific code signature*.
#   Flutter's debug builds are ad-hoc signed, and an ad-hoc signature changes on
#   every build — so each rebuild looks like a brand-new app to macOS, silently
#   orphaning the grant. Symptom: System Settings shows "Orthant" toggled ON
#   while the app still reports "not granted", and no amount of toggling fixes
#   it (the ON entry belongs to a previous build).
#
#   Signing every build with one long-lived local certificate keeps the
#   signature stable, so the grant sticks until you deliberately revoke it.
#
# WHAT IT TOUCHES
#   `setup` creates a self-signed code-signing certificate and adds it to your
#   *login* keychain, trusted for code signing. That is a persistent change to
#   your machine; `remove` undoes it. Nothing here is needed for CI or for
#   shipping — release builds use a real Developer ID (milestone M8).
#
# USAGE
#   tool/dev_signing.sh setup     # once per machine
#   tool/dev_signing.sh sign      # after each build (or use tool/run_dev.sh)
#   tool/dev_signing.sh status
#   tool/dev_signing.sh remove
#
set -euo pipefail

IDENTITY="Orthant Dev Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DAYS=3650

info() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# Run a command quietly, but surface its output if it fails. (Blanket
# >/dev/null 2>&1 is how a real error ends up looking like a mystery.)
run_quiet() {
  local out
  if ! out="$("$@" 2>&1)"; then
    printf '%s\n' "$out" >&2
    return 1
  fi
}

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."

have_identity() {
  security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"
}

app_path() { # $1 = build configuration (Debug|Release|Profile)
  printf '%s/build/macos/Build/Products/%s/Orthant.app' "$REPO_ROOT" "$1"
}

entitlements_for() { # $1 = build configuration
  if [[ "$1" == "Release" ]]; then
    printf '%s/macos/Runner/Release.entitlements' "$REPO_ROOT"
  else
    printf '%s/macos/Runner/DebugProfile.entitlements' "$REPO_ROOT"
  fi
}

cmd_setup() {
  if have_identity; then
    ok "Identity already present: $IDENTITY"
  else
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    info "Generating a self-signed code-signing certificate…"
    cat > "$tmp/cert.cnf" <<'CNF'
[req]
default_bits       = 2048
prompt             = no
distinguished_name = dn
x509_extensions    = v3_cs

[dn]
CN = Orthant Dev Signing
O  = Orthant
C  = US

[v3_cs]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
CNF
    run_quiet openssl req -x509 -newkey rsa:2048 -sha256 -days "$CERT_DAYS" \
      -nodes -keyout "$tmp/dev.key" -out "$tmp/dev.crt" -config "$tmp/cert.cnf" \
      || die "Certificate generation failed (see openssl output above)."
    # macOS's Security framework can't read OpenSSL 3's default PKCS#12
    # (SHA-256 MAC + AES-256-CBC); `security import` misreports it as a wrong
    # password. Pin the SHA-1/3DES combination it does understand. 3DES is still
    # in OpenSSL 3's default provider, so this needs no legacy provider — unlike
    # `-legacy`, which additionally pulls in RC2.
    run_quiet openssl pkcs12 -export -inkey "$tmp/dev.key" -in "$tmp/dev.crt" \
      -name "$IDENTITY" -out "$tmp/dev.p12" -passout pass:orthant \
      -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
      || die "PKCS#12 bundling failed (see openssl output above)."

    info "Importing into your login keychain (allowing codesign to use it)…"
    run_quiet security import "$tmp/dev.p12" -k "$KEYCHAIN" -P orthant \
      -T /usr/bin/codesign \
      || die "Keychain import failed (see output above).
       'MAC verification failed' here means the PKCS#12 was written with
       algorithms macOS can't read — check the -macalg/-keypbe/-certpbe flags."

    warn "Trusting the certificate for code signing — macOS will ask for your password."
    security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$tmp/dev.crt"

    have_identity || die "Import succeeded but the identity is not valid for code signing.
       Open Keychain Access, find \"$IDENTITY\", then Get Info ▸ Trust ▸
       Code Signing: Always Trust, and re-run this command."
    ok "Identity created and trusted: $IDENTITY"
  fi

  cat <<EOF

Next:
  1. tool/run_dev.sh            # build, sign, launch
  2. Grant Accessibility ONCE in System Settings ▸ Privacy & Security.
     From now on rebuilds keep the same signature, so the grant persists.

If the grant still looks stale after switching to signed builds, clear the old
ad-hoc entries once:  tccutil reset Accessibility app.orthant.orthant
EOF
}

cmd_sign() {
  local config="${1:-Debug}"
  local app ents
  app="$(app_path "$config")"
  ents="$(entitlements_for "$config")"

  have_identity || die "No signing identity. Run: tool/dev_signing.sh setup"
  # Note: lowercasing via tr, not ${x,,} — macOS still ships bash 3.2.
  [[ -d "$app" ]] || die "No app bundle at $app
       Build it first: flutter build macos --$(printf '%s' "$config" | tr '[:upper:]' '[:lower:]')"

  # Nested code first, then the bundle — signing inside-out is required, and
  # entitlements belong only on the outer bundle. (Avoids --deep, which Apple
  # discourages and which would wrongly apply entitlements to frameworks.)
  info "Signing nested frameworks…"
  while IFS= read -r -d '' framework; do
    codesign --force --timestamp=none --sign "$IDENTITY" "$framework"
  done < <(find "$app/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 2>/dev/null)

  while IFS= read -r -d '' dylib; do
    codesign --force --timestamp=none --sign "$IDENTITY" "$dylib"
  done < <(find "$app/Contents" -name '*.dylib' -print0 2>/dev/null)

  # Entitlements must be preserved: debug builds need allow-jit (Dart VM) and
  # network.server (VM service), and the app must stay un-sandboxed for AX.
  #
  # Deliberately NOT --options runtime: the hardened runtime turns on library
  # validation, which requires every loaded library to share the main binary's
  # Team ID. A self-signed certificate has no Team ID, so the app dies at launch
  # with "Library not loaded: @rpath/orthant.debug.dylib … different Team IDs".
  # Hardened runtime belongs with the Developer ID + notarization work (M8).
  info "Signing the app bundle with $(basename "$ents")…"
  codesign --force --timestamp=none \
    --entitlements "$ents" --sign "$IDENTITY" "$app"

  codesign --verify --deep --strict "$app" \
    || die "Signature verification failed."
  ok "Signed: $app"
  codesign -dv "$app" 2>&1 | grep -E 'Identifier|Authority' | sed 's/^/    /'
}

cmd_status() {
  if have_identity; then
    ok "Signing identity present:"
    security find-identity -v -p codesigning | grep -F "$IDENTITY" | sed 's/^/   /'
  else
    warn "No \"$IDENTITY\" identity (run: tool/dev_signing.sh setup)"
  fi

  local app
  app="$(app_path "${1:-Debug}")"
  if [[ -d "$app" ]]; then
    info "Current bundle signature:"
    codesign -dv "$app" 2>&1 | grep -E 'Identifier|Signature|Authority' \
      | sed 's/^/   /' || true
  else
    warn "No built bundle at $app"
  fi
}

cmd_remove() {
  have_identity || { warn "Nothing to remove."; return 0; }
  warn "Deleting \"$IDENTITY\" from $KEYCHAIN — macOS may ask for your password."
  security delete-identity -c "$IDENTITY" "$KEYCHAIN" >/dev/null
  ok "Removed. Builds fall back to ad-hoc signing (grants will churn again)."
}

case "${1:-}" in
  setup)  cmd_setup ;;
  sign)   cmd_sign "${2:-Debug}" ;;
  status) cmd_status "${2:-Debug}" ;;
  remove) cmd_remove ;;
  *)
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
