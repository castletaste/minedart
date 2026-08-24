/// Deterministic Minecraft Classic-style finite world generation.
library;

import 'dart:typed_data';

import '../block.dart';
import '../chunk.dart';
import '../world.dart';
import 'noise.dart';

final class WorldGenerator {
  WorldGenerator(this.seed)
    : _terrainNoise = ValueNoise(seed ^ 0x2d4a9f31),
      _detailNoise = ValueNoise(seed ^ 0x6b8b4567),
      _caveNoise = ValueNoise(seed ^ 0x13579bdf);

  final int seed;
  final ValueNoise _terrainNoise;
  final ValueNoise _detailNoise;
  final ValueNoise _caveNoise;

  static const int minimumTerrainHeight = 20;
  static const int maximumTerrainHeight = 50;

  /// Replaces all blocks in [world] with a deterministic world for [seed].
  void generate(VoxelWorld world) {
    world.seed = seed;
    final heights = Uint8List(WorldDims.worldBlocksX * WorldDims.worldBlocksZ);

    _generateTerrain(world, heights);
    _carveCaves(world, heights);

    final random = _WorldRandom(seed ^ 0x51f15e5d);
    _placeOres(world, random);
    _placeTrees(world, heights, random);
    _placePlants(world, heights, random);

    world.recomputeSkylight();
    for (final chunk in world.chunks) {
      chunk.recount();
    }
  }

  int _terrainHeight(int x, int z) {
    final broad = _terrainNoise.fbm2(x * 0.0105, z * 0.0105, octaves: 4);
    final detail = _detailNoise.fbm2(x * 0.031, z * 0.031, octaves: 3);
    final height = (34 + broad * 13 + detail * 5).round();
    return height.clamp(minimumTerrainHeight, maximumTerrainHeight);
  }

