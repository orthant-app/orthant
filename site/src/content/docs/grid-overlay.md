---
title: The grid overlay
description: Summon a grid over every display and draw exactly where a window should go.
group: place
order: 1
---

Press `⌃⌥O` and a translucent grid appears over every display. It takes about 50
milliseconds, and Orthant never becomes the frontmost app, so the window you were using stays
active the whole time.

## Placing a window

**With the mouse.** Press inside the cell where the window should start, drag to the cell
where it should end, and release. The highlighted block previews exactly where the window
will land.

**With the keyboard.** Arrow keys move the selection. Hold `⇧` and arrow to extend it across
more cells. `↩` places the window.

`Esc` dismisses the overlay without moving anything.

## Saving what you just drew

`⌘S` places the window *and* opens a shortcut picker pre-filled with the selection you made.
Orthant suggests a name: draw the left two thirds and it offers "Left ⅔".

It has to be pressed **while the overlay is still up**, because releasing a drag places the
window and dismisses the grid. So either:

- keep the mouse button held down and press `⌘S` without releasing, or
- select with the arrow keys (`⇧`-arrow extends), then press `⌘S` instead of `↩`.

See [custom regions](/docs/custom-regions/).

## Notes

- The grid appears on **every** display at once, and the window lands on the display you drew
  on. Drawing on another screen is how you move a window to it. (Direct shortcuts are the
  other way round: they keep a window on its own display. See
  [multiple displays](/docs/multiple-displays/).)
- The overlay costs nothing while it is hidden: zero CPU, zero wake-ups.
- `Esc`, `↩` and `⌘S` belong to the overlay only while it is on screen. Dismiss it and they
  go straight back to the app underneath.
