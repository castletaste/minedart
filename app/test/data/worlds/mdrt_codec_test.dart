import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/mdrt_codec.dart';
import 'package:minedart/data/worlds/world_models.dart';
import 'package:minedart_core/src/block.dart';
import 'package:minedart_core/src/chunk.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 24, 12);
  final metadata = WorldMetadata(
    id: 'classic-01',
    name: 'Classic One',
    seed: 0x5eed,
    createdAt: createdAt,
    updatedAt: createdAt,
    spawn: const WorldSpawn(x: 12.5, y: 33, z: -4, yaw: 1.5, pitch: -0.25),
  );

  test('MDRT2 round-trips metadata and canonical blocks', () async {
    final blocks = Uint16List(WorldDocument.blockCount)
      ..[0] = Blocks.bedrock
      ..[ChunkIndex.volume + 42] = Blocks.grass;
    final encoded = await MdrtCodec.encode(
      WorldDocument(metadata: metadata, blocks: blocks),
    );

    expect(encoded.sublist(0, 5), <int>[0x4d, 0x44, 0x52, 0x54, 0x32]);
    final decoded = await MdrtCodec.decode(encoded);

    expect(decoded.metadata, metadata);
    expect(decoded.blocks, orderedEquals(blocks));
    expect(decoded.toVoxelWorld().blockAt(0, 0, 0), Blocks.bedrock);
  });

  test('MDRT1 migrates in memory with supplied metadata', () async {
    final blocks = Uint16List(WorldDocument.blockCount)..[12] = Blocks.sponge;
    final raw = Uint8List.fromList(blocks.buffer.asUint8List());
    final gzipBlocks = Uint8List.fromList(gzip.encode(raw));
    final bytes = Uint8List(13 + gzipBlocks.length);
    bytes.setRange(0, 5, <int>[0x4d, 0x44, 0x52, 0x54, 0x31]);
    ByteData.sublistView(bytes).setInt64(5, -99, Endian.little);
    bytes.setRange(13, bytes.length, gzipBlocks);

    final decoded = await MdrtCodec.decode(
      bytes,
      legacyMetadata: metadata.copyWith(id: 'migrated', seed: 0),
    );

    expect(decoded.metadata.id, 'migrated');
    expect(decoded.metadata.seed, -99);
    expect(decoded.metadata.formatVersion, 2);
    expect(decoded.blocks[12], Blocks.sponge);
  });

  test('corrupt and unsupported payloads reject closed', () async {
    expect(
      () => MdrtCodec.decode(
        Uint8List.fromList(<int>[0x4d, 0x44, 0x52, 0x54, 0x32]),
      ),
      throwsA(isA<FormatException>()),
    );
    final invalid = Uint16List(WorldDocument.blockCount)..[0] = 0x0fff;
    expect(
      () =>
          MdrtCodec.encode(WorldDocument(metadata: metadata, blocks: invalid)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MdrtCodec.encode(
        WorldDocument(
          metadata: metadata.copyWith(id: '../../escaped'),
          blocks: Uint16List(WorldDocument.blockCount),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
