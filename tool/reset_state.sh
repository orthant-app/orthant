#!/usr/bin/env bash
#
# Put Orthant back into a first-run state, for manual testing.
#
#   tool/reset_state.sh onboarding      # show the onboarding + "try it" screens again
#   tool/reset_state.sh settings        # grid, gaps, launch-at-login back to defaults
#   tool/reset_state.sh bindings        # every shortcut back to its default
#   tool/reset_state.sh accessibility   # revoke the Accessibility grant
#   tool/reset_state.sh all             # all of the above — a true first launch
#
#   tool/reset_state.sh all --relaunch  # …and start the app afterwards
#
# Quits the app first in every case: it holds these values in memory and writes
# them back on change, so resetting underneath a running instance is a race you
# lose about half the time.
#
# On `accessibility`: `tccutil reset` revokes the grant but LEAVES THE ROW in
# System Settings ▸ Privacy & Security ▸ Accessibility, along with the name and
# icon captured when that row was first created. To clear a stale name or icon
# you must select the row and click "−" by hand — no CLI reaches it, because the
# TCC database is protected by SIP.
set -euo pipefail

BUNDLE_ID="app.orthant.orthant"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bold=$'\033[1m'; blue=$'\033[1;34m'; green=$'\033[1;32m'; dim=$'\033[2m'; off=$'\033[0m'
step() { printf '%s▸%s %s\n' "$blue" "$off" "$1"; }
done_() { printf '%s✓%s %s\n' "$green" "$off" "$1"; }

usage() {
  sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

WHAT="${1:-}"
RELAUNCH="${2:-}"
[[ -z "$WHAT" || "$WHAT" == "-h" || "$WHAT" == "--help" ]] && usage
case "$WHAT" in
  onboarding|settings|bindings|accessibility|all) ;;
  *) printf 'unknown target: %s\n\n' "$WHAT" >&2; usage 2 ;;
esac

# `defaults delete` exits non-zero when the key is absent, which is a perfectly
# normal state here — a fresh install has none of them.
forget() {
  if defaults delete "$BUNDLE_ID" "$1" 2>/dev/null; then
    done_ "cleared $1"
  else
    printf '%s  (%s was already unset)%s\n' "$dim" "$1" "$off"
  fi
}

if pgrep -x Orthant >/dev/null 2>&1; then
  step 'Quitting Orthant…'
  pkill -x Orthant || true
  sleep 1
fi

case "$WHAT" in
  onboarding|all)
    step 'Onboarding'
    # shared_preferences stores under NSUserDefaults with a `flutter.` prefix.
    forget 'flutter.orthant.onboarded.v1'
    ;;&
  settings|all)
    step 'Settings (grid, gaps)'
    forget 'flutter.orthant.settings.v1'
    ;;&
  bindings|all)
    step 'Shortcut bindings'
    forget 'flutter.orthant.bindings.v1'
    ;;&
  accessibility|all)
    step 'Accessibility grant'
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null
    done_ "revoked Accessibility for $BUNDLE_ID"
    cat <<'NOTE'

  Note: the row stays in System Settings ▸ Privacy & Security ▸ Accessibility,
  keeping the name and icon it was created with. If it still reads "orthant" or
  shows an old icon, select it there and click "−" before re-granting — that
  record is SIP-protected and no command can rewrite it.
NOTE
    ;;
esac

if [[ "$RELAUNCH" == "--relaunch" ]]; then
  APP="$REPO_ROOT/build/macos/Build/Products/Release/Orthant.app"
  [[ -d "$APP" ]] || APP="$REPO_ROOT/build/macos/Build/Products/Debug/Orthant.app"
  if [[ -d "$APP" ]]; then
    step 'Launching…'
    open "$APP"
    done_ "running: $APP"
  else
    printf 'no built app found — run tool/run_dev.sh first\n' >&2
    exit 1
  fi
fi
