import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  const seed = 0x5eed;
  late VoxelWorld world;

  setUpAll(() {
    world = VoxelWorld();
    IslandsWorldGenerator(seed).generate(world);
  });

  test('same seed repeats the full block hash and another seed differs', () {
    final repeated = VoxelWorld();
    IslandsWorldGenerator(seed).generate(repeated);
    expect(_blockHash(world), 1349996066);
    expect(_blockHash(repeated), _blockHash(world));

    final different = VoxelWorld();
    IslandsWorldGenerator(seed + 1).generate(different);
    expect(_blockHash(different), isNot(_blockHash(world)));
    expect(_differentBlockCount(different, world), greaterThan(50000));
  });

  test('edge seeds remain repeatable with the same safe center', () {
    for (final edgeSeed in const [0, -1, 0x7fffffff, -0x80000000]) {
      final first = VoxelWorld();
      final second = VoxelWorld();
      IslandsWorldGenerator(edgeSeed).generate(first);
      IslandsWorldGenerator(edgeSeed).generate(second);

      expect(first.seed, edgeSeed);
      expect(_blockHash(first), _blockHash(second), reason: 'seed $edgeSeed');
      _expectSafeSpawn(first, reason: 'seed $edgeSeed');
    }
  });

  test('archipelago mixes ocean, land, beaches, shelves, and cliffs', () {
    final counts = _blockCounts(world);
    expect(counts[Blocks.water] ?? 0, greaterThan(10000));
    expect(counts[Blocks.grass] ?? 0, greaterThan(500));
    expect(counts[Blocks.sand] ?? 0, greaterThan(500));
    expect(counts[Blocks.stone] ?? 0, greaterThan(10000));
    expect(counts[Blocks.gravel] ?? 0, greaterThan(100));

    var oceanColumns = 0;
    var landColumns = 0;
    var shallowShelfColumns = 0;
    var exposedStoneColumns = 0;
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        final (top, surface) = _terrainSurface(world, x, z);
        if (top < IslandsWorldGenerator.seaLevel - 1) {
          oceanColumns++;
        }
        if (top >= IslandsWorldGenerator.seaLevel) landColumns++;
        if (top >= IslandsWorldGenerator.seaLevel - 5 &&
            top < IslandsWorldGenerator.seaLevel &&
            (surface == Blocks.sand || surface == Blocks.gravel)) {
          shallowShelfColumns++;
        }
        if (top > IslandsWorldGenerator.seaLevel + 2 &&
            surface == Blocks.stone) {
          exposedStoneColumns++;
        }
      }
    }

    expect(oceanColumns, greaterThan(1000));
    expect(landColumns, greaterThan(1000));
    expect(shallowShelfColumns, greaterThan(100));
    expect(exposedStoneColumns, greaterThan(50));
  });

  test('land mask contains multiple islands separated by ocean', () {
    final componentSizes = _landComponentSizes(world)..sort();
    final landColumns = componentSizes.fold<int>(0, (sum, size) => sum + size);

    expect(
      componentSizes.length,
      greaterThanOrEqualTo(3),
      reason: 'land component sizes: $componentSizes',
    );
    expect(
      componentSizes.last,
      lessThan(landColumns),
      reason: 'all land columns joined one component: $componentSizes',
    );
  });

  test('islands contain trees and varied flora', () {
    final counts = _blockCounts(world);
    expect(counts[Blocks.logOak] ?? 0, greaterThan(50));
    expect(counts[Blocks.leavesOak] ?? 0, greaterThan(200));
    final flora =
        (counts[Blocks.flowerDandelion] ?? 0) +
        (counts[Blocks.flowerRose] ?? 0) +
        (counts[Blocks.mushroomBrown] ?? 0) +
        (counts[Blocks.mushroomRed] ?? 0);
    expect(flora, greaterThan(10));
  });

  test('small enclosed caves and depth-bounded ore pockets exist', () {
    var caveAir = 0;
    var coal = 0;
    var iron = 0;
    var gold = 0;
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        final (surfaceY, _) = _terrainSurface(world, x, z);
        for (var y = 2; y < surfaceY - 3; y++) {
          final block = Blocks.id(world.blockAt(x, y, z));
          switch (block) {
            case Blocks.air:
              caveAir++;
            case Blocks.oreCoal:
              expect(y, lessThanOrEqualTo(48));
              coal++;
            case Blocks.oreIron:
              expect(y, lessThanOrEqualTo(38));
              iron++;
            case Blocks.oreGold:
              expect(y, lessThanOrEqualTo(22));
              gold++;
          }
        }
      }
    }
    expect(caveAir, greaterThan(100));
    expect(coal, greaterThan(100));
    expect(iron, greaterThan(100));
    expect(gold, greaterThan(25));
  });

  test('central spawn is flat solid grass with clear headroom', () {
    _expectSafeSpawn(world);
  });

  test('skylight matches every generated column', () {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        var expected = 0;
        for (var y = WorldDims.worldBlocksY - 1; y >= 0; y--) {
          final definition = blockDefs[Blocks.id(world.blockAt(x, y, z))];
          if (definition != null && definition.blocksLight) {
            expected = y + 1;
            break;
          }
        }
        final column = x + z * WorldDims.worldBlocksX;
        expect(world.skyHeight[column], expected, reason: 'column ($x,$z)');
        expect(world.inSkylight(x, expected, z), isTrue);
        if (expected > 0) {
          expect(world.inSkylight(x, expected - 1, z), isFalse);
        }
      }
    }
  });

  test('chunk layout, counts, revisions, and mesh ABI remain stable', () {
    expect(
      world.chunks,
      hasLength(
        WorldDims.worldChunksX *
            WorldDims.worldChunksY *
            WorldDims.worldChunksZ,
      ),
    );
    expect(VertexLayout.floatsPerVertex, 20);

    for (var index = 0; index < world.chunks.length; index++) {
      final chunk = world.chunks[index];
      expect(index, VoxelWorld.chunkIndexOf(chunk.cx, chunk.cy, chunk.cz));
      expect(chunk.revision, 1);
      var expectedNonAir = 0;
      for (final block in chunk.blocks) {
        if (block != Blocks.air) expectedNonAir++;
      }
      expect(chunk.nonAirCount, expectedNonAir);
    }
  });

  test('generation fully replaces an already used world', () {
    final reused = VoxelWorld()..seed = -999;
    reused.skyHeight.fillRange(0, reused.skyHeight.length, 63);
    for (final chunk in reused.chunks) {
      chunk.blocks.fillRange(0, chunk.blocks.length, Blocks.tnt);
      chunk.recount();
    }
    final revisionsBefore = [for (final chunk in reused.chunks) chunk.revision];

    IslandsWorldGenerator(seed).generate(reused);

    expect(reused.seed, seed);
    expect(_blockHash(reused), _blockHash(world));
    expect(reused.skyHeight, orderedEquals(world.skyHeight));
    for (var i = 0; i < reused.chunks.length; i++) {
      expect(reused.chunks[i].revision, revisionsBefore[i] + 1);
      expect(reused.chunks[i].blocks, isNot(contains(Blocks.tnt)));
    }
  });
}

