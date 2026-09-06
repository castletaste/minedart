import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/world_models.dart';
import 'package:minedart/showcase/integration/legacy_world_migration_io.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'minedart-legacy-',
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test(
    'legacy locator preserves the previous application-support path',
    () async {
      final support = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}Application Support'
        '${Platform.pathSeparator}com.example.minedart',
      );

      final file = await legacyWorldFile(applicationSupportDirectory: support);

      expect(
        file.path,
        '${support.parent.path}${Platform.pathSeparator}minedart'
        '${Platform.pathSeparator}world.dat',
      );
    },
  );

  test(
    'legacy MDRT1 fixture migrates through the canonical bounded codec',
    () async {
      final blocks = Uint16List(WorldDocument.blockCount)
        ..[0] = Blocks.bedrock
        ..[4096] = Blocks.grass;
      final compressed = gzip.encode(Uint8List.sublistView(blocks));
      final bytes = Uint8List(13 + compressed.length)
        ..setRange(0, 5, <int>[0x4d, 0x44, 0x52, 0x54, 0x31])
        ..setRange(13, 13 + compressed.length, compressed);
      ByteData.sublistView(bytes).setInt64(5, 12345, Endian.little);
      final source = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}world.dat',
      );
      await source.writeAsBytes(bytes);
      final now = DateTime.utc(2026, 9, 6);

      final migrated = await readLegacyWorld(
        fallbackSeed: 7,
        source: source,
        clock: () => now,
      );

      expect(migrated, isNotNull);
      expect(migrated!.metadata.id, 'classic-world');
      expect(migrated.metadata.seed, 12345);
      expect(migrated.metadata.createdAt, now);
      expect(migrated.blocks[0], Blocks.bedrock);
      expect(migrated.blocks[4096], Blocks.grass);
    },
  );

  test('absent and corrupt legacy files are ignored', () async {
    final source = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}world.dat',
    );
    expect(await readLegacyWorld(fallbackSeed: 1, source: source), isNull);
    await source.writeAsBytes(const [0x4d, 0x44, 0x52, 0x54, 0x31]);
    expect(await readLegacyWorld(fallbackSeed: 1, source: source), isNull);
  });
}
