import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/png.dart';

void main() {
  test('the CRC is the one PNG chunks carry', () {
    // The standard check value, and the CRC every PNG ends with.
    expect(crc32('123456789'.codeUnits), 0xCBF43926);
    expect(crc32('IEND'.codeUnits), 0xAE426082);
  });

  // Two opaque pixels and two clear ones: straight alpha, so a clear pixel
  // keeps no colour worth comparing.
  final pixels = Uint8List.fromList([
    255, 0, 0, 255, /**/ 0, 255, 0, 255, //
    0, 0, 255, 255, /**/ 0, 0, 0, 0,
  ]);

  test('the header names the size and RGBA, the data inflates to the rows', () {
    final png = encodePng(2, 2, pixels);
    expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final view = ByteData.sublistView(png);
    expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
    expect(view.getUint32(16), 2);
    expect(view.getUint32(20), 2);
    expect(png.sublist(24, 29), [8, 6, 0, 0, 0]);
    final idatLength = view.getUint32(33);
    expect(String.fromCharCodes(png.sublist(37, 41)), 'IDAT');
    final rows = ZLibCodec().decode(png.sublist(41, 41 + idatLength));
    expect(rows, [0, ...pixels.sublist(0, 8), 0, ...pixels.sublist(8)]);
    expect(png.sublist(png.length - 12),
        [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]);
  });

  testWidgets('Flutter decodes it to the same pixels', (tester) async {
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(encodePng(2, 2, pixels));
      final frame = await codec.getNextFrame();
      final bytes =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      return (frame.image.width, frame.image.height, bytes!.buffer.asUint8List());
    });
    expect(decoded!.$1, 2);
    expect(decoded.$2, 2);
    expect(decoded.$3.sublist(0, 12), pixels.sublist(0, 12));
    expect(decoded.$3[15], 0, reason: 'the clear pixel stays clear');
  });

  test('pixels that do not fill the size are refused', () {
    expect(() => encodePng(2, 2, Uint8List(15)), throwsArgumentError);
    expect(() => encodePng(2, 2, Uint8List(17)), throwsArgumentError);
    expect(() => encodePng(0, 1, Uint8List(0)), throwsArgumentError);
  });
}
