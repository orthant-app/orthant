import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/windows_accent.dart';

void main() {
  test('the default blue gives the shades Windows 11 fills its controls with',
      () {
    // AccentPalette as read from the VM's registry (Windows 11 25H2, the
    // default accent): #99EBFF #4CC2FF #0091F8 #0078D4 #0067C0 #003E92
    // #001A68 #F7630C, four bytes each.
    final palette = Uint8List.fromList([
      0x99, 0xEB, 0xFF, 0x00, 0x4C, 0xC2, 0xFF, 0x00, //
      0x00, 0x91, 0xF8, 0x00, 0x00, 0x78, 0xD4, 0x00, //
      0x00, 0x67, 0xC0, 0x00, 0x00, 0x3E, 0x92, 0x00, //
      0x00, 0x1A, 0x68, 0x00, 0xF7, 0x63, 0x0C, 0x00, //
    ]);
    expect(accentFromPalette(palette),
        const AccentColors(light: 0xFF0067C0, dark: 0xFF4CC2FF));
  });

  test('light is the first darker shade and dark the second lighter one, '
      'opaque whatever the unused byte holds', () {
    // Every entry distinct, so a wrong index or byte order cannot pass.
    final palette = Uint8List.fromList([
      for (var i = 0; i < 8; i++) ...[i * 16, i * 16 + 1, i * 16 + 2, 0x7F],
    ]);
    expect(accentFromPalette(palette),
        const AccentColors(light: 0xFF404142, dark: 0xFF101112));
  });

  test('a palette shorter than eight colours, or none, is no accent', () {
    expect(accentFromPalette(Uint8List(31)), isNull);
    expect(accentFromPalette(null), isNull);
    expect(accentFromPalette(Uint8List(36)), isNotNull,
        reason: 'longer is read by its first eight');
  });
}
