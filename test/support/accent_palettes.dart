import 'dart:typed_data';

/// Windows' own `AccentPalette` for a few accents, eight colours lightest
/// first (the eighth is unused), measured on the VM (Windows 11 25H2): the
/// default blue as Settings left it, the rest as Windows computed them when
/// uxtheme's `SetUserColorPreference` set that accent, since Settings refuses
/// to personalise an unactivated Windows.
const measuredPalettes = {
  'blue': '99EBFF 4CC2FF 0091F8 0078D4 0067C0 003E92 001A68 F7630C',
  'red': 'FB9D8B F46762 EF2733 E81123 D20E1E 9E0912 6F0306 69797E',
  'yellow gold': 'FFE845 FFD52A FFC20D FFB900 E19D00 9B5D00 5C2100 00B294',
  'sport green': '89F1A5 3AE872 14AE4C 10893E 0E7835 08521F 032E0B 00B7C3',
  'violet red': 'EFACF2 D95BE6 AB1DBE 881798 7B148B 5B0C6D 3F0451 BF0077',
  'gray': 'E7E5E4 BDB9B8 8E8988 7A7574 696363 403B3A 1B1515 EA005E',
};

/// [palette] as the registry holds it: red, green, blue and an unused byte.
Uint8List paletteBytes(String palette) => Uint8List.fromList([
      for (final hex in palette.split(' ')) ...[
        int.parse(hex.substring(0, 2), radix: 16),
        int.parse(hex.substring(2, 4), radix: 16),
        int.parse(hex.substring(4, 6), radix: 16),
        0,
      ],
    ]);

/// Entry [i] of [palette], opaque.
int paletteShade(String palette, int i) =>
    0xFF000000 | int.parse(palette.split(' ')[i], radix: 16);
