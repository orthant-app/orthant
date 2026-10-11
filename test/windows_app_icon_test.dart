import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/windows_app_icon.dart';

/// The one decision in reading an icon: where its shape comes from. The
/// Win32 calls around it run only on Windows, and the VM checks them.
void main() {
  final white = [0xFF, 0xFF, 0xFF, 0x00];
  final black = [0x00, 0x00, 0x00, 0x00];

  test('an icon with its own alpha keeps it, in RGBA order', () {
    final color = Uint8List.fromList([10, 20, 30, 128, 1, 2, 3, 255]);
    // The mask says "transparent" for both; alpha wins.
    final mask = Uint8List.fromList([...white, ...white]);
    expect(iconBitsToRgba(color, mask), [30, 20, 10, 128, 3, 2, 1, 255]);
  });

  test('an icon with no alpha takes its shape from the mask', () {
    final color = Uint8List.fromList([10, 20, 30, 0, 1, 2, 3, 0]);
    final mask = Uint8List.fromList([...black, ...white]);
    expect(iconBitsToRgba(color, mask), [30, 20, 10, 255, 3, 2, 1, 0]);
  });

  test('with neither alpha nor a usable mask it is opaque', () {
    final color = Uint8List.fromList([10, 20, 30, 0, 1, 2, 3, 0]);
    expect(iconBitsToRgba(color, null), [30, 20, 10, 255, 3, 2, 1, 255]);
    expect(iconBitsToRgba(color, Uint8List.fromList(black)),
        [30, 20, 10, 255, 3, 2, 1, 255],
        reason: 'a mask of another size describes some other image');
  });
}
