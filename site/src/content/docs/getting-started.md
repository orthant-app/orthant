---
title: Getting started
description: Install Orthant on macOS or Windows, grant Accessibility permission on a Mac, and snap your first window.
group: start
order: 1
---

## Install

### On a Mac

```sh
brew install --cask orthant-app/tap/orthant
```

Or [download the disk image](/download/macos) and drag Orthant to Applications. Either way you
get the same build: signed with an Apple Developer ID and notarized by Apple, so it opens
without a trip through System Settings. Orthant needs **macOS 13+**.

### On Windows

[Download the installer](/download/windows) (or `Orthant-…-setup.exe` from
[the latest release](https://github.com/orthant-app/orthant/releases/latest)) and run it. It
installs Orthant for your account only, with no administrator rights. Orthant needs
**Windows 11** or **Windows 10 (version 1809 or later)**, 64-bit.

At first, Microsoft Defender SmartScreen may stop the installer with **Windows protected your
PC**. That means SmartScreen has not seen this download often yet: choose **More info**, then
**Run anyway**. The installer is signed, and its **Digital Signatures** tab (right-click it,
then **Properties**) names the publisher.

## Launch it

**On a Mac**, open Orthant from Applications, like any other app. On this first launch it opens
a small window to walk you through the next step. Once that window closes, look for its icon in
the **menu bar**, at the top of the screen. Its settings and update windows can appear in the
Dock while open.

Every launch after this one is quieter: once permission is granted, Orthant starts
straight into the menu bar and gets on with it, which is what you want from something
that is always running.

**On Windows**, the installer's last page offers to launch Orthant, and the Start menu has it
from then on. The first launch opens a short window showing the shortcuts to try; after that,
Orthant lives in the **notification area** at the right of the taskbar. Windows 11 puts a new
icon behind the **^** arrow there at first.

## Grant Accessibility permission

This step is for macOS only: Windows has no such permission, so on Windows skip to
[pressing a shortcut](#press-one-shortcut).

On first launch, Orthant opens a small window and walks you through granting
**Accessibility** permission. It needs this because it positions other apps' windows
through the macOS Accessibility API, the same mechanism every window manager uses, and
macOS gates that capability behind **System Settings ▸ Privacy & Security ▸
Accessibility**. It asks for nothing else, and the window gets out of the way the moment
the permission is on.

> **Having trouble granting permission?** See [Troubleshooting](/docs/troubleshooting/).

## Press one shortcut

Click any window to focus it, then press `⌃⌥←` (`Win+Ctrl+Shift+←` on Windows). It fills the
left half of its display. The window you are arranging stays active throughout the placement.

## Open the grid

Press `⌃⌥O` (`Win+Ctrl+Shift+O` on Windows) to open a grid over every display. Drag from one
cell to another, or move the selection with the arrow keys and hold `⇧` (Shift) to extend it,
then release (or press `↩`, Enter on Windows) to place the window. `Esc` dismisses the grid
without moving anything.

The grid is **2–12** cells per axis, set in **Settings ▸ General**.
