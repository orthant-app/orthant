---
title: Settings
description: Grid size, gaps between windows, and launch at login.
group: help
order: 2
---

Open Settings from Orthant's icon in the menu bar, or in the notification area on Windows.
Everything here survives a relaunch.

## General

**Grid size.** How many columns and rows the overlay draws, from 2–12 on each axis. A live
preview shows the result as you change it. Custom regions are unaffected, and keep their own
proportions.

**Gaps.** Space between placed windows and around the edge of the screen. Also previewed live.

A gap is a request rather than a promise. If the gap you ask for would make the window smaller
than 40 points, Orthant quietly reduces it rather than refusing, so the number beside the
stepper is a maximum. This is measured against the block you actually placed, not the smallest
cell on the grid, so a half-screen window keeps a wide gap that a single small cell could not.

**Launch at login.** Registers Orthant with the system to start when you log in.

> On macOS, turn this **off before uninstalling**. macOS records the registration outside the
> app, and an uninstall cannot remove it. On Windows the uninstaller removes it for you. See
> [Uninstall](/docs/uninstall/).

## Shortcuts

Every command and every custom region, each with its combination. See
[Shortcuts](/docs/shortcuts/) for rebinding, conflicts and resetting.
