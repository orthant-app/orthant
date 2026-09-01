---
title: Uninstall
description: Removing Orthant completely, and the one thing an uninstall cannot remove.
order: 9
---

```sh
brew uninstall --zap orthant
```

`--zap` is the complete removal. It deletes the app, its preferences, caches and saved
state, **and revokes its Accessibility grant**. A plain `brew uninstall` leaves those
behind. If you reinstall after a zap you will be asked for Accessibility again — that is
the grant having genuinely gone, not a bug.

## What an uninstall cannot remove

**If you enabled "Launch at login", that registration survives the uninstall.** macOS records
it in a system database that Homebrew's uninstall step does not manage, and by the time the
removal script runs, the app that could have unregistered itself is already deleted. (A future
version could unregister itself from a step that runs *before* removal; today it does not.)

To clear it, **turn off "Launch at login" in Settings ▸ General before uninstalling**. If
you have already removed Orthant, the leftover entry does nothing — there is no app for it
to launch — and installing Orthant again will pick the setting back up.

## Uninstalling a manual install

Quit Orthant and delete the app. Settings live in
`~/Library/Preferences/app.orthant.orthant.plist`, and the Accessibility entry can be
removed in System Settings ▸ Privacy & Security ▸ Accessibility by selecting the row and
clicking **−**.
