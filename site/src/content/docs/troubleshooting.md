---
title: Troubleshooting
description: Fixing the Accessibility permission when macOS says it is on but Orthant says it is not.
order: 8
---

## System Settings shows Orthant as enabled, but Orthant says permission is missing

This is not your mistake, and it has a specific cause. macOS ties the Accessibility grant to
an app's **code signature**, not to its name or its location. If a differently-signed build of
Orthant has ever run on this Mac, macOS keeps a separate record for it, and the Accessibility
list collapses both records into one row with one toggle. The row can show **on** while the copy
you are running is genuinely ungranted, and toggling it does nothing.

Every released build is signed identically, so a `.dmg` install and a Homebrew install cannot
produce this between them. You are most likely to hit it if you have also **built Orthant from
source** and run that copy alongside an installed one.

To fix it:

1. **Quit System Settings entirely.** The pane caches its state, and a reset performed
   underneath it shows stale results. This is the step people skip.
2. Open Terminal and run:

   ```sh
   tccutil reset Accessibility app.orthant.orthant
   ```

3. Make sure the copy of Orthant you want to grant is the one running. Quit any other.
4. Reopen System Settings ▸ Privacy & Security ▸ Accessibility and enable Orthant.

## The row shows a stale name or the wrong icon

Select the Orthant row in that pane and click **−** to remove it, then relaunch Orthant and
grant it again. Turning the toggle off and on does not clear a stale row.

## Every app's toggle in that pane looks dimmed or wrongly off

The pane is showing a stale cache. Quit System Settings entirely and reopen it.

## A shortcut does nothing

- Another app may own the combination. Open **Settings ▸ Shortcuts**: a combination macOS
  itself has claimed is marked in the list rather than silently failing.
- If *every* shortcut stopped working, quit and reopen Orthant, then check the
  Accessibility grant above.

## An app ignores Orthant, or snaps to the wrong size

Some apps enforce their own minimum window size and will not go smaller; TextEdit is one.
Orthant asks for the size you drew; the app is entitled to refuse it. A window that lands
wider than the region you drew is usually this, not a placement bug.

## Still stuck

[Open an issue](https://github.com/orthant-app/orthant/issues) with your macOS version and
what you saw.
