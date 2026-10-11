import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:win32/win32.dart';

import 'png.dart';

/// The icon the shell shows for the executable at [exePath], as a PNG, or
/// null when it has none that can be read. Windows only.
///
/// **Blocking, so never on the summon path.** `SHGetFileInfo` is documented as
/// able to block the calling thread (it may read the file, or ask a shell
/// extension), so the Windows controller runs this on a background isolate and
/// sends the result after the grid is up. It needs COM on the calling thread,
/// which a background isolate's thread has not got, so it initialises COM for
/// the call and releases it after.
///
/// Once its setup (COM, the path, the info record) has allocated, every handle
/// it creates is released on every path, and a failure after that is a null
/// return, not a throw. Only an allocation failure in that setup can throw
/// (off Windows, the ole32 lookup does), and it would skip `CoUninitialize`
/// and leak the path; its one caller, the controller's icon read, treats a
/// throw as no icon and tries again on the next summon.
Uint8List? readAppIconPng(String exePath) {
  final com = CoInitializeEx(COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  final path = exePath.toNativeUtf16();
  final info = calloc<SHFILEINFO>();
  try {
    final got = SHGetFileInfo(PCWSTR(path), FILE_FLAGS_AND_ATTRIBUTES(0), info,
        sizeOf<SHFILEINFO>(), SHGFI_ICON | SHGFI_LARGEICON);
    final icon = info.ref.hIcon;
    if (got == 0 || icon.address == 0) return null;
    try {
      return _iconPng(icon);
    } finally {
      DestroyIcon(icon);
    }
  } catch (_) {
    // A display nicety: any failure is "no icon", and the chip shows the
    // app's name alone, as it always could.
    return null;
  } finally {
    calloc.free(info);
    calloc.free(path);
    // S_OK and S_FALSE both took a reference; a thread already in another
    // apartment (RPC_E_CHANGED_MODE) took none.
    if (com.isOk) CoUninitialize();
  }
}

Uint8List? _iconPng(HICON icon) {
  final iconInfo = calloc<ICONINFO>();
  try {
    if (!GetIconInfo(icon, iconInfo).value) return null;
    final color = iconInfo.ref.hbmColor;
    final mask = iconInfo.ref.hbmMask;
    try {
      // A monochrome icon has no colour bitmap; an app's icon is never one.
      if (color.address == 0) return null;
      final size = _bitmapSize(color);
      if (size == null) return null;
      final (width, height) = size;
      final colorBits = _bitsOf(color, width, height);
      if (colorBits == null) return null;
      final maskBits = mask.address == 0 ? null : _bitsOf(mask, width, height);
      return encodePng(width, height, iconBitsToRgba(colorBits, maskBits));
    } finally {
      if (color.address != 0) DeleteObject(HGDIOBJ(color));
      if (mask.address != 0) DeleteObject(HGDIOBJ(mask));
    }
  } finally {
    calloc.free(iconInfo);
  }
}

(int, int)? _bitmapSize(HBITMAP bitmap) {
  final bm = calloc<BITMAP>();
  try {
    if (GetObject(HGDIOBJ(bitmap), sizeOf<BITMAP>(), bm) == 0) return null;
    final w = bm.ref.bmWidth;
    final h = bm.ref.bmHeight;
    // An icon is tens of pixels; anything else is not one worth drawing.
    return w > 0 && h > 0 && w <= 256 && h <= 256 ? (w, h) : null;
  } finally {
    calloc.free(bm);
  }
}

/// [bitmap]'s pixels as 32-bit BGRA, top row first, or null.
Uint8List? _bitsOf(HBITMAP bitmap, int width, int height) {
  final header = calloc<BITMAPINFO>();
  final bits = calloc<Uint8>(width * height * 4);
  final dc = CreateCompatibleDC(null);
  try {
    if (dc.address == 0) return null;
    header.ref.bmiHeader
      ..biSize = sizeOf<BITMAPINFOHEADER>()
      ..biWidth = width
      ..biHeight = -height // negative: top-down rows
      ..biPlanes = 1
      ..biBitCount = 32
      ..biCompression = BI_RGB;
    final lines =
        GetDIBits(dc, bitmap, 0, height, bits, header, DIB_RGB_COLORS);
    if (lines != height) return null;
    return Uint8List.fromList(bits.asTypedList(width * height * 4));
  } finally {
    if (dc.address != 0) DeleteDC(dc);
    calloc.free(bits);
    calloc.free(header);
  }
}

/// An icon's colour and mask bitmaps, both 32-bit BGRA rows, as straight RGBA.
///
/// A modern icon carries its own alpha; an older one has none (every alpha
/// byte zero) and its shape is the mask, black where the icon is drawn. With
/// no mask either, it is opaque.
@visibleForTesting
Uint8List iconBitsToRgba(Uint8List colorBgra, Uint8List? maskBgra) {
  final out = Uint8List(colorBgra.length);
  var hasAlpha = false;
  for (var i = 3; i < colorBgra.length; i += 4) {
    if (colorBgra[i] != 0) {
      hasAlpha = true;
      break;
    }
  }
  for (var i = 0; i + 3 < colorBgra.length; i += 4) {
    out[i] = colorBgra[i + 2];
    out[i + 1] = colorBgra[i + 1];
    out[i + 2] = colorBgra[i];
    out[i + 3] = hasAlpha
        ? colorBgra[i + 3]
        : maskBgra == null || maskBgra.length != colorBgra.length
            ? 0xFF
            : (maskBgra[i] == 0 ? 0xFF : 0);
  }
  return out;
}
