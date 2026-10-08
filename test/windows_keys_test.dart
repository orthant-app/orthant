import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/core/windows_keys.dart';

/// The engine's own names for the virtual keys a shortcut can use, copied
/// from Flutter 3.47.4's `flutter_key_map.g.cc` (`windowsToLogicalMap_`) as
/// (virtual key, logical key). Kept apart from the table under test, so a
/// mistyped entry in either fails here.
final _engine = <(int, LogicalKeyboardKey)>[
  (0x08, LogicalKeyboardKey.backspace), (0x0D, LogicalKeyboardKey.enter),
  (0x20, LogicalKeyboardKey.space), (0x21, LogicalKeyboardKey.pageUp),
  (0x22, LogicalKeyboardKey.pageDown), (0x23, LogicalKeyboardKey.end),
  (0x24, LogicalKeyboardKey.home), (0x25, LogicalKeyboardKey.arrowLeft),
  (0x26, LogicalKeyboardKey.arrowUp), (0x27, LogicalKeyboardKey.arrowRight),
  (0x28, LogicalKeyboardKey.arrowDown), (0x2E, LogicalKeyboardKey.delete),
  (0x6A, LogicalKeyboardKey.numpadMultiply), (0x6B, LogicalKeyboardKey.numpadAdd),
  (0x6C, LogicalKeyboardKey.numpadComma), (0x6D, LogicalKeyboardKey.numpadSubtract),
  (0x6F, LogicalKeyboardKey.numpadDivide), (0x70, LogicalKeyboardKey.f1),
  (0x71, LogicalKeyboardKey.f2), (0x72, LogicalKeyboardKey.f3),
  (0x73, LogicalKeyboardKey.f4), (0x74, LogicalKeyboardKey.f5),
  (0x75, LogicalKeyboardKey.f6), (0x76, LogicalKeyboardKey.f7),
  (0x77, LogicalKeyboardKey.f8), (0x78, LogicalKeyboardKey.f9),
  (0x79, LogicalKeyboardKey.f10), (0x7A, LogicalKeyboardKey.f11),
  (0x7B, LogicalKeyboardKey.f12), (0x7C, LogicalKeyboardKey.f13),
  (0x7D, LogicalKeyboardKey.f14), (0x7E, LogicalKeyboardKey.f15),
  (0x7F, LogicalKeyboardKey.f16), (0x80, LogicalKeyboardKey.f17),
  (0x81, LogicalKeyboardKey.f18), (0x82, LogicalKeyboardKey.f19),
  (0x83, LogicalKeyboardKey.f20), (0x90, LogicalKeyboardKey.numLock),
  (0xBA, LogicalKeyboardKey.semicolon),
  (0xBB, LogicalKeyboardKey.equal), (0xBC, LogicalKeyboardKey.comma),
  (0xBD, LogicalKeyboardKey.minus), (0xBE, LogicalKeyboardKey.period),
  (0xBF, LogicalKeyboardKey.slash), (0xC0, LogicalKeyboardKey.backquote),
  (0xDB, LogicalKeyboardKey.bracketLeft), (0xDC, LogicalKeyboardKey.backslash),
  (0xDD, LogicalKeyboardKey.bracketRight), (0xDE, LogicalKeyboardKey.quote),
];

