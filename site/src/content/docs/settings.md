---
title: Settings
description: Grid size, gaps between windows, and launch at login.
order: 5
---

Open Settings from the menu bar icon. Everything here survives a relaunch.

## General

**Grid size.** How many columns and rows the overlay draws, from 2–12 on each axis. A live
preview shows the result as you change it. Custom regions are unaffected — they keep their own
proportions.

**Gaps.** Space between placed windows and around the edge of the screen. Also previewed live.

A gap is a request rather than a promise. If the gap you ask for would make the window smaller
than 40 points, Orthant quietly reduces it rather than refusing, so the number beside the
stepper is a maximum. This is measured against the block you actually placed, not the smallest
cell on the grid, so a half-screen window keeps a wide gap that a single small cell could not.

**Launch at login.** Registers Orthant with macOS to start when you log in.

> Turn this **off before uninstalling**. macOS records the registration outside the app, and an
> uninstall cannot remove it. See [Uninstall](/docs/uninstall/).

## Shortcuts

Every command and every custom region, each with its combination. See
[Shortcuts](/docs/shortcuts/) for rebinding, conflicts and resetting.
