library;

import 'dart:typed_data';

import 'gzip_codec_stub.dart'
    if (dart.library.io) 'gzip_codec_io.dart'
    if (dart.library.js_interop) 'gzip_codec_web.dart'
    as implementation;

Future<Uint8List> gzipEncode(Uint8List bytes) =>
    implementation.gzipEncode(bytes);

/// Inflates [bytes], refusing any payload larger than [maxLength].
///
/// World payloads have a fixed known size, so a compressed stream that expands
/// past it is malicious or corrupt either way. Enforcing the bound during
/// decompression keeps a small hostile file from exhausting memory before the
/// codec can reject it.
Future<Uint8List> gzipDecode(Uint8List bytes, {required int maxLength}) =>
    implementation.gzipDecode(bytes, maxLength: maxLength);
