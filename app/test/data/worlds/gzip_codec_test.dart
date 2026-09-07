import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/gzip_codec.dart';

void main() {
  test('bounded decode accepts the exact limit', () async {
    final raw = Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xff));
    final compressed = await gzipEncode(raw);

    final decoded = await gzipDecode(compressed, maxOutputBytes: raw.length);

    expect(decoded, raw);
  });

  test('bounded decode rejects expansion past the limit', () async {
    final compressed = await gzipEncode(Uint8List(1024));

    await expectLater(
      gzipDecode(compressed, maxOutputBytes: 1023),
      throwsA(isA<FormatException>()),
    );
  });
}
