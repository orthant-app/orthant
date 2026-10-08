import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import '../core/key_chord.dart';
import '../core/windows_keys.dart';

/// The chord a key press records, or null if the key isn't one a shortcut may
/// use or no modifier is held.
///
/// On Windows the key must also have a virtual key to register
/// ([windowsVirtualKey]): a keypad digit has none, since it is a different
/// virtual key in each NumLock state. Refused here, the press is ignored and
/// the recorder keeps listening, rather than recording a shortcut that could
/// never fire.
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
