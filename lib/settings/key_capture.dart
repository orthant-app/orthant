import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import '../core/key_chord.dart';
import '../core/windows_keys.dart';
import '../l10n/app_localizations.dart';
import '../l10n/strings.dart';

/// The chord a key press records, or null if the key isn't one a shortcut may
/// use or no modifier is held.
///
/// On Windows the key must also have a virtual key to register
/// ([windowsVirtualKey]): a keypad digit has none, since it is a different
/// virtual key in each NumLock state. Refused here, the recorder keeps
/// listening, rather than recording a shortcut that could never fire, and
/// says why ([refusalFor]).
///
/// Both of the key's identities come from this one event: its position, which
/// macOS registers, and what it typed under the current layout, which Windows
/// registers. Neither can be recovered from the other later, because the
/// layout that related them may be gone by then.
KeyChord? chordFromKeyEvent(KeyEvent event) {
  final physical = event.physicalKey.usbHidUsage;
  if (!isBindableKey(physical)) return null;
  final logical = event.logicalKey.keyId;
  if (defaultTargetPlatform == TargetPlatform.windows &&
      windowsVirtualKey(windowsKeyId(logical, physical)) == null) {
    return null;
  }
  final modifiers = heldModifiers();
  // A bare key is unsafe as a global hotkey: it would be taken from every app.
  if (modifiers.isEmpty) return null;
  return KeyChord(
    physical: physical,
    logical: logical,
    modifiers: modifiers,
  );
}

/// What the recorder says when a key cannot be part of a shortcut on Windows:
/// the keypad's digits, decimal point and = (each is a different virtual key
/// in each NumLock state, so no registration fires in both), or a key Windows
/// has no virtual key for at all.
///
/// Messages (`refusalKeypad`, `refusalUnregistrable`), so they are said in the
/// language of the app. These two read the language the code without a widget
/// tree uses (`appStrings`), which is what English is until the app points it
/// elsewhere; [refusalFor] takes the widget tree's own when it has one.
String get keypadRefusal => appStrings.refusalKeypad;
String get unregistrableRefusal => appStrings.refusalUnregistrable;

/// Why [event], pressed with a modifier held, cannot be recorded on this
/// platform: a sentence for the person recording, or null when it records, or
/// when there is nothing to explain (a modifier on its own, a bare key, Tab:
/// the footer already says a combination needs a modifier). Only Windows
/// refuses keys this way; on macOS every bindable key registers.
///
/// In the language of [l], or of [appStrings] when none is given.
String? refusalFor(KeyEvent event, [AppLocalizations? l]) {
  if (defaultTargetPlatform != TargetPlatform.windows) return null;
  final physical = event.physicalKey.usbHidUsage;
  if (!isBindableKey(physical) || heldModifiers().isEmpty) return null;
  final logical = event.logicalKey.keyId;
  if (windowsVirtualKey(windowsKeyId(logical, physical)) != null) return null;
  final words = l ?? appStrings;
  return _keypadUnregistrable.contains(logical)
      ? words.refusalKeypad
      : words.refusalUnregistrable;
}

final _keypadUnregistrable = {
  for (final key in [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
    LogicalKeyboardKey.numpadDecimal,
    LogicalKeyboardKey.numpadEqual,
  ])
    key.keyId,
};

/// The modifiers held down right now.
///
/// Lifted out of [chordFromKeyEvent] so the recorder can draw what it is
/// hearing *before* a key completes the combination. Reads the keyboard rather
/// than the event because a modifier's own key-down carries no information
/// about the ones already held.
Modifiers heldModifiers() {
  final pressed = HardwareKeyboard.instance.logicalKeysPressed;
  var modifiers = Modifiers.none;
  if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight)) {
    modifiers = modifiers | Modifiers.ctrl;
  }
  if (pressed.contains(LogicalKeyboardKey.altLeft) ||
      pressed.contains(LogicalKeyboardKey.altRight)) {
    modifiers = modifiers | Modifiers.alt;
  }
  if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight)) {
    modifiers = modifiers | Modifiers.shift;
  }
  if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
      pressed.contains(LogicalKeyboardKey.metaRight)) {
    modifiers = modifiers | Modifiers.meta;
  }
  return modifiers;
}
