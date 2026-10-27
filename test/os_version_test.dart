import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/os_version.dart';

void main() {
  group('macOSMajorVersion', () {
    test('reads the major version out of macOS\'s own version string', () {
      // What `Platform.operatingSystemVersion` returns on a Mac.
      expect(macOSMajorVersion('Version 15.1 (Build 24B83)'), 15);
      expect(macOSMajorVersion('Version 13.6.9 (Build 22G830)'), 13);
      expect(macOSMajorVersion('Version 14.0 (Build 23A344)'), 14);
      expect(macOSMajorVersion('Version 26.0.1 (Build 25A362)'), 26);
    });

    test('a major version with no minor is still a major version', () {
      expect(macOSMajorVersion('Version 15 (Build 24A335)'), 15);
    });

    test('anything else is unknown, never a guess', () {
      expect(macOSMajorVersion(''), isNull);
      expect(macOSMajorVersion('garbage'), isNull);
      expect(macOSMajorVersion('Version x.y (Build z)'), isNull);
      // Windows' form, and a bare number: not macOS's string, so not read.
      expect(macOSMajorVersion('"Windows 10 Pro" 10.0 (Build 22631)'), isNull);
      expect(macOSMajorVersion('15.1'), isNull);
    });
  });
}
