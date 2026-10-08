// The Windows side of a chord: the virtual key and modifier flags that
// `RegisterHotKey` takes. The only file that knows Windows' key numbers, the
// way `carbon_keys.dart` is the only one that knows macOS's.
//
// Windows registers a chord by its **logical** key: a hotkey is matched
// against the layout of whichever app is in front, so a key position cannot
// be asked for at all. The virtual key comes from the logical key through the
// inverse of the rule the Flutter engine uses to name a key event on Windows
// (`flutter_key_map.g.cc`'s `windowsToLogicalMap_`, then: a printable virtual
// key is the character it is, lowercased from A to Z and from 0xC0 to 0xDE),
// so a chord recorded on Windows maps back to the virtual key that produced
// it.
// `VkKeyScanEx` is deliberately not used: it answers a *character* with the
// modifiers needed to type it, which would turn a recorded chord into a
// different one.

import 'package:flutter/services.dart'
    show LogicalKeyboardKey, PhysicalKeyboardKey;

import 'key_chord.dart';

/// `MOD_ALT`, `MOD_CONTROL`, `MOD_SHIFT`, `MOD_WIN`. The runner adds
/// `MOD_NOREPEAT` itself, to every registration.
const int kModAlt = 0x0001;
const int kModControl = 0x0002;
const int kModShift = 0x0004;
const int kModWin = 0x0008;

/// The `RegisterHotKey` flags for [modifiers]; 0 when none is held.
int windowsModifiers(Modifiers modifiers) =>
    (modifiers.has(Modifiers.alt) ? kModAlt : 0) |
    (modifiers.has(Modifiers.ctrl) ? kModControl : 0) |
    (modifiers.has(Modifiers.shift) ? kModShift : 0) |
    (modifiers.has(Modifiers.meta) ? kModWin : 0);

/// The id a chord's key has on Windows ([KeyChord.windowsKey]): the id it
/// registers, compares and is labelled by. Its [logical] key, except where
/// the engine names two keys with one id. It lowercases 0xC0 to 0xDE, so
/// Brazil's ABNT_C1 (the /? key) comes out as 0xE1 and ABNT_C2 (its keypad
/// separator) as 0xE2, the ids of VK_OEM_AX and VK_OEM_102 (the ISO key
/// beside left Shift). [physical] (a USB HID usage) tells them apart, and the
/// two ABNT keys answer with their own virtual keys, ids the engine never
/// names a key with.
int windowsKeyId(int logical, int physical) {
  if (logical == 0xE1 && physical == _intlRo) return 0xC1;
  if (logical == 0xE2 && physical == _numpadComma) return 0xC2;
  return logical;
}

final int _intlRo = PhysicalKeyboardKey.intlRo.usbHidUsage;
final int _numpadComma = PhysicalKeyboardKey.numpadComma.usbHidUsage;

/// The virtual key a chord whose Windows key id ([windowsKeyId]) is [key]
/// registers, or null when Windows cannot bind it.
///
/// Null for the keypad digits and the keypad decimal on purpose. Each is two
/// virtual keys (`VK_NUMPAD1` with NumLock on, `VK_END` with it off) where the
/// engine names it once, by scan code, so no single registration fires in
/// both states; and with Shift in the chord, Windows turns the press into the
/// navigation key and neither fires (measured). They are not recordable on
/// Windows. Keypad Enter is null too: Windows reports it as `VK_RETURN`, so
/// the engine names it `enter`, and a chord holding `numpadEnter` cannot come
/// from a Windows recording. So is keypad `=`: the engine names it by scan
/// code, and Windows reports it as `VK_CLEAR` on US (measured), which no
/// table entry can stand for.
int? windowsVirtualKey(int key) {
  final named = _virtualKeys[key];
  if (named != null) return named;
  return _ownIds.contains(key) ? key : null;
}

/// Keys whose id is their virtual key: Brazil's two ABNT keys, as
/// [windowsKeyId] gives them; VK_OEM_8, above the lowercased range; and
/// VK_OEM_AX and the ISO key, whose lowercase is their own id.
const Set<int> _ownIds = {0xC1, 0xC2, 0xDF, 0xE1, 0xE2};

/// The Windows key id ([windowsKeyId]) of a chord on [virtualKey]: the
/// forward direction of [windowsVirtualKey], for the keys a label is read
/// for. The engine's naming (its table, then a printable virtual key is its
/// character, lowercased from A to Z and from 0xC0 to 0xDE), except that the
/// two ABNT keys keep their own id.
int windowsKeyOf(int virtualKey) {
  final named = _logicalKeys[virtualKey];
  if (named != null) return named;
  if (virtualKey >= 0x41 && virtualKey <= 0x5A) return virtualKey + 0x20;
  if (virtualKey == 0xC1 || virtualKey == 0xC2) return virtualKey;
  if (virtualKey >= 0xC0 && virtualKey <= 0xDE) return virtualKey + 0x20;
  return virtualKey;
}

