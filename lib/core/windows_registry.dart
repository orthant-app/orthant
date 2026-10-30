import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// String values in the current user's hive, shared by the stores that keep
// Orthant's own settings there (`RegistryUpdateStore`, `RegistryLanguageStore`).
// Every call allocates inside its try and frees in the finally, and none
// throws: a value that cannot be read reads as absent, and one that cannot be
// written or deleted is left as it was.
//
// Windows only.

/// The `REG_SZ` value [value] under [key] in `HKEY_CURRENT_USER`, trimmed;
/// null when it is absent, is not a string, is longer than 255 characters, or
/// cannot be read.
String? readUserString(String key, String value) {
  Pointer<Utf16>? keyPtr;
  Pointer<Utf16>? valuePtr;
  Pointer<Uint32>? size;
  Pointer<Uint16>? data;
  try {
    keyPtr = key.toNativeUtf16();
    valuePtr = value.toNativeUtf16();
    size = calloc<Uint32>()..value = 512;
    data = calloc<Uint16>(256);
    final result = RegGetValue(HKEY_CURRENT_USER, PCWSTR(keyPtr),
        PCWSTR(valuePtr), RRF_RT_REG_SZ, null, data.cast(), size);
    if (result != ERROR_SUCCESS) return null;
    return data.cast<Utf16>().toDartString().trim();
  } catch (_) {
    return null;
  } finally {
    if (data != null) calloc.free(data);
    if (size != null) calloc.free(size);
    if (valuePtr != null) calloc.free(valuePtr);
    if (keyPtr != null) calloc.free(keyPtr);
  }
}

/// Writes [text] as the `REG_SZ` value [value] under [key] in
/// `HKEY_CURRENT_USER`, creating the key if need be.
void writeUserString(String key, String value, String text) {
  Pointer<Utf16>? keyPtr;
  Pointer<Utf16>? valuePtr;
  Pointer<Utf16>? dataPtr;
  try {
    keyPtr = key.toNativeUtf16();
    valuePtr = value.toNativeUtf16();
    dataPtr = text.toNativeUtf16();
    // REG_SZ counts its bytes with the terminator.
    RegSetKeyValue(HKEY_CURRENT_USER, PCWSTR(keyPtr), PCWSTR(valuePtr), REG_SZ,
        dataPtr, (text.length + 1) * 2);
  } catch (_) {
    // Unwritten: read back as it was.
  } finally {
    if (dataPtr != null) calloc.free(dataPtr);
    if (valuePtr != null) calloc.free(valuePtr);
    if (keyPtr != null) calloc.free(keyPtr);
  }
}

/// Deletes the value [value] under [key] in `HKEY_CURRENT_USER`; nothing
/// happens when it is not there.
void deleteUserValue(String key, String value) {
  Pointer<Utf16>? keyPtr;
  Pointer<Utf16>? valuePtr;
  try {
    keyPtr = key.toNativeUtf16();
    valuePtr = value.toNativeUtf16();
    RegDeleteKeyValue(HKEY_CURRENT_USER, PCWSTR(keyPtr), PCWSTR(valuePtr));
  } catch (_) {
    // Left: read back as it was.
  } finally {
    if (valuePtr != null) calloc.free(valuePtr);
    if (keyPtr != null) calloc.free(keyPtr);
  }
}
