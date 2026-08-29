import 'package:flutter/services.dart';
import '../shortcuts/bindings.dart';

// PhysicalKeyboardKey.usbHidUsage (USB HID page 0x07) → Carbon virtual key code.
const Map<int, int> _logicalToCarbon = {
  // arrows / return / space
  0x00070050: 123, // arrowLeft
  0x0007004F: 124, // arrowRight
  0x00070051: 125, // arrowDown
  0x00070052: 126, // arrowUp
  0x00070028: 36,  // enter/return
  0x0007002C: 49,  // space
  // letters a..z → kVK_ANSI codes
  0x00070004: 0,  0x00070005: 11, 0x00070006: 8,  0x00070007: 2,
  0x00070008: 14, 0x00070009: 3,  0x0007000A: 5,  0x0007000B: 4,
  0x0007000C: 34, 0x0007000D: 38, 0x0007000E: 40, 0x0007000F: 37,
  0x00070010: 46, 0x00070011: 45, 0x00070012: 31, 0x00070013: 35,
  0x00070014: 12, 0x00070015: 15, 0x00070016: 1,  0x00070017: 17,
  0x00070018: 32, 0x00070019: 9,  0x0007001A: 13, 0x0007001B: 7,
  0x0007001C: 16, 0x0007001D: 6,
  // digits 1..9,0
  0x0007001E: 18, 0x0007001F: 19, 0x00070020: 20, 0x00070021: 21,
  0x00070022: 23, 0x00070023: 22, 0x00070024: 26, 0x00070025: 28,
  0x00070026: 25, 0x00070027: 29,
};

/// Maps a physical key press + held modifiers to Carbon (keyCode, modifiers),
/// or null if the key isn't in the supported set. Requires at least one modifier.
({int keyCode, int modifiers})? carbonFromKeyEvent(KeyEvent event) {
  final code = _logicalToCarbon[event.physicalKey.usbHidUsage];
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
