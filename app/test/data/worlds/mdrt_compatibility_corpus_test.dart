import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/mdrt_codec.dart';
import 'package:minedart/data/worlds/world_models.dart';
import 'package:minedart_core/src/block.dart';

void main() {
  final metadata = WorldMetadata(
    id: 'compatibility-corpus',
    name: 'Compatibility Corpus',
    seed: 2026,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    spawn: const WorldSpawn(x: 8, y: 20, z: 8),
  );

  test(
    'supported MDRT corpus decodes and migrates to the current version',
    () async {
      final v1 = await File(
        'test/data/worlds/fixtures/mdrt1_legacy.mdrt',
      ).readAsBytes();
      final v2 = await File(
        'test/data/worlds/fixtures/mdrt2_current.mdrt',
      ).readAsBytes();

      for (final fixture in <(String, Uint8List)>[
        ('MDRT1 legacy', v1),
        ('MDRT2 current', v2),
      ]) {
        final decoded = await MdrtCodec.decode(
          fixture.$2,
          legacyMetadata: metadata,
        );
        expect(
          decoded.metadata.formatVersion,
          MdrtCodec.currentFormatVersion,
          reason: fixture.$1,
        );
        expect(
          decoded.blocks.length,
          WorldDocument.blockCount,
          reason: fixture.$1,
        );
        expect(decoded.blocks[0], Blocks.pack(Blocks.stone, 3));
        expect(
          decoded.blocks[WorldDocument.blockCount ~/ 2],
          Blocks.pack(Blocks.sponge, 11),
        );
      }
    },
  );

  test(
    'corpus rejects malformed headers, sections, and compressed payloads',
    () async {
      final encoded = await MdrtCodec.encode(
        WorldDocument(metadata: metadata, blocks: _blocks(Blocks.dirt)),
      );
      final badLength = Uint8List.fromList(encoded);
      ByteData.sublistView(badLength).setUint32(5, 0x7fffffff, Endian.little);
      expect(
        () => MdrtCodec.decode(badLength),
        throwsA(isA<FormatException>()),
      );

      for (final cut in <int>[0, 4, 5, 8]) {
        final truncated = Uint8List.sublistView(encoded, 0, cut);
        await expectLater(
          MdrtCodec.decode(truncated),
          throwsA(isA<FormatException>()),
        );
      }
      final corruptedPayload = Uint8List.fromList(encoded)
        ..[encoded.length - 1] ^= 0xff;
      await expectLater(
        MdrtCodec.decode(corruptedPayload),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        MdrtCodec.decode(Uint8List.sublistView(encoded, 0, encoded.length - 1)),
        throwsA(isA<FormatException>()),
      );
    },
  );
}

Uint16List _blocks(int id) => Uint16List(WorldDocument.blockCount)
  ..[0] = Blocks.pack(id, 3)
  ..[WorldDocument.blockCount ~/ 2] = Blocks.pack(id, 11);
