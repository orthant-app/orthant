---
title: Updates
description: How Orthant updates itself on macOS and Windows, and how to turn that off.
group: help
order: 3
---

Orthant checks for updates on its own and installs them in place. On macOS every update is
signed with an Apple Developer ID and notarized by Apple; on Windows every installer is signed.
On both, the update is verified before it is applied.

Updating does **not** disturb your shortcuts or your custom regions, nor, on macOS, your
Accessibility permission.

## On Windows

Orthant checks about once a day, quietly: nothing opens on its own. When an update is ready,
its tray menu gains **Update to Orthant …** with the new version's number, and
**Settings ▸ About** says so too. Choose it, or **Check for Updates…** in either place, to see
the update and install it. Orthant closes, updates, and starts again with your settings as
they were.

## Turning it off

**Settings ▸ About ▸ Check for updates automatically.** With it off, Orthant never contacts
the update server; you can still check by hand from the menu bar, or from the tray on Windows.

## If you installed with Homebrew

The cask is marked `auto_updates true`, so `brew upgrade` deliberately skips Orthant rather
than fighting the built-in updater over the same app. That is the intended behaviour, not a
broken cask.

If you would rather Homebrew drove updates:

```sh
brew upgrade --cask --greedy-auto-updates orthant
```

## What gets downloaded

On macOS, where possible Orthant downloads only the difference between your version and the
new one, which is usually a small fraction of the full app. On Windows an update is the full
installer. Disk images, installers and updates alike are served from GitHub.
