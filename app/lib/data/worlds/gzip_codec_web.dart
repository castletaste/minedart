import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browser gzip through the standards-based Compression Streams API.
Future<Uint8List> gzipEncode(Uint8List bytes) =>
    _transform(bytes, 'gzip', true, maxOutputBytes: null);
Future<Uint8List> gzipDecode(Uint8List bytes, {required int maxOutputBytes}) =>
    _transform(bytes, 'gzip', false, maxOutputBytes: maxOutputBytes);

Future<Uint8List> _transform(
  Uint8List bytes,
  String format,
  bool encode, {
  required int? maxOutputBytes,
}) async {
  final input = web.Blob(<web.BlobPart>[bytes.toJS].toJS);
  final web.ReadableStream readable;
  final web.WritableStream writable;
  if (encode) {
    final transformer = web.CompressionStream(format);
    readable = transformer.readable;
    writable = transformer.writable;
  } else {
    final transformer = web.DecompressionStream(format);
    readable = transformer.readable;
    writable = transformer.writable;
  }
  final stream = input.stream().pipeThrough(
    web.ReadableWritablePair(readable: readable, writable: writable),
  );
  if (maxOutputBytes == null) {
    final output = await web.Response(stream).arrayBuffer().toDart;
    return Uint8List.view(output.toDart);
  }
  final reader = stream.getReader() as web.ReadableStreamDefaultReader;
  final output = BytesBuilder(copy: false);
  var outputLength = 0;
  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) break;
      final value = result.value;
      if (value == null || !value.isA<JSUint8Array>()) {
        throw const FormatException('Gzip stream returned invalid bytes');
      }
      final chunk = (value as JSUint8Array).toDart;
      outputLength += chunk.length;
      if (outputLength > maxOutputBytes) {
        await reader.cancel().toDart;
        throw const FormatException('Gzip output exceeds allowed length');
      }
      output.add(chunk);
    }
    return output.takeBytes();
  } finally {
    reader.releaseLock();
  }
}