/// Virtual keys whose printed symbol depends on the layout: the ones
/// `keyboardLabels` reads from the current layout on Windows. Letters, digits
/// and named keys are labelled from the logical key itself.
const List<int> windowsLabelledKeys = [
  0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, // OEM_1, PLUS, COMMA, MINUS, PERIOD, 2, 3
  0xC1, 0xC2, // ABNT_C1, ABNT_C2
  0xDB, 0xDC, 0xDD, 0xDE, // OEM_4, 5, 6, 7
  0xDF, 0xE1, 0xE2, // OEM_8, OEM_AX, OEM_102
];

/// Every named key a shortcut can use on Windows, as (logical, virtual key),
/// copied from the engine's `windowsToLogicalMap_` and inverted. Letters and
/// digits are computed below them.
final Map<int, int> _virtualKeys = {
  for (final (logical, vk) in [
    (LogicalKeyboardKey.enter, 0x0D),
    (LogicalKeyboardKey.space, 0x20),
    (LogicalKeyboardKey.backspace, 0x08),
    (LogicalKeyboardKey.pageUp, 0x21),
    (LogicalKeyboardKey.pageDown, 0x22),
    (LogicalKeyboardKey.end, 0x23),
    (LogicalKeyboardKey.home, 0x24),
    (LogicalKeyboardKey.arrowLeft, 0x25),
    (LogicalKeyboardKey.arrowUp, 0x26),
    (LogicalKeyboardKey.arrowRight, 0x27),
    (LogicalKeyboardKey.arrowDown, 0x28),
    (LogicalKeyboardKey.delete, 0x2E),
    (LogicalKeyboardKey.numpadMultiply, 0x6A),
    (LogicalKeyboardKey.numpadAdd, 0x6B),
    (LogicalKeyboardKey.numpadComma, 0x6C),
    (LogicalKeyboardKey.numpadSubtract, 0x6D),
    (LogicalKeyboardKey.numpadDivide, 0x6F),
    (LogicalKeyboardKey.f1, 0x70),
    (LogicalKeyboardKey.f2, 0x71),
    (LogicalKeyboardKey.f3, 0x72),
    (LogicalKeyboardKey.f4, 0x73),
    (LogicalKeyboardKey.f5, 0x74),
    (LogicalKeyboardKey.f6, 0x75),
    (LogicalKeyboardKey.f7, 0x76),
    (LogicalKeyboardKey.f8, 0x77),
    (LogicalKeyboardKey.f9, 0x78),
    (LogicalKeyboardKey.f10, 0x79),
    (LogicalKeyboardKey.f11, 0x7A),
    (LogicalKeyboardKey.f12, 0x7B),
    (LogicalKeyboardKey.f13, 0x7C),
    (LogicalKeyboardKey.f14, 0x7D),
    (LogicalKeyboardKey.f15, 0x7E),
    (LogicalKeyboardKey.f16, 0x7F),
    (LogicalKeyboardKey.f17, 0x80),
    (LogicalKeyboardKey.f18, 0x81),
    (LogicalKeyboardKey.f19, 0x82),
    (LogicalKeyboardKey.f20, 0x83),
    (LogicalKeyboardKey.numLock, 0x90),
    (LogicalKeyboardKey.semicolon, 0xBA),
    (LogicalKeyboardKey.equal, 0xBB),
    (LogicalKeyboardKey.comma, 0xBC),
    (LogicalKeyboardKey.minus, 0xBD),
    (LogicalKeyboardKey.period, 0xBE),
    (LogicalKeyboardKey.slash, 0xBF),
    (LogicalKeyboardKey.backquote, 0xC0),
    (LogicalKeyboardKey.bracketLeft, 0xDB),
    (LogicalKeyboardKey.backslash, 0xDC),
    (LogicalKeyboardKey.bracketRight, 0xDD),
    (LogicalKeyboardKey.quote, 0xDE),
  ])
    logical.keyId: vk,
  // Letters: the engine names VK_A..VK_Z by the lowercase character.
  for (var vk = 0x41; vk <= 0x5A; vk++) vk + 0x20: vk,
  // Digits: VK_0..VK_9 are the characters themselves.
  for (var vk = 0x30; vk <= 0x39; vk++) vk: vk,
};

final Map<int, int> _logicalKeys = {
  for (final e in _virtualKeys.entries)
    if (e.key < 0x61 || e.key > 0x7A) e.value: e.key,
};
