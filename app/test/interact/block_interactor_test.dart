import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/interact/block_interactor.dart';
import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart';

/// Flat stone floor at y=0..3 across a small area around the spawn column.
VoxelWorld _flatWorld() {
  final world = VoxelWorld();
  for (var z = 8; z < 24; z++) {
    for (var x = 8; x < 24; x++) {
      for (var y = 0; y < 4; y++) {
        world.setBlock(x, y, z, Blocks.pack(Blocks.stone));
      }
    }
  }
  world.recomputeSkylight();
  return world;
}

void main() {
  group('canPlaceBlock', () {
    test('rejects cells intersecting the player body', () {
      final world = _flatWorld();
      // Feet at y=4 on top of the floor, eye 1.62 above that.
      final eye = Vector3(16.5, 4 + PlayerBody.eyeHeight, 16.5);
      final box = Aabb();
      writePlayerAabbFromEye(eye, box);

      // Feet cell and head cell are both occupied by the player.
      expect(canPlaceBlock(world, 16, 4, 16, Blocks.stone, box), isFalse);
      expect(canPlaceBlock(world, 16, 5, 16, Blocks.stone, box), isFalse);
      // The cell right next to the player is free.
      expect(canPlaceBlock(world, 18, 4, 16, Blocks.stone, box), isTrue);
      // As is the cell above the player's head.
      expect(canPlaceBlock(world, 16, 6, 16, Blocks.stone, box), isTrue);
    });

    test('allows non-solid blocks inside the player', () {
      final world = _flatWorld();
      final eye = Vector3(16.5, 4 + PlayerBody.eyeHeight, 16.5);
      final box = Aabb();
      writePlayerAabbFromEye(eye, box);
      expect(canPlaceBlock(world, 16, 4, 16, Blocks.flowerRose, box), isTrue);
    });

    test('rejects occupied, out-of-bounds and invalid blocks', () {
      final world = _flatWorld();
      final box = Aabb()..setValues(-1, -1, -1, -1, -1, -1);
      expect(canPlaceBlock(world, 16, 2, 16, Blocks.stone, box), isFalse);
      expect(canPlaceBlock(world, -1, 2, 16, Blocks.stone, box), isFalse);
      expect(canPlaceBlock(world, 16, 8, 16, Blocks.air, box), isFalse);
    });

    test('replaces water and lava at every metadata level', () {
      final world = _flatWorld();
      final box = Aabb()..setValues(-1, -1, -1, -1, -1, -1);
      for (final liquid in <int>[Blocks.water, Blocks.lava]) {
        for (var metadata = 0; metadata < 16; metadata++) {
          world.setBlock(16, 8, 16, Blocks.pack(liquid, metadata));
          expect(
            canPlaceBlock(world, 16, 8, 16, Blocks.stone, box),
            isTrue,
            reason: 'liquid=$liquid metadata=$metadata',
          );
        }
      }
    });
  });

  group('canBreakBlock', () {
    test('is false for air, water and bedrock', () {
      final world = _flatWorld();
      world.setBlock(16, 8, 16, Blocks.pack(Blocks.water));
      world.setBlock(16, 9, 16, Blocks.pack(Blocks.bedrock));
      expect(canBreakBlock(world, 16, 10, 16), isFalse);
      expect(canBreakBlock(world, 16, 8, 16), isFalse);
      expect(canBreakBlock(world, 16, 9, 16), isFalse);
      expect(canBreakBlock(world, 16, 3, 16), isTrue);
    });
  });

  group('BlockInteractor', () {
    test('breaking clears the block and reports dirty chunks', () {
      final world = _flatWorld();
      final dirty = <int>{};
      final interactor = BlockInteractor(world: world, onDirty: dirty.addAll);
      // Eye above the floor looking straight down.
      final eye = Vector3(16.5, 6.0, 16.5);
      final result = interactor.breakBlock(eye, Vector3(0, -1, 0));

      expect(result.kind, BlockEditKind.broke);
      expect(result.y, 3);
      expect(Blocks.id(world.blockAt(16, 3, 16)), Blocks.air);
      expect(dirty, contains(VoxelWorld.chunkIndexOf(1, 0, 1)));
    });

    test('breaking nothing leaves the world untouched', () {
      final world = _flatWorld();
      var calls = 0;
      final interactor = BlockInteractor(world: world, onDirty: (_) => calls++);
      final result = interactor.breakBlock(
        Vector3(16.5, 40.0, 16.5),
        Vector3(0, 1, 0),
      );
      expect(result.kind, BlockEditKind.none);
      expect(result.changed, isFalse);
      expect(calls, 0);
    });

    test('respects the reach limit', () {
      final world = _flatWorld();
      final interactor = BlockInteractor(world: world, onDirty: (_) {});
      // Floor top is y=3; from y=20 straight down the block is out of reach.
      final result = interactor.breakBlock(
        Vector3(16.5, 20.0, 16.5),
        Vector3(0, -1, 0),
      );
      expect(result.kind, BlockEditKind.none);
      expect(Blocks.id(world.blockAt(16, 3, 16)), Blocks.stone);
    });

    test('placing puts the block in the previous cell', () {
      final world = _flatWorld();
      final dirty = <int>{};
      final interactor = BlockInteractor(world: world, onDirty: dirty.addAll);
      // Eye high enough that the player body clears the target cell.
      final eye = Vector3(16.5, 8.0, 16.5);
      final result = interactor.placeBlock(
        eye,
        Vector3(0, -1, 0),
        Blocks.brick,
      );

      expect(result.kind, BlockEditKind.placed);
      expect(result.y, 4);
      expect(Blocks.id(world.blockAt(16, 4, 16)), Blocks.brick);
      expect(dirty, isNotEmpty);
    });

    test('placing replaces water and lava including falling metadata', () {
      for (final liquid in <int>[Blocks.water, Blocks.lava]) {
        final world = _flatWorld();
        world.setBlock(16, 4, 16, Blocks.pack(liquid, 15));
        final dirty = <int>{};
        final interactor = BlockInteractor(world: world, onDirty: dirty.addAll);

        final result = interactor.placeBlock(
          Vector3(16.5, 8.0, 16.5),
          Vector3(0, -1, 0),
          Blocks.brick,
        );

        expect(result.kind, BlockEditKind.placed, reason: 'liquid=$liquid');
        expect(result.y, 4);
        expect(world.blockAt(16, 4, 16), Blocks.pack(Blocks.brick));
        expect(dirty, isNotEmpty);
      }
    });

    test('refuses to place a solid block inside the player', () {
      final world = _flatWorld();
      var calls = 0;
      final interactor = BlockInteractor(world: world, onDirty: (_) => calls++);
      // Standing on the floor, looking down: the free cell is where the feet
      // are, so the placement must be rejected.
      final eye = Vector3(16.5, 4 + PlayerBody.eyeHeight, 16.5);
      final result = interactor.placeBlock(
        eye,
        Vector3(0, -1, 0),
        Blocks.stone,
      );

      expect(result.kind, BlockEditKind.none);
      expect(Blocks.id(world.blockAt(16, 4, 16)), Blocks.air);
      expect(calls, 0);
    });

    test('placing without a target block does nothing', () {
      final world = _flatWorld();
      final interactor = BlockInteractor(world: world, onDirty: (_) {});
      final result = interactor.placeBlock(
        Vector3(16.5, 40.0, 16.5),
        Vector3(0, 1, 0),
        Blocks.stone,
      );
      expect(result.kind, BlockEditKind.none);
    });
  });

  group('isReplaceable', () {
    test('air, water and lava only regardless of liquid metadata', () {
      expect(isReplaceable(Blocks.pack(Blocks.air)), isTrue);
      for (var metadata = 0; metadata < 16; metadata++) {
        expect(isReplaceable(Blocks.pack(Blocks.water, metadata)), isTrue);
        expect(isReplaceable(Blocks.pack(Blocks.lava, metadata)), isTrue);
      }
      expect(isReplaceable(Blocks.pack(Blocks.stone)), isFalse);
      expect(isReplaceable(Blocks.pack(Blocks.flowerRose)), isFalse);
      expect(isReplaceable(Blocks.pack(Blocks.mushroomRed)), isFalse);
    });
  });
}
