import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Reads the app's version, or null. [readFixedFileVersion] is the real one;
/// a test hands the controller a fake, since `version.dll` does not exist on
/// the Mac that runs the suite.
typedef VersionReader = ({String short, String build})? Function();

/// The version CMake stamped into the exe, split the way `AppVersion` wants
/// it: `FILEVERSION 1,0,3,7` is `dwFileVersionMS = 0x0001_0000` and
/// `dwFileVersionLS = 0x0003_0007`.
///
/// Pure, so it is tested on the Mac. A build number above 65535 cannot fit
/// the resource's 16 bits; this project's are single digits.
({String short, String build}) versionFromFixedInfo(
    int fileVersionMS, int fileVersionLS) {
  final major = (fileVersionMS >> 16) & 0xFFFF;
  final minor = fileVersionMS & 0xFFFF;
  final patch = (fileVersionLS >> 16) & 0xFFFF;
  final build = fileVersionLS & 0xFFFF;
  return (short: '$major.$minor.$patch', build: '$build');
}

/// `VS_FIXEDFILEINFO` of the running executable, or null if Windows cannot
/// supply it. Never throws: this is read on the launch path before the tray
/// exists, and a throw there is a menu that never appears.
///
/// Windows only. `package:win32` resolves `version.dll` on first call, so
/// importing this library on macOS is harmless and calling it there is not.
/// Signatures are `win32` 6.4.0's: `Win32Result` for the two `GetLastError`
/// style calls, a plain `bool` for `VerQueryValue`, `PCWSTR` for strings.
({String short, String build})? readFixedFileVersion() {
  final path = PCWSTR(Platform.resolvedExecutable.toNativeUtf16());
  final subBlock = PCWSTR(r'\'.toNativeUtf16());
  final block = calloc<Pointer<VS_FIXEDFILEINFO>>();
  final len = calloc<Uint32>();
  Pointer<Uint8>? buffer;
  try {
    final size = GetFileVersionInfoSize(path, null).value;
    if (size == 0) return null;
    buffer = calloc<Uint8>(size);
    if (!GetFileVersionInfo(path, size, buffer).value) return null;
    if (!VerQueryValue(buffer, subBlock, block.cast(), len)) return null;
    if (block.value == nullptr) return null;
    final info = block.value.ref;
    return versionFromFixedInfo(info.dwFileVersionMS, info.dwFileVersionLS);
  } finally {
    if (buffer != null) calloc.free(buffer);
    calloc.free(len);
    calloc.free(block);
    calloc.free(subBlock);
    calloc.free(path);
  }
}
