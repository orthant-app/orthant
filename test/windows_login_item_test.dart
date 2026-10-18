import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/windows_login_item.dart';

const _exe = r'C:\Users\someone\AppData\Local\Programs\Orthant\Orthant.exe';

// Built through functions so equality is tested, not const identity.
RegRead<String> run(String command) =>
    (found: RegFound.present, data: command);
RegRead<String> runOf(RegFound found) => (found: found, data: null);
RegRead<Uint8List> approved(List<int> bytes) =>
    (found: RegFound.present, data: Uint8List.fromList(bytes));
RegRead<Uint8List> approvedOf(RegFound found) => (found: found, data: null);

LoginItemStatus status(RegRead<String> r, RegRead<Uint8List> a) =>
    loginItemStatusOf(run: r, approved: a, exe: _exe);

void main() {
  group('what Task Manager and Settings show, as a status', () {
    // Every byte pattern below was read from the VM's registry after Task
    // Manager's or Settings' own toggle wrote it, or written there and then
    // read back through Task Manager's Startup apps page (Windows 11 25H2).
    final quoted = run('"$_exe"');

    test('a Run value naming this executable, with no record, is on', () {
      expect(status(quoted, approvedOf(RegFound.absent)),
          LoginItemStatus.enabled);
    });

    test("Task Manager's Enable and Disable", () {
      expect(status(quoted, approved([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
          LoginItemStatus.enabled);
      expect(
          status(quoted,
              approved([3, 0, 0, 0, 0xF2, 0x54, 0xA6, 0xA8, 0xCC, 0x5A, 0xDD, 1])),
          LoginItemStatus.requiresApproval);
    });

    test("Settings' on and off", () {
      expect(status(quoted, approved(List.filled(12, 0))),
          LoginItemStatus.enabled);
      expect(
          status(quoted,
              approved([1, 0, 0, 0, 0xA7, 0x0E, 0x65, 0xC7, 0xCB, 0x5A, 0xDD, 1])),
          LoginItemStatus.requiresApproval);
    });

    test('the low bit of the first byte is the switch, whatever else is set',
        () {
      expect(status(quoted, approved([6, 0, 0, 0])), LoginItemStatus.enabled);
      expect(status(quoted, approved([7, 0, 0, 0])),
          LoginItemStatus.requiresApproval);
    });

    test('no Run value is off, whatever the record says', () {
      expect(status(runOf(RegFound.absent), approved([3, 0, 0, 0])),
          LoginItemStatus.disabled,
          reason: 'measured: Task Manager lists no row for a record alone');
      expect(status(runOf(RegFound.absent), approvedOf(RegFound.absent)),
          LoginItemStatus.disabled);
    });

    test('a Run value naming another executable is off for this one', () {
      expect(
          status(run(r'"C:\src\orthant\build\windows\x64\runner\Debug\Orthant.exe"'),
              approvedOf(RegFound.absent)),
          LoginItemStatus.disabled,
          reason: 'that copy would start at login, not this one');
    });

    test('what cannot be read is never shown as on', () {
      expect(status(runOf(RegFound.unreadable), approvedOf(RegFound.absent)),
          LoginItemStatus.unavailable);
      expect(status(quoted, approvedOf(RegFound.unreadable)),
          LoginItemStatus.unavailable);
      expect(status(quoted, approved([])), LoginItemStatus.unavailable,
          reason: 'an empty record says nothing either way');
    });
  });

  group('the command a Run value holds', () {
    test('quoted, as Orthant writes it, and as installers write it', () {
      expect(runCommandFor(_exe), '"$_exe"');
      expect(runCommandExecutable('"$_exe"'), _exe);
      expect(runCommandExecutable('"$_exe" --minimized'), _exe);
    });

    test('unquoted, as some hand edits leave it', () {
      expect(runCommandExecutable(r'C:\Tools\Orthant.exe'), r'C:\Tools\Orthant.exe');
      expect(runCommandExecutable(r'C:\Tools\Orthant.exe --flag'),
          r'C:\Tools\Orthant.exe');
    });

    test('nothing to name, or a quote never closed', () {
      expect(runCommandExecutable(''), isNull);
      expect(runCommandExecutable('   '), isNull);
      expect(runCommandExecutable('"C:\\Tools\\Orthant.exe'), isNull);
    });

    test("Windows' paths ignore case and either slash", () {
      expect(
          status(run('"${_exe.toUpperCase().replaceAll(r'\', '/')}"'),
              approvedOf(RegFound.absent)),
          LoginItemStatus.enabled);
    });
  });
}
