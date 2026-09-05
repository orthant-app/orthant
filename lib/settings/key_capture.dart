import 'package:flutter/services.dart';
import '../shortcuts/bindings.dart';

// PhysicalKeyboardKey.usbHidUsage (USB HID page 0x07) → Carbon virtual key code.
const Map<int, int> _physicalToCarbon = {
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
  // Punctuation, plus the extra ISO key beside left Shift.
  0x0007002D: 27, 0x0007002E: 24, 0x0007002F: 33, 0x00070030: 30,
  0x00070031: 42, 0x00070032: 42, 0x00070033: 41, 0x00070034: 39,
  0x00070035: 50, 0x00070036: 43, 0x00070037: 47, 0x00070038: 44,
  0x00070064: 10,
  // Editing / navigation. Escape remains the recorder's cancel action, and
  // Tab is deliberately absent: ⌃⇥ and ⌘⇥ switch tabs and apps everywhere,
  // and RegisterEventHotKey would take them without a word.
  0x0007002A: 51,
  0x0007004A: 115, 0x0007004B: 116, 0x0007004C: 117,
  0x0007004D: 119, 0x0007004E: 121,
  // F1…F20. The keyboard must deliver an F-key event, not a media action.
  0x0007003A: 122, 0x0007003B: 120, 0x0007003C: 99, 0x0007003D: 118,
  0x0007003E: 96, 0x0007003F: 97, 0x00070040: 98, 0x00070041: 100,
  0x00070042: 101, 0x00070043: 109, 0x00070044: 103, 0x00070045: 111,
  0x00070068: 105, 0x00070069: 107, 0x0007006A: 113, 0x0007006B: 106,
  0x0007006C: 64, 0x0007006D: 79, 0x0007006E: 80, 0x0007006F: 90,
  // Numeric keypad, including its distinct Enter and decimal keys.
  0x00070053: 71, 0x00070054: 75, 0x00070055: 67, 0x00070056: 78,
  0x00070057: 69, 0x00070058: 76, 0x00070059: 83, 0x0007005A: 84,
  0x0007005B: 85, 0x0007005C: 86, 0x0007005D: 87, 0x0007005E: 88,
  0x0007005F: 89, 0x00070060: 91, 0x00070061: 92, 0x00070062: 82,
  0x00070063: 65, 0x00070067: 81, 0x00070085: 95,
  // JIS punctuation, which has dedicated physical keys.
  0x00070087: 94, 0x00070089: 93,
};

/// Maps a physical key press + held modifiers to Carbon (keyCode, modifiers),
/// or null if the key isn't in the supported set. Requires at least one modifier.
({int keyCode, int modifiers})? carbonFromKeyEvent(KeyEvent event) {
  final code = _physicalToCarbon[event.physicalKey.usbHidUsage];
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
