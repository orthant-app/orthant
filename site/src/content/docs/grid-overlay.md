---
title: The grid overlay
description: Summon a grid over every display and draw exactly where a window should go.
order: 3
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

`⌘S` on the overlay places the window *and* opens a shortcut picker pre-filled with the
selection you made. Orthant suggests a name: draw the left two thirds and it offers
"Left ⅔". You can bind it to a shortcut on the spot. See
[custom regions](/docs/custom-regions/).

## Notes

- The grid appears on **every** display at once. Draw on whichever one you like; the window
  moves within its own display.
- The overlay costs nothing while it is hidden: zero CPU, zero wake-ups.
- `Esc`, `↩` and `⌘S` belong to the overlay only while it is on screen. Dismiss it and they
  go straight back to the app underneath.
