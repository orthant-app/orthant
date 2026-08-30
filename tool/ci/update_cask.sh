#!/usr/bin/env bash

set -euo pipefail

error() {
  printf 'update_cask: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 3 ]] || error 'usage: update_cask.sh VERSION SHA256 TAP_ROOT'

version="$1"
sha256="$2"
tap_root="$3"

[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
  error "invalid stable version: $version"
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || error 'invalid SHA-256 checksum'
[[ -n "$tap_root" ]] || error 'missing tap path'

casks_dir="$tap_root/Casks"
cask_path="$casks_dir/orthant.rb"
mkdir -p "$casks_dir"
temporary="$(mktemp "$casks_dir/.orthant.rb.XXXXXX")"
trap 'rm -f "$temporary"' EXIT

cat >"$temporary" <<EOF
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

mv "$temporary" "$cask_path"
trap - EXIT
