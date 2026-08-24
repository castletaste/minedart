import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browser gzip through the standards-based Compression Streams API.
Future<Uint8List> gzipEncode(Uint8List bytes) =>
    _transform(bytes, 'gzip', true);
Future<Uint8List> gzipDecode(Uint8List bytes) =>
    _transform(bytes, 'gzip', false);

Future<Uint8List> _transform(
  Uint8List bytes,
  String format,
  bool encode,
) async {
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
  final output = await web.Response(stream).arrayBuffer().toDart;
  return Uint8List.view(output.toDart);
}