void _expectSafeSpawn(VoxelWorld world, {String? reason}) {
  const centerX = IslandsWorldGenerator.spawnX;
  const centerZ = IslandsWorldGenerator.spawnZ;
  const extent = IslandsWorldGenerator.safeSpawnHalfExtent;
  final surfaceY =
      world.skyHeight[centerX + centerZ * WorldDims.worldBlocksX] - 1;

  expect(
    surfaceY,
    greaterThanOrEqualTo(IslandsWorldGenerator.seaLevel + 7),
    reason: reason,
  );

  for (var z = centerZ - extent; z <= centerZ + extent; z++) {
    for (var x = centerX - extent; x <= centerX + extent; x++) {
      expect(world.blockAt(x, surfaceY, z), Blocks.grass, reason: reason);
      expect(world.blockAt(x, surfaceY - 1, z), Blocks.dirt, reason: reason);
      for (var y = 0; y <= surfaceY; y++) {
        final block = Blocks.id(world.blockAt(x, y, z));
        expect(block, isNot(Blocks.air), reason: reason);
        expect(blockDefs[block]?.solid, isTrue, reason: reason);
      }
      for (var y = surfaceY + 1; y <= surfaceY + 3; y++) {
        expect(world.blockAt(x, y, z), Blocks.air, reason: reason);
      }
    }
  }

  // The guaranteed square is the local high point. Looking outward from its
  // center can descend, but cannot immediately face an excavated wall.
  for (var z = centerZ - extent - 4; z <= centerZ + extent + 4; z++) {
    for (var x = centerX - extent - 4; x <= centerX + extent + 4; x++) {
      final (nearbySurface, _) = _terrainSurface(world, x, z);
      expect(nearbySurface, lessThanOrEqualTo(surfaceY), reason: reason);
    }
  }
}