  void _generateTerrain(VoxelWorld world, Uint8List heights) {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      final cz = z >> 4;
      final lz = z & 15;
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        final cx = x >> 4;
        final lx = x & 15;
        final height = _terrainHeight(x, z);
        heights[x + z * WorldDims.worldBlocksX] = height;
        final underwater = height < WorldDims.seaLevel;
        final floorBlock = underwater
            ? (_detailNoise.noise2(x * 0.19, z * 0.19) > 0.18
                  ? Blocks.gravel
                  : Blocks.sand)
            : Blocks.grass;

        for (var cy = 0; cy < WorldDims.worldChunksY; cy++) {
          final blocks = world.chunkAt(cx, cy, cz).blocks;
          final columnBase = lx + lz * ChunkIndex.size;
          final worldYBase = cy * ChunkIndex.size;
          for (var ly = 0; ly < ChunkIndex.size; ly++) {
            final y = worldYBase + ly;
            final block = switch (y) {
              0 => Blocks.bedrock,
              _ when y > height && y < WorldDims.seaLevel => Blocks.water,
              _ when y > height => Blocks.air,
              _ when y == height => floorBlock,
              _ when y >= height - 3 => Blocks.dirt,
              _ => Blocks.stone,
            };
            blocks[columnBase + ly * ChunkIndex.sliceArea] = block;
          }
        }
      }
    }
  }

  void _carveCaves(VoxelWorld world, Uint8List heights) {
    // Keeping caves above sea level avoids open cave cells immediately filling
    // with or bordering the deliberately simple ocean water model.
    for (var y = WorldDims.seaLevel + 1; y < maximumTerrainHeight - 3; y++) {
      final cy = y >> 4;
      final lyOffset = (y & 15) * ChunkIndex.sliceArea;
      for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
        final cz = z >> 4;
        final lzOffset = (z & 15) * ChunkIndex.size;
        for (var x = 0; x < WorldDims.worldBlocksX; x++) {
          if (y > heights[x + z * WorldDims.worldBlocksX] - 4) continue;
          final cx = x >> 4;
          final index = (x & 15) + lzOffset + lyOffset;
          final blocks = world.chunkAt(cx, cy, cz).blocks;
          if (blocks[index] != Blocks.stone) continue;

          final tunnel = _caveNoise.noise3(x * 0.055, y * 0.082, z * 0.055);
          if (tunnel > -0.10 && tunnel < 0.10) {
            final mask = _detailNoise.noise3(x * 0.025, y * 0.035, z * 0.025);
            if (mask > -0.05) blocks[index] = Blocks.air;
          }
        }
      }
    }
  }

  void _placeOres(VoxelWorld world, _WorldRandom random) {
    _placeOreVeins(
      world,
      random,
      block: Blocks.oreCoal,
      veinCount: 460,
      minY: 4,
      maxY: 48,
      steps: 7,
    );
    _placeOreVeins(
      world,
      random,
      block: Blocks.oreIron,
      veinCount: 310,
      minY: 4,
      maxY: 40,
      steps: 6,
    );
    _placeOreVeins(
      world,
      random,
      block: Blocks.oreGold,
      veinCount: 105,
      minY: 3,
      maxY: 24,
      steps: 5,
    );
  }

  void _placeOreVeins(
    VoxelWorld world,
    _WorldRandom random, {
    required int block,
    required int veinCount,
    required int minY,
    required int maxY,
    required int steps,
  }) {
    for (var vein = 0; vein < veinCount; vein++) {
      var x = 2 + random.nextInt(WorldDims.worldBlocksX - 4);
      var y = minY + random.nextInt(maxY - minY + 1);
      var z = 2 + random.nextInt(WorldDims.worldBlocksZ - 4);
      for (var step = 0; step < steps; step++) {
        final radiusSquared = random.nextInt(3) == 0 ? 3 : 2;
        for (var dz = -1; dz <= 1; dz++) {
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx * dx + dy * dy + dz * dz > radiusSquared) continue;
              final bx = x + dx;
              final by = y + dy;
              final bz = z + dz;
              if (!VoxelWorld.inBounds(bx, by, bz) || by < minY || by > maxY) {
                continue;
              }
              if (_rawBlock(world, bx, by, bz) == Blocks.stone) {
                _writeRaw(world, bx, by, bz, block);
              }
            }
          }
        }
        x = (x + random.nextInt(3) - 1).clamp(1, WorldDims.worldBlocksX - 2);
        y = (y + random.nextInt(3) - 1).clamp(minY, maxY);
        z = (z + random.nextInt(3) - 1).clamp(1, WorldDims.worldBlocksZ - 2);
      }
    }
  }

  void _placeTrees(VoxelWorld world, Uint8List heights, _WorldRandom random) {
    for (var z = 2; z < WorldDims.worldBlocksZ - 2; z++) {
      for (var x = 2; x < WorldDims.worldBlocksX - 2; x++) {
        if (random.nextInt(64) != 0) continue;
        final surfaceY = heights[x + z * WorldDims.worldBlocksX];
        if (surfaceY <= WorldDims.seaLevel ||
            _rawBlock(world, x, surfaceY, z) != Blocks.grass) {
          continue;
        }

        final trunkHeight = 4 + random.nextInt(3);
        final baseY = surfaceY + 1;
        final crownTop = baseY + trunkHeight;
        if (crownTop >= WorldDims.worldBlocksY) continue;
        if (!_treeVolumeIsClear(world, x, baseY, z, crownTop)) continue;

        for (var y = baseY; y < baseY + trunkHeight; y++) {
          _writeRaw(world, x, y, z, Blocks.logOak);
        }
        for (var y = crownTop - 2; y <= crownTop; y++) {
          for (var dz = -2; dz <= 2; dz++) {
            for (var dx = -2; dx <= 2; dx++) {
              if (dx.abs() == 2 && dz.abs() == 2) continue;
              final bx = x + dx;
              final bz = z + dz;
              if (_rawBlock(world, bx, y, bz) == Blocks.air) {
                _writeRaw(world, bx, y, bz, Blocks.leavesOak);
              }
            }
          }
        }
      }
    }
  }

  bool _treeVolumeIsClear(
    VoxelWorld world,
    int x,
    int baseY,
    int z,
    int crownTop,
  ) {
    for (var y = baseY; y <= crownTop; y++) {
      final radius = y >= crownTop - 2 ? 2 : 0;
      for (var dz = -radius; dz <= radius; dz++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (_rawBlock(world, x + dx, y, z + dz) != Blocks.air) return false;
        }
      }
    }
    return true;
  }

  void _placePlants(VoxelWorld world, Uint8List heights, _WorldRandom random) {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        final surfaceY = heights[x + z * WorldDims.worldBlocksX];
        if (surfaceY <= WorldDims.seaLevel ||
            surfaceY + 1 >= WorldDims.worldBlocksY ||
            _rawBlock(world, x, surfaceY, z) != Blocks.grass ||
            _rawBlock(world, x, surfaceY + 1, z) != Blocks.air) {
          continue;
        }

        final roll = random.nextInt(768);
        final plant = switch (roll) {
          < 2 => Blocks.flowerDandelion,
          < 4 => Blocks.flowerRose,
          4 => Blocks.mushroomBrown,
          5 => Blocks.mushroomRed,
          _ => Blocks.air,
        };
        if (plant != Blocks.air) {
          _writeRaw(world, x, surfaceY + 1, z, plant);
        }
      }
    }
  }

  static int _rawBlock(VoxelWorld world, int x, int y, int z) {
    final blocks = world.chunkAt(x >> 4, y >> 4, z >> 4).blocks;
    return blocks[ChunkIndex.of(x & 15, y & 15, z & 15)];
  }

  static void _writeRaw(VoxelWorld world, int x, int y, int z, int block) {
    final blocks = world.chunkAt(x >> 4, y >> 4, z >> 4).blocks;
    blocks[ChunkIndex.of(x & 15, y & 15, z & 15)] = block;
  }
}

final class _WorldRandom {
  _WorldRandom(int seed) : _state = seed & 0xffffffff {
    if (_state == 0) _state = 0x6d2b79f5;
  }

  int _state;

  int nextInt(int upperBound) {
    assert(upperBound > 0);
    var value = _state;
    value ^= (value << 13) & 0xffffffff;
    value ^= value >> 17;
    value ^= (value << 5) & 0xffffffff;
    _state = value & 0xffffffff;
    return _state % upperBound;
  }
}
