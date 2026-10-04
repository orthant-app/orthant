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
/// exists, and a throw there is a menu that never appears. The catch-all
/// below is what makes that guarantee actually hold across a failed
/// allocation, not just a failed Win32 call; do not simplify it away.
///
/// Windows only. `package:win32` resolves `version.dll` on first call, so
/// importing this library on macOS is harmless and calling it there is not.
/// Signatures are `win32` 6.4.0's: `Win32Result` for the two `GetLastError`
/// style calls, a plain `bool` for `VerQueryValue`, `PCWSTR` for strings.
///
/// The four pointers are allocated inside the try, not before it, and freed
/// in reverse order in the finally with null checks: allocating them ahead
/// of the try would leak whichever ones already succeeded if a later
/// allocation (or `toNativeUtf16`) threw, since the finally that frees them
/// would never be entered.
({String short, String build})? readFixedFileVersion() {
  Pointer<Utf16>? pathPtr;
  Pointer<Utf16>? subBlockPtr;
  Pointer<Pointer<VS_FIXEDFILEINFO>>? block;
  Pointer<Uint32>? len;
  Pointer<Uint8>? buffer;
  try {
    pathPtr = Platform.resolvedExecutable.toNativeUtf16();
    subBlockPtr = r'\'.toNativeUtf16();
    block = calloc<Pointer<VS_FIXEDFILEINFO>>();
    len = calloc<Uint32>();
    final path = PCWSTR(pathPtr);
    final subBlock = PCWSTR(subBlockPtr);
    final size = GetFileVersionInfoSize(path, null).value;
    if (size == 0) return null;
    buffer = calloc<Uint8>(size);
    if (!GetFileVersionInfo(path, size, buffer).value) return null;
    if (!VerQueryValue(buffer, subBlock, block.cast(), len)) return null;
    if (block.value == nullptr) return null;
    final info = block.value.ref;
    return versionFromFixedInfo(info.dwFileVersionMS, info.dwFileVersionLS);
  } catch (_) {
    return null;
  } finally {
    if (buffer != null) calloc.free(buffer);
    if (len != null) calloc.free(len);
    if (block != null) calloc.free(block);
    if (subBlockPtr != null) calloc.free(subBlockPtr);
    if (pathPtr != null) calloc.free(pathPtr);
  }
}

/// The `FileDescription` string of the executable at [path] (what Task
/// Manager names a process, and the name the overlay's app chip will show,
/// spec §5.2), or null if it has none. Never throws, for the reason
/// [readFixedFileVersion] gives, with the same allocation discipline: every
/// pointer is allocated inside the try and freed in reverse in the finally.
String? readFileDescription(String path) {
  Pointer<Utf16>? pathPtr;
  Pointer<Utf16>? translationKey;
  Pointer<Utf16>? descriptionKey;
  Pointer<Pointer>? value;
  Pointer<Uint32>? len;
  Pointer<Uint8>? buffer;
  try {
    pathPtr = path.toNativeUtf16();
    translationKey = r'\VarFileInfo\Translation'.toNativeUtf16();
    value = calloc<Pointer>();
    len = calloc<Uint32>();
    final file = PCWSTR(pathPtr);
    final size = GetFileVersionInfoSize(file, null).value;
    if (size == 0) return null;
    buffer = calloc<Uint8>(size);
    if (!GetFileVersionInfo(file, size, buffer).value) return null;
    if (!VerQueryValue(buffer, PCWSTR(translationKey), value, len) ||
        len.value < 4 ||
        value.value == nullptr) {
      return null;
    }
    // The first (language, code page) pair names the string table to read.
    final pair = value.value.cast<Uint16>();
    final table = pair[0].toRadixString(16).padLeft(4, '0') +
        pair[1].toRadixString(16).padLeft(4, '0');
    descriptionKey =
        '\\StringFileInfo\\$table\\FileDescription'.toNativeUtf16();
    if (!VerQueryValue(buffer, PCWSTR(descriptionKey), value, len) ||
        len.value == 0 ||
        value.value == nullptr) {
      return null;
    }
    final description = value.value.cast<Utf16>().toDartString().trim();
    return description.isEmpty ? null : description;
  } catch (_) {
    return null;
  } finally {
    if (buffer != null) calloc.free(buffer);
    if (len != null) calloc.free(len);
    if (value != null) calloc.free(value);
    if (descriptionKey != null) calloc.free(descriptionKey);
    if (translationKey != null) calloc.free(translationKey);
    if (pathPtr != null) calloc.free(pathPtr);
  }
}
