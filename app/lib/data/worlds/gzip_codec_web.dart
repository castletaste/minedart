import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browser gzip through the standards-based Compression Streams API.
Future<Uint8List> gzipEncode(Uint8List bytes) async {
  final transformer = web.CompressionStream('gzip');
  final stream = _pipe(bytes, transformer.readable, transformer.writable);
  final output = await web.Response(stream).arrayBuffer().toDart;
  return Uint8List.view(output.toDart);
}

/// Inflates the payload chunk by chunk, cancelling the stream as soon as the
/// output exceeds [maxLength] so a gzip bomb never fully materializes.
Future<Uint8List> gzipDecode(Uint8List bytes, {required int maxLength}) async {
  final transformer = web.DecompressionStream('gzip');
  final stream = _pipe(bytes, transformer.readable, transformer.writable);
  final reader = stream.getReader() as web.ReadableStreamDefaultReader;
  final output = Uint8List(maxLength);
  var length = 0;
  while (true) {
    final result = await reader.read().toDart;
    if (result.done) break;
    final chunk = (result.value! as JSUint8Array).toDart;
    if (length + chunk.length > maxLength) {
      await reader.cancel('payload too large'.toJS).toDart;
      throw const FormatException('Compressed world payload is too large');
    }
    output.setRange(length, length + chunk.length, chunk);
    length += chunk.length;
  }
  return Uint8List.sublistView(output, 0, length);
}

web.ReadableStream _pipe(
  Uint8List bytes,
  web.ReadableStream readable,
  web.WritableStream writable,
) => web.Blob(<web.BlobPart>[bytes.toJS].toJS).stream().pipeThrough(
  web.ReadableWritablePair(readable: readable, writable: writable),
);
