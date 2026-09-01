---
title: Custom regions
description: Draw any block on any grid, name it, and give it a shortcut.
order: 4
---

The built-in commands cover halves, quarters, maximize and center. A custom region is
anything else: left two thirds, a centred column, the top strip of an ultrawide.

## Creating one

Two ways in:

- **From the overlay.** Draw a selection and press `⌘S`. The picker opens already filled in,
  with a suggested name.
- **From Settings.** Open **Settings ▸ Shortcuts** and choose *Add region…*, then draw on the
  grid in the sheet. Arrow keys and `⇧`-arrows work here too.

Name it, click the shortcut field, and press the combination you want.

## A region remembers its own proportions

This is the part worth knowing. A region does not store "cells 0 to 7 of 12" as a position on
your current grid — it stores the **fraction** it covers. Change the overlay's grid size
afterwards and your regions land in exactly the same place.

So you can set the grid to 6 columns to draw a precise third, set it back to 4, and the region
still gives you a third.

## Editing and deleting

Select a region in **Settings ▸ Shortcuts** to rename it, redraw it, or change its shortcut.
Editing keeps the same region, so its shortcut survives.

Deleting a region also clears its shortcut, and offers an Undo.

*Reset Shortcuts* puts the built-in commands back to their defaults. Your regions survive it;
their shortcuts do not.
