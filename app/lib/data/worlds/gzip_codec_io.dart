import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

Future<Uint8List> gzipEncode(Uint8List bytes) =>
    Isolate.run(() => Uint8List.fromList(gzip.encode(bytes)));
Future<Uint8List> gzipDecode(Uint8List bytes, {required int maxOutputBytes}) =>
    Isolate.run(() async {
      final output = BytesBuilder(copy: false);
      var outputLength = 0;
      await for (final chunk in gzip.decoder.bind(_chunks(bytes))) {
        outputLength += chunk.length;
        if (outputLength > maxOutputBytes) {
          throw const FormatException('Gzip output exceeds allowed length');
        }
        output.add(chunk);
      }
      final decoded = output.takeBytes();
      _validateGzip(bytes, decoded);
      return decoded;
    });

Stream<List<int>> _chunks(Uint8List bytes) async* {
  const chunkSize = 64 * 1024;
  for (var offset = 0; offset < bytes.length; offset += chunkSize) {
    final end = (offset + chunkSize).clamp(0, bytes.length);
    yield Uint8List.sublistView(bytes, offset, end);
  }
}

void _validateGzip(Uint8List bytes, Uint8List decoded) {
  // The VM decoder can yield the decompressed prefix when the final gzip
  // trailer is missing. MDRT must reject that prefix as a corrupt file.
  if (bytes.length < 18 ||
      bytes[0] != 0x1f ||
      bytes[1] != 0x8b ||
      bytes[2] != 8) {
    throw const FormatException('Invalid gzip stream');
  }
  final trailer = ByteData.sublistView(bytes, bytes.length - 8);
  final expectedCrc = trailer.getUint32(0, Endian.little);
  final expectedSize = trailer.getUint32(4, Endian.little);
  if (expectedSize != (decoded.length & 0xffffffff) ||
      expectedCrc != _crc32(decoded)) {
    throw const FormatException('Invalid gzip trailer');
  }
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
