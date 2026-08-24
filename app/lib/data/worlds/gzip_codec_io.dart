import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

Future<Uint8List> gzipEncode(Uint8List bytes) =>
    Isolate.run(() => Uint8List.fromList(gzip.encode(bytes)));
Future<Uint8List> gzipDecode(Uint8List bytes) =>
    Isolate.run(() => Uint8List.fromList(gzip.decode(bytes)));
