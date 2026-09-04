---
title: Getting started
description: Install Orthant, grant Accessibility permission, and snap your first window.
group: start
order: 1
---

## Install

```sh
brew install --cask orthant-app/tap/orthant
```

Or download the `.dmg` and drag Orthant to Applications. Either way you get the same
build: signed with an Apple Developer ID and notarized by Apple, so it opens without a
trip through System Settings. Orthant needs **macOS 13+**.

## Grant Accessibility permission

Orthant positions other apps' windows through the macOS Accessibility API, the same
mechanism every window manager uses, and macOS gates that behind **System Settings ▸
Privacy & Security ▸ Accessibility**.

On first launch Orthant walks you through it, and gets out of the way the moment it is
on. It asks for nothing else.

## Snap your first window

Click any window to focus it, then press `⌃⌥→`. It fills the right half of its display.
Orthant never becomes the frontmost app, so the window you are arranging stays active.

Press `⌃⌥O` to open the grid over every display. Drag across cells, or use the arrow
keys with `⇧` to extend, and release to place the window. `Esc` dismisses it.

The grid is **2–12** cells per axis, set in **Settings ▸ General**.
