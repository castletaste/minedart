import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/render/minimap_snapshot.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('MinimapSnapshot', () {
    test('copies VoxelWorld heightmap and surface ids immutably', () {
      final world = VoxelWorld()..seed = 0x5eed;
      world.setBlock(2, 3, 4, Blocks.stone);

      final snapshot = MinimapSnapshot.fromWorld(world);

      expect(snapshot.width, WorldDims.worldBlocksX);
      expect(snapshot.depth, WorldDims.worldBlocksZ);
      expect(snapshot.heightAt(2, 4), 4);
      expect(snapshot.surfaceBlockAt(2, 4), Blocks.stone);
      expect(snapshot.maxElevation, 4);
      expect(snapshot.seed, 0x5eed);

      world.setBlock(2, 3, 4, Blocks.air);
      expect(snapshot.heightAt(2, 4), 4);
      expect(snapshot.surfaceBlockAt(2, 4), Blocks.stone);
      expect(() => snapshot.heights[0] = 9, throwsUnsupportedError);
      expect(() => snapshot.surfaceBlockIds[0] = 9, throwsUnsupportedError);
    });

    test('fromHeightmap defensively copies caller buffers', () {
      final heights = Uint8List.fromList(<int>[0, 1, 2, 3]);
      final blocks = Uint16List.fromList(<int>[0, 1, 2, 3]);
      final snapshot = MinimapSnapshot.fromHeightmap(
        width: 2,
        depth: 2,
        heights: heights,
        surfaceBlockIds: blocks,
      );

      heights[3] = 0;
      blocks[3] = 0;
      expect(snapshot.heightAt(1, 1), 3);
      expect(snapshot.blockIdAt(1, 1), 3);
      expect(snapshot.normalizedElevationAt(1, 1), 1);
      expect(() => snapshot.heightAt(2, 0), throwsRangeError);
    });

    test('top non-air surface includes water above an opaque floor', () {
      final world = VoxelWorld();
      world
        ..setBlock(7, 4, 9, Blocks.stone)
        ..setBlock(7, 5, 9, Blocks.water)
        ..setBlock(7, 6, 9, Blocks.water);

      final snapshot = MinimapSnapshot.fromWorld(world);

      expect(snapshot.heightAt(7, 9), 7);
      expect(snapshot.surfaceBlockAt(7, 9), Blocks.water);
      expect(snapshot.sourceRevision, MinimapSnapshot.revisionOf(world));
    });
  });
}
