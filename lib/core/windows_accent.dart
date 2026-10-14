import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'window_controller.dart' show AccentColors;

/// Reads Windows' accent palette, or null. [readAccentPalette] is the real
/// one; a test hands the controller a fake, since `advapi32.dll` does not
/// exist on the Mac that runs the suite.
typedef AccentPaletteReader = Uint8List? Function();

/// The accent Windows' own controls draw with, from its `AccentPalette`.
///
/// The palette is eight colours of four bytes each (red, green, blue and one
/// unused), lightest first: three lighter shades of the accent, the accent,
/// three darker shades, and an eighth no control uses. A light theme fills an
/// accent control with the first darker shade and a dark theme with the
/// second lighter one (the default blue: #0067C0 and #4CC2FF, measured on
/// Windows 11 25H2), so those are the two fills returned. Link text is one
/// shade further each way, WinUI's `AccentTextFillColorPrimary`: the second
/// darker shade and the third lighter one (#003E92 and #99EBFF). Null for a
/// palette shorter than the eight.
///
/// Not `DwmGetColorizationColor`, which on the same machine answered
/// 0xE3006FC4: the colour DWM blends into a window frame, not the accent.
///
/// Pure, so it is tested on the Mac.
AccentColors? accentFromPalette(Uint8List? palette) {
  if (palette == null || palette.length < 32) return null;
  int shade(int i) =>
      0xFF000000 |
      palette[i * 4] << 16 |
      palette[i * 4 + 1] << 8 |
      palette[i * 4 + 2];
  return AccentColors(
    light: shade(4),
    dark: shade(1),
    linkLight: shade(5),
    linkDark: shade(0),
  );
}

/// `AccentPalette` under
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent`, which
/// Windows' Settings rewrites whenever the accent changes, or null. Never
/// throws, for the reason `readFixedFileVersion` gives, with the same
/// allocation discipline: every pointer is allocated inside the try and freed
/// in reverse in the finally.
///
/// Windows only. `package:win32` resolves `advapi32.dll` on first call, so
/// importing this library on macOS is harmless, and calling it there returns
/// null: the library fails to load inside the try.
Uint8List? readAccentPalette() {
  Pointer<Utf16>? keyPtr;
  Pointer<Utf16>? valuePtr;
  Pointer<Uint8>? data;
  Pointer<Uint32>? size;
  try {
    keyPtr = r'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
        .toNativeUtf16();
    valuePtr = 'AccentPalette'.toNativeUtf16();
    data = calloc<Uint8>(64);
    size = calloc<Uint32>()..value = 64;
    final result = RegGetValue(HKEY_CURRENT_USER, PCWSTR(keyPtr),
        PCWSTR(valuePtr), RRF_RT_REG_BINARY, null, data.cast(), size);
    if (result != ERROR_SUCCESS || size.value < 32) return null;
    return Uint8List.fromList(data.asTypedList(size.value));
  } catch (_) {
    return null;
  } finally {
    if (size != null) calloc.free(size);
    if (data != null) calloc.free(data);
    if (valuePtr != null) calloc.free(valuePtr);
    if (keyPtr != null) calloc.free(keyPtr);
  }
}
