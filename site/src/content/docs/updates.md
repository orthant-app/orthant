---
title: Updates
description: How Orthant updates itself, and how to turn that off.
group: help
order: 3
---

Orthant checks for updates on its own and installs them in place. Every update is signed with
an Apple Developer ID and notarized by Apple, and the update is verified before it is applied.

Updating does **not** disturb your Accessibility permission, your shortcuts, or your custom
regions.

## Turning it off

**Settings ▸ About ▸ Check for updates automatically.** With it off, Orthant never contacts
the update server; you can still check by hand from the menu bar.

## If you installed with Homebrew

The cask is marked `auto_updates true`, so `brew upgrade` deliberately skips Orthant rather
than fighting the built-in updater over the same app. That is the intended behaviour, not a
broken cask.

If you would rather Homebrew drove updates:

```sh
brew upgrade --cask --greedy-auto-updates orthant
```

## What gets downloaded

Where possible Orthant downloads only the difference between your version and the new one,
which is usually a small fraction of the full app. Disk images and updates alike are served
from GitHub.
