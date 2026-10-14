import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'window_controller.dart' show LoginItemStatus;

/// What one registry read found.
enum RegFound { absent, present, unreadable }

/// A registry value as read: what was found, and the data when present.
typedef RegRead<T> = ({RegFound found, T? data});

/// The name of Orthant's startup entry, under both keys below. Once a release
/// has written it, it is a published name: an older or newer build, and the
/// uninstaller, look for it there.
const kStartupValueName = 'Orthant';

/// The command a startup entry runs, as Windows' own launch reads it.
const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';

/// Windows' record of the user's choice in Task Manager's Startup apps page
/// and in Settings, keyed by the same value name.
const _approvedKey =
    r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

/// The two values launch at login lives in, behind an interface so the suite,
/// which runs on a Mac with no `advapi32.dll`, can supply its own.
///
/// Orthant writes only the Run value. The StartupApproved record is Windows':
/// Task Manager and Settings write it when the user turns the entry off or on
/// there, and it outlives a rewrite of the Run value (measured), so the
/// user's off in either place stands until they turn it on there again.
abstract class StartupRegistry {
  RegRead<String> readRun();
  RegRead<Uint8List> readApproved();

  /// Whether the value was written.
  bool writeRun(String command);

  /// Whether the value is gone, including when it was never there.
  bool deleteRun();
}

/// The command Orthant writes for [exe]: the path, quoted, as installers
/// write it, so a path with a space in it is still one argument.
String runCommandFor(String exe) => '"$exe"';

/// The executable a Run command names, or null for one that names none: the
/// quoted path when it starts with a quote, otherwise up to the first space.
String? runCommandExecutable(String command) {
  final c = command.trim();
  if (c.isEmpty) return null;
  if (c.startsWith('"')) {
    final end = c.indexOf('"', 1);
    return end < 0 ? null : c.substring(1, end);
  }
  final space = c.indexOf(' ');
  return space < 0 ? c : c.substring(0, space);
}

