import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/windows_version_resource.dart';

void main() {
  test('decodes FILEVERSION 1,0,3,7 as 1.0.3 build 7', () {
    // dwFileVersionMS = major << 16 | minor; dwFileVersionLS = patch << 16 | build.
    final v = versionFromFixedInfo(0x00010000, 0x00030007);
    expect(v.short, '1.0.3');
    expect(v.build, '7');
  });

  test('keeps each component within its 16 bits', () {
    final v = versionFromFixedInfo(0x0002000A, 0x000BFFFF);
    expect(v.short, '2.10.11');
    expect(v.build, '65535');
  });
}