void main() {
  test('every named key maps back to the virtual key the engine named it from',
      () {
    for (final (vk, logical) in _engine) {
      expect(windowsVirtualKey(logical.keyId), vk, reason: logical.debugName);
      expect(windowsKeyOf(vk), logical.keyId, reason: logical.debugName);
    }
  });

  test('letters and digits, as the engine names them: the character', () {
    for (var vk = 0x41; vk <= 0x5A; vk++) {
      final logical = LogicalKeyboardKey.findKeyByKeyId(vk + 0x20)!;
      expect(windowsVirtualKey(logical.keyId), vk, reason: logical.debugName);
      expect(windowsKeyOf(vk), logical.keyId, reason: logical.debugName);
    }
    for (var vk = 0x30; vk <= 0x39; vk++) {
      expect(windowsVirtualKey(vk), vk);
      expect(windowsKeyOf(vk), vk);
    }
    expect(windowsVirtualKey(LogicalKeyboardKey.keyO.keyId), 0x4F);
    expect(windowsVirtualKey(LogicalKeyboardKey.digit7.keyId), 0x37);
  });

  test('keys of non-US layouts with no named logical key keep their id', () {
    // The ISO key beside left Shift (VK_OEM_102), VK_OEM_8 and VK_OEM_AX: the
    // engine passes the virtual key through as the logical id.
    for (final vk in [0xDF, 0xE1, 0xE2]) {
      expect(windowsVirtualKey(vk), vk);
      expect(windowsKeyOf(vk), vk);
    }
    expect(
        windowsKeyId(0xE2, PhysicalKeyboardKey.intlBackslash.usbHidUsage), 0xE2);
  });

  test("Brazil's ABNT keys share those ids, and their position decides", () {
    // The engine lowercases 0xC0 to 0xDE, so ABNT_C1 (the /? key) is named
    // 0xE1 and ABNT_C2 (its keypad separator) 0xE2: VK_OEM_AX's and
    // VK_OEM_102's ids. Registered by id alone, either would never fire;
    // compared or labelled by id alone, the separator would be the ISO key.
    final intlRo = PhysicalKeyboardKey.intlRo.usbHidUsage;
    final numpadComma = PhysicalKeyboardKey.numpadComma.usbHidUsage;
    expect(windowsKeyId(0xE1, intlRo), 0xC1);
    expect(windowsKeyId(0xE2, numpadComma), 0xC2);
    expect(windowsVirtualKey(0xC1), 0xC1);
    expect(windowsVirtualKey(0xC2), 0xC2);
    expect(windowsKeyOf(0xC1), 0xC1, reason: 'its label is its own');
    expect(windowsKeyOf(0xC2), 0xC2);
    expect(windowsLabelledKeys, containsAll([0xC1, 0xC2]));
  });

  test('keypad digits, the keypad decimal and keypad Enter are not bindable',
      () {
    // Two virtual keys each, by NumLock (measured: no one registration fires
    // in both states, and with Shift held neither fires), named once by the
    // engine; keypad Enter reaches Windows as VK_RETURN.
    for (final key in [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
      LogicalKeyboardKey.numpadDecimal, LogicalKeyboardKey.numpadEnter,
      // Named by scan code, and VK_CLEAR on US (measured).
      LogicalKeyboardKey.numpadEqual,
    ]) {
      expect(windowsVirtualKey(key.keyId), isNull, reason: key.debugName);
    }
  });

  test('a key nothing on Windows names is not bindable', () {
    expect(windowsVirtualKey(LogicalKeyboardKey.tab.keyId), isNull);
    expect(windowsVirtualKey(0xE9), isNull, reason: 'é is not a virtual key');
    expect(windowsVirtualKey(LogicalKeyboardKey.intlBackslash.keyId), isNull,
        reason: 'on Windows the ISO key is named by its virtual key, 0xE2');
  });

  test('every key a US recording can bind registers, but the excluded ones', () {
    final excluded = {
      for (final k in [
        PhysicalKeyboardKey.numpad0, PhysicalKeyboardKey.numpad1,
        PhysicalKeyboardKey.numpad2, PhysicalKeyboardKey.numpad3,
        PhysicalKeyboardKey.numpad4, PhysicalKeyboardKey.numpad5,
        PhysicalKeyboardKey.numpad6, PhysicalKeyboardKey.numpad7,
        PhysicalKeyboardKey.numpad8, PhysicalKeyboardKey.numpad9,
        PhysicalKeyboardKey.numpadDecimal, PhysicalKeyboardKey.numpadEnter,
        PhysicalKeyboardKey.numpadEqual, PhysicalKeyboardKey.intlBackslash,
        PhysicalKeyboardKey.intlRo, PhysicalKeyboardKey.intlYen,
      ])
        k.usbHidUsage,
    };
    for (final physical in bindableKeys) {
      final chord = KeyChord.us(physical, Modifiers.ctrl)!;
      expect(windowsVirtualKey(chord.windowsKey) == null,
          excluded.contains(physical),
          reason: PhysicalKeyboardKey.findKeyByCode(physical)!.debugName);
    }
  });

  test('modifiers become RegisterHotKey flags', () {
    expect(windowsModifiers(Modifiers.alt), 0x1);
    expect(windowsModifiers(Modifiers.ctrl), 0x2);
    expect(windowsModifiers(Modifiers.shift), 0x4);
    expect(windowsModifiers(Modifiers.meta), 0x8);
    expect(
        windowsModifiers(Modifiers.meta | Modifiers.ctrl | Modifiers.shift),
        0xE);
    expect(windowsModifiers(Modifiers.none), 0);
  });

  test('every labelled key is one a chord can hold', () {
    for (final vk in windowsLabelledKeys) {
      expect(windowsVirtualKey(windowsKeyOf(vk)), vk,
          reason: '0x${vk.toRadixString(16)}');
    }
  });
}
