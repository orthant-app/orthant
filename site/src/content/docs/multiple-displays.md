---
title: Multiple displays
description: How Orthant decides which screen a window belongs to.
group: place
order: 3
---

## A window snaps within its own display

Press `⌃⌥→` and the window fills the right half of **the display it is already on**, not the
one your pointer happens to be over.

This is deliberate, and it is the behaviour most people expect once they have both. Using the
cursor's display instead means a shortcut can fling a window to another screen because the
mouse drifted, which is a surprising way to lose a window.

When a window straddles two displays, Orthant picks the one covering more of it.

## Mixed resolutions and scaling

A Retina display and an external monitor at a different scale can be mixed freely. Orthant
works in one coordinate space throughout and converts exactly once, natively, so a window moved
between displays of different densities keeps the size you asked for.

## The overlay works the other way round

`⌃⌥O` puts a grid on all of them at once, each sized to its own screen. The window lands on
**the display you draw on**, so drawing on a different screen from the one the window is
currently on is how you move it there.

That is the opposite of the shortcut rule above, and deliberately so. A shortcut is aimed with
one keypress and should not depend on where the pointer drifted; a drawn selection is aimed at
a specific place on a specific screen, and honouring that is the whole point of drawing it.
