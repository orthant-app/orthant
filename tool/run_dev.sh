#!/usr/bin/env bash
#
# Build, sign and launch Orthant for manual testing — the everyday dev loop.
#
#   tool/run_dev.sh            # Debug build
#   tool/run_dev.sh Release
#
# Why not `flutter run -d macos`?
#   Two reasons, both learned the hard way:
#   1. Orthant is an LSUIElement (menu-bar) app. Started from a shell without an
#      interactive TTY, `flutter run` reaches EOF on stdin and tears the app down
#      seconds after launch — the log shows the VM service come up and then
#      "Lost connection to device", with no crash report. Nothing to click.
#   2. `flutter run` leaves the bundle ad-hoc signed, so the Accessibility grant
#      is orphaned on every rebuild (see tool/dev_signing.sh).
#   Building, re-signing, then handing the bundle to LaunchServices via `open`
#   avoids both.
#
set -euo pipefail

CONFIG="${1:-Debug}"
# Lowercase via tr rather than ${x,,}: macOS still ships bash 3.2, where the
# latter is a syntax error.
CONFIG_FLAG="$(printf '%s' "$CONFIG" | tr '[:upper:]' '[:lower:]')"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/build/macos/Build/Products/$CONFIG/Orthant.app"
BIN="$APP/Contents/MacOS/Orthant"

info() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

cd "$REPO_ROOT"

info "Building ($CONFIG)…"
flutter build macos "--$CONFIG_FLAG"

if "$REPO_ROOT/tool/dev_signing.sh" status >/dev/null 2>&1 &&
   security find-identity -v -p codesigning 2>/dev/null | grep -qF "Orthant Dev Signing"; then
  "$REPO_ROOT/tool/dev_signing.sh" sign "$CONFIG"
else
  warn "No stable signing identity — this build is ad-hoc signed, so you will"
  warn "have to re-grant Accessibility. Fix once with: tool/dev_signing.sh setup"
fi

# Replace **every** running build of this app, not just this configuration's.
#
# Matching on "$BIN" was a silent trap and it cost a real investigation. All
# three configurations share one bundle id, so `open` on the Debug bundle while
# a Profile instance is running does not start anything — LaunchServices simply
# activates the process that is already there. The script then found *a* running
# Orthant, said "Running", and left you driving the wrong binary. The symptom is
# the worst kind: the app is up, the tray works, and a fix you just made appears
# not to work.
#
# Anchored on Build/Products/ so it cannot reach an installed copy in
# /Applications, which is not ours to kill.
PRODUCTS="$REPO_ROOT/build/macos/Build/Products"
if pgrep -f "$PRODUCTS/.*/Orthant.app/Contents/MacOS/Orthant" >/dev/null 2>&1; then
  info "Stopping running instance(s)…"
  pgrep -lf "$PRODUCTS/.*/Orthant.app/Contents/MacOS/Orthant" |
    while read -r pid path; do printf '    was: %s (pid %s)\n' "$path" "$pid"; done
  pkill -f "$PRODUCTS/.*/Orthant.app/Contents/MacOS/Orthant" || true
  # Waited for rather than slept through: `open` below is a no-op against a
  # process that has not finished exiting yet, which is the very confusion
  # this block exists to end.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$PRODUCTS/.*/Orthant.app/Contents/MacOS/Orthant" >/dev/null 2>&1 || break
    sleep 0.3
  done
fi

info "Launching…"
open "$APP"
sleep 3

# Report the path *and* pid, so "which binary am I looking at" is answered here
# rather than reconstructed later from `ps -o lstart`.
RUNNING="$(pgrep -f "$BIN" | head -1 || true)"
if [[ -n "$RUNNING" ]]; then
  ok "Running: $BIN (pid $RUNNING)"
  ok "Look for the 2×2 icon in the menu bar."
else
  OTHER="$(pgrep -lf "$PRODUCTS/.*/Orthant.app/Contents/MacOS/Orthant" || true)"
  if [[ -n "$OTHER" ]]; then
    warn "A different build is running and this one is not:"
    warn "$OTHER"
  else
    warn "The app is not running. Check Console.app for crash reports."
  fi
  exit 1
fi
