import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

Future<Uint8List> gzipEncode(Uint8List bytes) =>
    Isolate.run(() => Uint8List.fromList(gzip.encode(bytes)));

Future<Uint8List> gzipDecode(Uint8List bytes, {required int maxLength}) =>
    Isolate.run(() => _decodeBounded(bytes, maxLength));

/// Streams the inflated output and aborts as soon as it exceeds [maxLength],
/// so a gzip bomb never materializes in full.
Uint8List _decodeBounded(Uint8List bytes, int maxLength) {
  final builder = BytesBuilder(copy: false);
  final sink = ZLibDecoder(raw: false).startChunkedConversion(
    _BoundedByteSink(builder, maxLength),
  );
  try {
    sink.add(bytes);
    sink.close();
  } on FormatException {
    rethrow;
  }
  return builder.takeBytes();
}

final class _BoundedByteSink extends ByteConversionSink {
  _BoundedByteSink(this._builder, this._maxLength);

  final BytesBuilder _builder;
  final int _maxLength;

  @override
  void add(List<int> chunk) {
    if (_builder.length + chunk.length > _maxLength) {
      throw const FormatException('Compressed world payload is too large');
    }
    _builder.add(chunk);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    add(chunk.sublist(start, end));
    if (isLast) close();
  }

  @override
  void close() {}
}
