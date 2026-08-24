import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart_core/minedart_core.dart';

import 'package:minedart/save/world_saver.dart';

void main() {
  group('WorldSaver', () {
    late Directory temporaryDirectory;
    late File saveFile;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'minedart-save-',
      );
      saveFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}world.dat',
      );
    });

    tearDown(() => temporaryDirectory.delete(recursive: true));

    test('round-trips seed, blocks, counts, and skylight', () async {
      final world = VoxelWorld()..seed = 0x5eed;
      world
        ..setBlock(0, 0, 0, Blocks.bedrock)
        ..setBlock(17, 33, 17, Blocks.grass)
        ..setBlock(255, 63, 255, Blocks.glass);

      await WorldSaver.save(world, saveFile);
      final loaded = await WorldSaver.load(saveFile);

      expect(loaded, isNotNull);
      expect(loaded!.seed, world.seed);
      expect(loaded.blockAt(0, 0, 0), Blocks.bedrock);
      expect(loaded.blockAt(17, 33, 17), Blocks.grass);
      expect(loaded.blockAt(255, 63, 255), Blocks.glass);
      expect(loaded.chunkAt(0, 0, 0).nonAirCount, 1);
      expect(loaded.chunkAt(1, 2, 1).nonAirCount, 1);
      expect(loaded.inSkylight(17, 34, 17), isTrue);
      expect(loaded.inSkylight(17, 33, 17), isFalse);
    });

    test('returns null for a corrupt file', () async {
      await saveFile.writeAsBytes(const <int>[0x4d, 0x44, 0x52, 0x54, 0x31]);

      expect(await WorldSaver.load(saveFile), isNull);
    });

    test('replaces an existing save with the newest snapshot', () async {
      final world = VoxelWorld()..seed = 7;
      world.setBlock(1, 1, 1, Blocks.stone);
      await WorldSaver.save(world, saveFile);

      world
        ..setBlock(1, 1, 1, Blocks.air)
        ..setBlock(2, 2, 2, Blocks.dirt);
      await WorldSaver.save(world, saveFile);

      final loaded = await WorldSaver.load(saveFile);
      expect(loaded, isNotNull);
      expect(loaded!.blockAt(1, 1, 1), Blocks.air);
      expect(loaded.blockAt(2, 2, 2), Blocks.dirt);
    });
  });
}
