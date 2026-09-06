import 'dart:typed_data';

Future<Uint8List> gzipEncode(Uint8List bytes) => Future<Uint8List>.error(
  UnsupportedError('gzip is unavailable on this platform'),
);
Future<Uint8List> gzipDecode(Uint8List bytes, {required int maxOutputBytes}) =>
    Future<Uint8List>.error(
      UnsupportedError('gzip is unavailable on this platform'),
    );