List<int> _landComponentSizes(VoxelWorld world) {
  const width = WorldDims.worldBlocksX;
  const depth = WorldDims.worldBlocksZ;
  final land = List<bool>.filled(width * depth, false);
  final visited = List<bool>.filled(width * depth, false);
  for (var z = 0; z < depth; z++) {
    for (var x = 0; x < width; x++) {
      final (top, _) = _terrainSurface(world, x, z);
      land[x + z * width] = top >= IslandsWorldGenerator.seaLevel;
    }
  }

  final queue = List<int>.filled(width * depth, 0);
  final sizes = <int>[];
  for (var start = 0; start < land.length; start++) {
    if (!land[start] || visited[start]) continue;
    var head = 0;
    var tail = 0;
    var size = 0;
    queue[tail++] = start;
    visited[start] = true;

    while (head < tail) {
      final index = queue[head++];
      size++;
      final x = index % width;
      final z = index ~/ width;
      for (final neighbor in [
        if (x > 0) index - 1,
        if (x + 1 < width) index + 1,
        if (z > 0) index - width,
        if (z + 1 < depth) index + width,
      ]) {
        if (land[neighbor] && !visited[neighbor]) {
          visited[neighbor] = true;
          queue[tail++] = neighbor;
        }
      }
    }
    sizes.add(size);
  }
  return sizes;
}

(int, int) _terrainSurface(VoxelWorld world, int x, int z) {
  for (var y = WorldDims.worldBlocksY - 1; y >= 0; y--) {
    final block = Blocks.id(world.blockAt(x, y, z));
    if (block == Blocks.grass ||
        block == Blocks.sand ||
        block == Blocks.gravel ||
        block == Blocks.stone) {
      return (y, block);
    }
  }
  return (-1, Blocks.air);
}

Map<int, int> _blockCounts(VoxelWorld world) {
  final counts = <int, int>{};
  for (final chunk in world.chunks) {
    for (final raw in chunk.blocks) {
      final block = Blocks.id(raw);
      counts[block] = (counts[block] ?? 0) + 1;
    }
  }
  return counts;
}

int _blockHash(VoxelWorld world) {
  var hash = 1;
  for (final chunk in world.chunks) {
    for (final block in chunk.blocks) {
      hash = (hash * 31 + block) & 0x7fffffff;
    }
  }
  return hash;
}

int _differentBlockCount(VoxelWorld first, VoxelWorld second) {
  var differences = 0;
  for (var chunkIndex = 0; chunkIndex < first.chunks.length; chunkIndex++) {
    final firstBlocks = first.chunks[chunkIndex].blocks;
    final secondBlocks = second.chunks[chunkIndex].blocks;
    for (var blockIndex = 0; blockIndex < firstBlocks.length; blockIndex++) {
      if (firstBlocks[blockIndex] != secondBlocks[blockIndex]) differences++;
    }
  }
  return differences;
}