/// Windows paths compare without case, and either slash names one directory.
bool _samePath(String a, String b) => _path(a) == _path(b);
String _path(String p) => p.replaceAll('/', r'\').toLowerCase();

/// What the Run value and its StartupApproved record mean for this [exe].
///
/// Measured against Task Manager's Startup apps page and Settings' Startup
/// page on Windows 11 25H2: an entry with no record is on; the record's first
/// byte has its low bit set when the user turned the entry off (Task Manager
/// writes 0x02 and 0x03, Settings 0x00 and 0x01, each followed by the time of
/// the change); a record without its Run value lists nothing.
///
/// Off in Startup apps is [LoginItemStatus.requiresApproval], macOS's name
/// for the same state: registered, switched off by the user in the OS's own
/// settings, and remedied there. A Run value naming another copy of Orthant
/// is [LoginItemStatus.disabled] for this one, which that copy would replace.
/// Nothing that could not be read is ever [LoginItemStatus.enabled].
///
/// Pure, so it is tested on the Mac.
LoginItemStatus loginItemStatusOf({
  required RegRead<String> run,
  required RegRead<Uint8List> approved,
  required String exe,
}) {
  switch (run.found) {
    case RegFound.unreadable:
      return LoginItemStatus.unavailable;
    case RegFound.absent:
      return LoginItemStatus.disabled;
    case RegFound.present:
      break;
  }
  final named = runCommandExecutable(run.data ?? '');
  if (named == null || !_samePath(named, exe)) {
    return LoginItemStatus.disabled;
  }
  switch (approved.found) {
    case RegFound.unreadable:
      return LoginItemStatus.unavailable;
    case RegFound.absent:
      return LoginItemStatus.enabled;
    case RegFound.present:
      final record = approved.data;
      if (record == null || record.isEmpty) return LoginItemStatus.unavailable;
      return record[0] & 1 == 1
          ? LoginItemStatus.requiresApproval
          : LoginItemStatus.enabled;
  }
}

/// The real registry, in the current user's hive. Every call allocates inside
/// its try and frees in the finally, as `readAccentPalette` does, and never
/// throws: a failure is [RegFound.unreadable] or false.
///
/// Windows only, for the reason `readAccentPalette` gives.
class FfiStartupRegistry implements StartupRegistry {
  const FfiStartupRegistry();

  @override
  RegRead<String> readRun() {
    final bytes = _read(_runKey, RRF_RT_REG_SZ);
    if (bytes.found != RegFound.present) {
      return (found: bytes.found, data: null);
    }
    final data = bytes.data!;
    // UTF-16LE with its terminator, as RegGetValue writes it.
    final units = data.buffer.asUint16List(0, data.lengthInBytes ~/ 2);
    final end = units.indexOf(0);
    return (
      found: RegFound.present,
      data: String.fromCharCodes(end < 0 ? units : units.sublist(0, end)),
    );
  }

  @override
  RegRead<Uint8List> readApproved() => _read(_approvedKey, RRF_RT_REG_BINARY);

  RegRead<Uint8List> _read(String key, REG_ROUTINE_FLAGS type) {
    Pointer<Utf16>? keyPtr;
    Pointer<Utf16>? valuePtr;
    Pointer<Uint32>? size;
    Pointer<Uint8>? data;
    try {
      keyPtr = key.toNativeUtf16();
      valuePtr = kStartupValueName.toNativeUtf16();
      size = calloc<Uint32>();
      final probe = RegGetValue(HKEY_CURRENT_USER, PCWSTR(keyPtr),
          PCWSTR(valuePtr), type, null, null, size);
      if (probe == ERROR_FILE_NOT_FOUND) {
        return (found: RegFound.absent, data: null);
      }
      if (probe != ERROR_SUCCESS) {
        return (found: RegFound.unreadable, data: null);
      }
      if (size.value == 0) {
        return (found: RegFound.present, data: Uint8List(0));
      }
      data = calloc<Uint8>(size.value);
      final result = RegGetValue(HKEY_CURRENT_USER, PCWSTR(keyPtr),
          PCWSTR(valuePtr), type, null, data.cast(), size);
      if (result != ERROR_SUCCESS) {
        return (found: RegFound.unreadable, data: null);
      }
      return (
        found: RegFound.present,
        data: Uint8List.fromList(data.asTypedList(size.value)),
      );
    } catch (_) {
      return (found: RegFound.unreadable, data: null);
    } finally {
      if (data != null) calloc.free(data);
      if (size != null) calloc.free(size);
      if (valuePtr != null) calloc.free(valuePtr);
      if (keyPtr != null) calloc.free(keyPtr);
    }
  }

  @override
  bool writeRun(String command) {
    Pointer<Utf16>? keyPtr;
    Pointer<Utf16>? valuePtr;
    Pointer<Utf16>? dataPtr;
    try {
      keyPtr = _runKey.toNativeUtf16();
      valuePtr = kStartupValueName.toNativeUtf16();
      dataPtr = command.toNativeUtf16();
      // REG_SZ counts its bytes with the terminator.
      return RegSetKeyValue(HKEY_CURRENT_USER, PCWSTR(keyPtr),
              PCWSTR(valuePtr), REG_SZ, dataPtr, (command.length + 1) * 2) ==
          ERROR_SUCCESS;
    } catch (_) {
      return false;
    } finally {
      if (dataPtr != null) calloc.free(dataPtr);
      if (valuePtr != null) calloc.free(valuePtr);
      if (keyPtr != null) calloc.free(keyPtr);
    }
  }

  @override
  bool deleteRun() {
    Pointer<Utf16>? keyPtr;
    Pointer<Utf16>? valuePtr;
    try {
      keyPtr = _runKey.toNativeUtf16();
      valuePtr = kStartupValueName.toNativeUtf16();
      final result = RegDeleteKeyValue(
          HKEY_CURRENT_USER, PCWSTR(keyPtr), PCWSTR(valuePtr));
      return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND;
    } catch (_) {
      return false;
    } finally {
      if (valuePtr != null) calloc.free(valuePtr);
      if (keyPtr != null) calloc.free(keyPtr);
    }
  }
}

/// Opens Settings on its Startup apps page, where the user turns a startup
/// entry on or off; whether Windows took the request. Never throws.
///
/// Windows only.
bool openStartupAppsSettings() {
  Pointer<Utf16>? verb;
  Pointer<Utf16>? target;
  try {
    verb = 'open'.toNativeUtf16();
    target = 'ms-settings:startupapps'.toNativeUtf16();
    // Above 32 is success: ShellExecute's own convention.
    return ShellExecute(null, PCWSTR(verb), PCWSTR(target), null, null,
                SW_SHOWNORMAL)
            .address >
        32;
  } catch (_) {
    return false;
  } finally {
    if (target != null) calloc.free(target);
    if (verb != null) calloc.free(verb);
  }
}
