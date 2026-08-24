import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('raycastVoxel', () {
    test('hits the expected block, entry face, and place cell', () {
      final world = VoxelWorld()..setBlock(5, 4, 3, Blocks.stone);

      final hit = raycastVoxel(world, Vector3(2.5, 4.5, 3.5), Vector3(1, 0, 0));

      expect(hit, isNotNull);
      expect((hit!.x, hit.y, hit.z), (5, 4, 3));
      expect((hit.normalX, hit.normalY, hit.normalZ), (-1, 0, 0));
      expect((hit.previousX, hit.previousY, hit.previousZ), (4, 4, 3));
      expect(hit.distance, closeTo(2.5, 1e-9));
    });

    test('reports the top face and cell above for placement', () {
      final world = VoxelWorld()..setBlock(4, 2, 4, Blocks.dirt);

      final hit = raycastVoxel(
        world,
        Vector3(4.5, 5.5, 4.5),
        Vector3(0, -2, 0),
      );

      expect(hit, isNotNull);
      expect((hit!.x, hit.y, hit.z), (4, 2, 4));
      expect((hit.normalX, hit.normalY, hit.normalZ), (0, 1, 0));
      expect((hit.previousX, hit.previousY, hit.previousZ), (4, 3, 4));
    });

    test('default predicate ignores water but includes breakable flowers', () {
      final world = VoxelWorld()
        ..setBlock(3, 4, 3, Blocks.water)
        ..setBlock(4, 4, 3, Blocks.flowerRose)
        ..setBlock(5, 4, 3, Blocks.stone);

      final hit = raycastVoxel(world, Vector3(2.5, 4.5, 3.5), Vector3(1, 0, 0));

      expect(hit, isNotNull);
      expect(hit!.rawBlock, Blocks.flowerRose);
      expect(hit.x, 4);
    });

    test('custom predicate controls targetability', () {
      final world = VoxelWorld()
        ..setBlock(3, 4, 3, Blocks.flowerRose)
        ..setBlock(4, 4, 3, Blocks.stone);

      final hit = raycastVoxel(
        world,
        Vector3(2.5, 4.5, 3.5),
        Vector3(1, 0, 0),
        predicate: (raw, definition) => definition.solid,
      );

      expect(hit, isNotNull);
      expect(hit!.x, 4);
    });
  });
}
