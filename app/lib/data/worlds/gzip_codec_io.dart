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
      return output.takeBytes();
    });

Stream<List<int>> _chunks(Uint8List bytes) async* {
  const chunkSize = 64 * 1024;
  for (var offset = 0; offset < bytes.length; offset += chunkSize) {
    final end = (offset + chunkSize).clamp(0, bytes.length);
    yield Uint8List.sublistView(bytes, offset, end);
  }
}
