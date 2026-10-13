import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/mdrt_codec.dart';
import 'package:minedart/data/worlds/world_models.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  test(
    'seeded sparse MDRT worlds round-trip without changing raw blocks',
    () async {
      final createdAt = DateTime.utc(2026, 10, 12);
      for (final seed in [3, 29, 2026]) {
        final random = Random(seed);
        final blocks = Uint16List(WorldDocument.blockCount);
        for (var i = 0; i < 96; i++) {
          final index = random.nextInt(blocks.length);
          final id = <int>[
            Blocks.stone,
            Blocks.dirt,
            Blocks.grass,
            Blocks.sand,
            Blocks.water,
            Blocks.lava,
            Blocks.obsidian,
          ][random.nextInt(7)];
          blocks[index] = Blocks.pack(id, random.nextInt(16));
        }
        final metadata = WorldMetadata(
          id: 'property-$seed',
          name: 'Property $seed',
          seed: seed,
          createdAt: createdAt,
          updatedAt: createdAt,
          spawn: const WorldSpawn(x: 8.5, y: 4, z: 8.5),
        );

        final encoded = await MdrtCodec.encode(
          WorldDocument(metadata: metadata, blocks: blocks),
        );
        final decoded = await MdrtCodec.decode(encoded);

        expect(decoded.metadata, metadata);
        expect(decoded.blocks, orderedEquals(blocks));
        expect(MdrtCodec.decodeMetadata(encoded), metadata);
      }
    },
  );
  test(
    'seeded malformed headers, metadata and payload truncations reject',
    () async {
      final metadata = WorldMetadata(
        id: 'corruption',
        name: 'Corruption',
        seed: 43,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        spawn: const WorldSpawn.origin(),
      );
      final encoded = await MdrtCodec.encode(
        WorldDocument(
          metadata: metadata,
          blocks: Uint16List(WorldDocument.blockCount),
        ),
      );
      final offset =
          9 + ByteData.sublistView(encoded).getUint32(5, Endian.little);
      final random = Random(43);
      for (var attempt = 0; attempt < 24; attempt++) {
        final broken = Uint8List.fromList(encoded);
        if (attempt.isEven) {
          broken[random.nextInt(5)] ^= 1 + random.nextInt(255);
        } else {
          ByteData.sublistView(
            broken,
          ).setUint32(5, encoded.length + random.nextInt(10000), Endian.little);
        }
        await expectLater(
          MdrtCodec.decode(broken),
          throwsFormatException,
          reason: 'header attempt $attempt',
        );
      }
      for (final (field, value) in <(String, Object)>[
        ('id', '../unsafe'),
        ('seed', 'text'),
        ('spawn', []),
        ('formatVersion', 99),
        ('createdAt', 'yesterday'),
        ('name', 0),
      ]) {
        final json = metadata.toJson()..[field] = value;
        final bytes = utf8.encode(jsonEncode(json));
        final broken = Uint8List(9 + bytes.length + encoded.length - offset)
          ..setRange(0, 5, encoded)
          ..setRange(9, 9 + bytes.length, bytes)
          ..setRange(
            9 + bytes.length,
            9 + bytes.length + encoded.length - offset,
            encoded,
            offset,
          );
        ByteData.sublistView(broken).setUint32(5, bytes.length, Endian.little);
        await expectLater(
          MdrtCodec.decode(broken),
          throwsFormatException,
          reason: field,
        );
        expect(
          () => MdrtCodec.decodeMetadata(broken),
          throwsFormatException,
          reason: field,
        );
      }
      for (final cut in [0, 4, 8, offset, offset + 3, encoded.length ~/ 2]) {
        await expectLater(
          MdrtCodec.decode(Uint8List.sublistView(encoded, 0, cut)),
          throwsFormatException,
          reason: 'truncate at $cut',
        );
      }
    },
  );
}
