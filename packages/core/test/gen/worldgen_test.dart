import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  late VoxelWorld world;

  setUpAll(() {
    world = VoxelWorld();
    WorldGenerator(0x5eed).generate(world);
  });

  test('same seed produces the same complete block hash', () {
    final sameSeed = VoxelWorld();
    WorldGenerator(0x5eed).generate(sameSeed);
    expect(_blockHash(sameSeed), _blockHash(world));

    final otherSeed = VoxelWorld();
    WorldGenerator(0x5eee).generate(otherSeed);
    expect(_blockHash(otherSeed), isNot(_blockHash(world)));
  });

  test('terrain surface remains in the promised height range', () {
    var minimum = WorldDims.worldBlocksY;
    var maximum = 0;
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        final surface = _terrainSurface(world, x, z);
        if (surface < minimum) minimum = surface;
        if (surface > maximum) maximum = surface;
        expect(
          surface,
          inInclusiveRange(
            WorldGenerator.minimumTerrainHeight,
            WorldGenerator.maximumTerrainHeight,
          ),
          reason: 'column ($x,$z)',
        );
      }
    }
    expect(minimum, lessThan(WorldDims.seaLevel));
    expect(maximum, greaterThan(WorldDims.seaLevel));
  });

  test('bedrock is solid across y=0', () {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        expect(world.blockAt(x, 0, z), Blocks.bedrock);
      }
    }
  });

  test('water never appears at or above sea level', () {
    var waterBelowSeaLevel = 0;
    for (var y = 0; y < WorldDims.seaLevel; y++) {
      for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
        for (var x = 0; x < WorldDims.worldBlocksX; x++) {
          if (world.blockAt(x, y, z) == Blocks.water) waterBelowSeaLevel++;
        }
      }
    }
    for (var y = WorldDims.seaLevel; y < WorldDims.worldBlocksY; y++) {
      for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
        for (var x = 0; x < WorldDims.worldBlocksX; x++) {
          expect(world.blockAt(x, y, z), isNot(Blocks.water));
        }
      }
    }
    expect(waterBelowSeaLevel, greaterThan(0));
  });

  test(
    'caves exist only above the protected sea layer and ores obey depth',
    () {
      var caveBlocks = 0;
      var coalBlocks = 0;
      var ironBlocks = 0;
      var goldBlocks = 0;
      for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
        for (var x = 0; x < WorldDims.worldBlocksX; x++) {
          final surface = _terrainSurface(world, x, z);
          for (var y = 1; y < surface - 3; y++) {
            final block = world.blockAt(x, y, z);
            if (block == Blocks.air) {
              expect(y, greaterThanOrEqualTo(WorldDims.seaLevel + 1));
              caveBlocks++;
            } else if (block == Blocks.oreCoal) {
              expect(y, lessThanOrEqualTo(48));
              coalBlocks++;
            } else if (block == Blocks.oreIron) {
              expect(y, lessThanOrEqualTo(40));
              ironBlocks++;
            } else if (block == Blocks.oreGold) {
              expect(y, lessThanOrEqualTo(24));
              goldBlocks++;
            }
          }
        }
      }
      expect(caveBlocks, greaterThan(0));
      expect(coalBlocks, greaterThan(0));
      expect(ironBlocks, greaterThan(0));
      expect(goldBlocks, greaterThan(0));
    },
  );

  test('tree crowns cross chunk borders without being clipped', () {
    var crossingTrees = 0;
    for (var z = 2; z < WorldDims.worldBlocksZ - 2; z++) {
      for (var x = 2; x < WorldDims.worldBlocksX - 2; x++) {
        final surface = _terrainSurface(world, x, z);
        final baseY = surface + 1;
        if (baseY >= WorldDims.worldBlocksY ||
            world.blockAt(x, baseY, z) != Blocks.logOak) {
          continue;
        }

        var trunkHeight = 0;
        while (baseY + trunkHeight < WorldDims.worldBlocksY &&
            world.blockAt(x, baseY + trunkHeight, z) == Blocks.logOak) {
          trunkHeight++;
        }
        expect(trunkHeight, inInclusiveRange(4, 6));
        final crownTop = baseY + trunkHeight;
        expect(crownTop, lessThan(WorldDims.worldBlocksY));

        final crossesChunkEdge =
            (x & 15) < 2 || (x & 15) > 13 || (z & 15) < 2 || (z & 15) > 13;
        if (!crossesChunkEdge) continue;
        crossingTrees++;

        for (var y = crownTop - 2; y <= crownTop; y++) {
          for (var dz = -2; dz <= 2; dz++) {
            for (var dx = -2; dx <= 2; dx++) {
              if (dx.abs() == 2 && dz.abs() == 2) continue;
              final block = world.blockAt(x + dx, y, z + dz);
              expect(
                block == Blocks.leavesOak || block == Blocks.logOak,
                isTrue,
                reason: 'crown at (${x + dx},$y,${z + dz})',
              );
            }
          }
        }
      }
    }
    expect(crossingTrees, greaterThan(0));
  });

  test('skylight height matches the highest light-blocking block', () {
    for (var z = 3; z < WorldDims.worldBlocksZ; z += 17) {
      for (var x = 5; x < WorldDims.worldBlocksX; x += 19) {
        var expected = 0;
        for (var y = WorldDims.worldBlocksY - 1; y >= 0; y--) {
          final def = blockDefs[Blocks.id(world.blockAt(x, y, z))];
          if (def != null && def.blocksLight) {
            expected = y + 1;
            break;
          }
        }
        final column = x + z * WorldDims.worldBlocksX;
        expect(world.skyHeight[column], expected, reason: 'column ($x,$z)');
        expect(world.inSkylight(x, expected, z), isTrue);
        if (expected > 0) expect(world.inSkylight(x, expected - 1, z), isFalse);
      }
    }
  });

  test('chunk counts match generated storage', () {
    for (final chunk in world.chunks) {
      var expected = 0;
      for (final block in chunk.blocks) {
        if (block != Blocks.air) expected++;
      }
      expect(chunk.nonAirCount, expected);
    }
  });
}

int _terrainSurface(VoxelWorld world, int x, int z) {
  for (var y = WorldDims.worldBlocksY - 1; y >= 0; y--) {
    final block = Blocks.id(world.blockAt(x, y, z));
    if (block == Blocks.grass ||
        block == Blocks.sand ||
        block == Blocks.gravel) {
      return y;
    }
  }
  return -1;
}

int _blockHash(VoxelWorld world) {
  var hash = 0x811c9dc5;
  for (final chunk in world.chunks) {
    for (final block in chunk.blocks) {
      hash ^= block;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }
  return hash;
}
