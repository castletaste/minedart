library;

import 'dart:typed_data';

import 'gzip_codec_stub.dart'
    if (dart.library.io) 'gzip_codec_io.dart'
    if (dart.library.js_interop) 'gzip_codec_web.dart'
    as implementation;

Future<Uint8List> gzipEncode(Uint8List bytes) =>
    implementation.gzipEncode(bytes);
Future<Uint8List> gzipDecode(Uint8List bytes) =>
    implementation.gzipDecode(bytes);
