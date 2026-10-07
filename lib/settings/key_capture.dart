import 'package:flutter/services.dart';
import '../core/carbon_keys.dart' show carbonKeyCode;
import '../shortcuts/bindings.dart';

/// Maps a physical key press + held modifiers to Carbon (keyCode, modifiers),
/// or null if the key isn't in the supported set. Requires at least one modifier.
({int keyCode, int modifiers})? carbonFromKeyEvent(KeyEvent event) {
  final code = carbonKeyCode(event.physicalKey.usbHidUsage);
  if (code == null) return null;
  final mods = heldModifiers();
  if (mods == 0) return null; // require a modifier — bare keys are unsafe as global hotkeys
  return (keyCode: code, modifiers: mods);
}

/// The Carbon modifier mask held down right now.
///
/// Lifted out of [carbonFromKeyEvent] so the recorder can draw what it is
/// hearing *before* a key completes the combination. Reads the keyboard rather
/// than the event because a modifier's own key-down carries no information
/// about the ones already held.
int heldModifiers() {
  final pressed = HardwareKeyboard.instance.logicalKeysPressed;
  var mods = 0;
  if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight)) {
    mods |= kControlKey;
  }
  if (pressed.contains(LogicalKeyboardKey.altLeft) ||
      pressed.contains(LogicalKeyboardKey.altRight)) {
    mods |= kOptionKey;
  }
  if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight)) {
    mods |= kShiftKey;
  }
  if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
      pressed.contains(LogicalKeyboardKey.metaRight)) {
    mods |= kCmdKey;
  }
  return mods;
}
