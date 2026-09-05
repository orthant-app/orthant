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

Or [download the disk image](/download) and drag Orthant to Applications. Either way you
get the same build: signed with an Apple Developer ID and notarized by Apple, so it opens
without a trip through System Settings. Orthant needs **macOS 13+**.

## Launch it

Open Orthant from Applications, like any other app. On this first launch it opens a small
window to walk you through the next step. Once that window closes, look for its icon in the
**menu bar**, at the top of the screen. Its settings and update windows can appear in the
Dock while open.

Every launch after this one is quieter: once permission is granted, Orthant starts
straight into the menu bar and gets on with it, which is what you want from something
that is always running.

## Grant Accessibility permission

On first launch, Orthant opens a small window and walks you through granting
**Accessibility** permission. It needs this because it positions other apps' windows
through the macOS Accessibility API, the same mechanism every window manager uses, and
macOS gates that capability behind **System Settings ▸ Privacy & Security ▸
Accessibility**. It asks for nothing else, and the window gets out of the way the moment
the permission is on.

> **Having trouble granting permission?** See [Troubleshooting](/docs/troubleshooting/).

## Press one shortcut

Click any window to focus it, then press `⌃⌥←`. It fills the left half of its display.
The window you are arranging stays active throughout the placement.

## Open the grid

Press `⌃⌥O` to open a grid over every display. Drag from one cell to another, or move
the selection with the arrow keys and hold `⇧` to extend it, then release (or press `↩`)
to place the window. `Esc` dismisses the grid without moving anything.

The grid is **2–12** cells per axis, set in **Settings ▸ General**.
