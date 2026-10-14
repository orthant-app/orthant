import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/windows_accent.dart';

import 'support/accent_palettes.dart';

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
    expect(
        accentFromPalette(palette),
        const AccentColors(
            light: 0xFF0067C0,
            dark: 0xFF4CC2FF,
            linkLight: 0xFF003E92,
            linkDark: 0xFF99EBFF));
  });

  test('light is the first darker shade and dark the second lighter one, '
      'a link one shade further, opaque whatever the unused byte holds', () {
    // Every entry distinct, so a wrong index or byte order cannot pass.
    final palette = Uint8List.fromList([
      for (var i = 0; i < 8; i++) ...[i * 16, i * 16 + 1, i * 16 + 2, 0x7F],
    ]);
    expect(
        accentFromPalette(palette),
        const AccentColors(
            light: 0xFF404142,
            dark: 0xFF101112,
            linkLight: 0xFF505152,
            linkDark: 0xFF000102));
  });

  test('a link is WinUI\'s link text: the second darker shade in a light '
      'theme, the third lighter one in a dark theme, whatever the accent', () {
    for (final MapEntry(key: name, value: palette)
        in measuredPalettes.entries) {
      final accent = accentFromPalette(paletteBytes(palette))!;
      expect(accent.linkLight, paletteShade(palette, 5), reason: name);
      expect(accent.linkDark, paletteShade(palette, 0), reason: name);
      expect(accent.light, paletteShade(palette, 4), reason: name);
      expect(accent.dark, paletteShade(palette, 1), reason: name);
    }
  });

  test('two accents differing only in a link are different accents', () {
    // Built at run time: const instances are canonicalised, and would compare
    // equal with == deleted.
    AccentColors withLink(int link) =>
        AccentColors(light: 1, dark: 2, linkLight: link, linkDark: 4);
    expect(withLink(3), withLink(3));
    expect(withLink(3).hashCode, withLink(3).hashCode);
    expect(withLink(3), isNot(withLink(5)));
    expect(withLink(3),
        isNot(AccentColors(light: 1, dark: 2, linkLight: 3, linkDark: 6)));
    expect(const AccentColors(light: 1, dark: 2), isNot(withLink(3)));
  });

  test('the accent line keeps the form a reader of the log looks for', () {
    // The acceptance harness finds 'AccentColors(light: ..., dark: ...)' in
    // the app's log, closing bracket included.
    expect(
        const AccentColors(
                light: 0xFF0067C0,
                dark: 0xFF4CC2FF,
                linkLight: 0xFF003E92,
                linkDark: 0xFF99EBFF)
            .toString(),
        'AccentColors(light: 0xff0067c0, dark: 0xff4cc2ff), '
        'links (light: 0xff003e92, dark: 0xff99ebff)');
    expect(const AccentColors(light: 0xFF953D96, dark: 0xFFA550A7).toString(),
        'AccentColors(light: 0xff953d96, dark: 0xffa550a7)');
  });

  test('a palette shorter than eight colours, or none, is no accent', () {
    expect(accentFromPalette(Uint8List(31)), isNull);
    expect(accentFromPalette(null), isNull);
    expect(accentFromPalette(Uint8List(36)), isNotNull,
        reason: 'longer is read by its first eight');
  });
}
