import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// A PNG of [width] x [height] straight-alpha RGBA pixels, 8 bits a channel,
/// rows top first.
///
/// The overlay's chip draws the captured app's icon from PNG bytes, which is
/// what macOS has always sent; Windows reads an icon as raw pixels, so it
/// encodes them here. Unfiltered rows, zlib from `dart:io`: an icon is a few
/// kilobytes, so the encoder's simplicity costs nothing worth having back.
Uint8List encodePng(int width, int height, Uint8List rgba) {
  if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
    throw ArgumentError('${rgba.length} bytes for $width x $height');
  }
  final rows = BytesBuilder(copy: false);
  final stride = width * 4;
  for (var y = 0; y < height; y++) {
    rows.addByte(0); // filter type: none
    rows.add(Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // colour type: RGBA; compression, filter, interlace 0
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = Uint8List.fromList([...type.codeUnits, ...data]);
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(typed)
      ..add((ByteData(4)..setUint32(0, crc32(typed))).buffer.asUint8List());
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibCodec().encode(rows.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

/// The CRC-32 PNG chunks carry (ISO 3309, the one zlib and Ethernet use).
int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return c ^ 0xFFFFFFFF;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
}, growable: false);
