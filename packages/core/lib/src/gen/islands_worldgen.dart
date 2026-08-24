/// Deterministic finite archipelago world generation.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../block.dart';
import '../chunk.dart';
import '../world.dart';

/// Fills an existing [VoxelWorld] with a deterministic islands preset.
///
/// Generation uses bounded in-memory height data and raw chunk writes. Every
/// chunk is cleared before generation, then recounted exactly once after the
/// complete skylight heightmap has been recomputed.
final class IslandsWorldGenerator {
  IslandsWorldGenerator(this.seed)
    : _coastNoise = _PortableValueNoise(seed ^ 0x49534c41),
      _reliefNoise = _PortableValueNoise(seed ^ 0x52454c46),
      _surfaceNoise = _PortableValueNoise(seed ^ 0x53555246);

  final int seed;
  final _PortableValueNoise _coastNoise;
  final _PortableValueNoise _reliefNoise;
  final _PortableValueNoise _surfaceNoise;

  static const int seaLevel = WorldDims.seaLevel;
  static const int spawnX = WorldDims.worldBlocksX ~/ 2;
  static const int spawnZ = WorldDims.worldBlocksZ ~/ 2;
  static const int spawnSurfaceY = seaLevel + 7;

  /// Half-size of the guaranteed square, flat, obstruction-free spawn area.
  static const int safeSpawnHalfExtent = 6;

  static const int _spawnFeatureBuffer = safeSpawnHalfExtent + 4;
  static const int _deepOceanFloor = 10;
  static const int _islandCount = 15;

  /// Replaces every block in [world] with the islands world for [seed].
  void generate(VoxelWorld world) {
    _clear(world);
    world.seed = seed;

    final heights = Uint8List(WorldDims.worldBlocksX * WorldDims.worldBlocksZ);
    final random = _IslandsRandom(seed ^ 0x41524348);
    final islands = _createIslands(random);

    _buildHeightmap(heights, islands);
    _fillTerrain(world, heights);
    _carveCaves(world, heights, random);
    _placeOres(world, heights, random);
    _placeTrees(world, heights, random);
    _placePlants(world, heights, random);

    world.recomputeSkylight();
    for (final chunk in world.chunks) {
      chunk.recount();
    }
  }

  List<_Island> _createIslands(_IslandsRandom random) {
    final islands = <_Island>[
      _Island(
        x: spawnX.toDouble(),
        z: spawnZ.toDouble(),
        radiusX: 48.0,
        radiusZ: 41.0,
        angle: 0.32,
        peakHeight: 14,
        reliefPower: 0.72,
      ),
    ];

    for (var i = 1; i < _islandCount; i++) {
      final small = i % 4 == 0;
      islands.add(
        _Island(
          x: 18 + random.nextDouble() * (WorldDims.worldBlocksX - 36),
          z: 18 + random.nextDouble() * (WorldDims.worldBlocksZ - 36),
          radiusX: (small ? 11 : 17) + random.nextDouble() * (small ? 12 : 22),
          radiusZ: (small ? 10 : 15) + random.nextDouble() * (small ? 11 : 21),
          angle: random.nextDouble() * math.pi,
          peakHeight: 7 + random.nextInt(12),
          reliefPower: i % 3 == 0
              ? 0.42 + random.nextDouble() * 0.12
              : 0.68 + random.nextDouble() * 0.32,
        ),
      );
    }
    return islands;
  }

  void _buildHeightmap(Uint8List heights, List<_Island> islands) {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        if (_insideSafeSpawn(x, z)) {
          heights[_columnIndex(x, z)] = spawnSurfaceY;
          continue;
        }

        var bestStrength = -double.infinity;
        var bestIsland = islands.first;
        for (final island in islands) {
          final strength = island.strengthAt(x, z);
          if (strength > bestStrength) {
            bestStrength = strength;
            bestIsland = island;
          }
        }

        final coast = _coastNoise.fbm2(x * 0.023, z * 0.023, octaves: 3);
        final fineCoast = _surfaceNoise.noise2(x * 0.071, z * 0.071);
        final shapedStrength = bestStrength + coast * 0.13 + fineCoast * 0.035;
        final relief = _reliefNoise.fbm2(x * 0.041, z * 0.041, octaves: 3);

        final int top;
        if (shapedStrength >= 0) {
          final normalized = shapedStrength.clamp(0.0, 1.0);
          final rise =
              1 +
              math.pow(normalized, bestIsland.reliefPower) *
                  bestIsland.peakHeight;
          top = (seaLevel + rise + relief * 2.2).round().clamp(
            seaLevel,
            WorldDims.worldBlocksY - 10,
          );
        } else if (shapedStrength > -0.5) {
          top = (seaLevel - 3 + shapedStrength * 15 + relief * 1.5)
              .round()
              .clamp(_deepOceanFloor, seaLevel - 1);
        } else {
          top = (_deepOceanFloor + relief * 3.0).round().clamp(6, seaLevel - 5);
        }
        heights[_columnIndex(x, z)] = top;
      }
    }
  }

  void _fillTerrain(VoxelWorld world, Uint8List heights) {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        final top = heights[_columnIndex(x, z)];
        final surface = _surfaceBlock(heights, x, z, top);

        _writeRaw(world, x, 0, z, Blocks.bedrock);
        for (var y = 1; y <= top; y++) {
          final block = switch (surface) {
            Blocks.grass when y == top => Blocks.grass,
            Blocks.grass when y >= top - 3 => Blocks.dirt,
            Blocks.sand when y >= top - 2 => Blocks.sand,
            Blocks.gravel when y >= top - 2 => Blocks.gravel,
            _ => Blocks.stone,
          };
          _writeRaw(world, x, y, z, block);
        }
        for (var y = top + 1; y < seaLevel; y++) {
          _writeRaw(world, x, y, z, Blocks.water);
        }
      }
    }
  }

  int _surfaceBlock(Uint8List heights, int x, int z, int top) {
    if (_insideSafeSpawn(x, z)) return Blocks.grass;

    final surfaceVariation = _surfaceNoise.noise2(x * 0.16, z * 0.16);
    if (top <= seaLevel + 2) {
      return surfaceVariation > 0.28 ? Blocks.gravel : Blocks.sand;
    }

    final slope = _maximumSlope(heights, x, z, top);
    final cliffNoise = _reliefNoise.noise2(x * 0.085, z * 0.085);
    if (slope >= 3 || (top >= seaLevel + 7 && cliffNoise > 0.48)) {
      return Blocks.stone;
    }
    if (top <= seaLevel + 5 && surfaceVariation > 0.52) {
      return Blocks.gravel;
    }
    return Blocks.grass;
  }

  static int _maximumSlope(Uint8List heights, int x, int z, int top) {
    var slope = 0;
    for (final (dx, dz) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = (x + dx).clamp(0, WorldDims.worldBlocksX - 1);
      final nz = (z + dz).clamp(0, WorldDims.worldBlocksZ - 1);
      final difference = (top - heights[_columnIndex(nx, nz)]).abs();
      if (difference > slope) slope = difference;
    }
    return slope;
  }

  void _carveCaves(VoxelWorld world, Uint8List heights, _IslandsRandom random) {
    for (var cave = 0; cave < 105; cave++) {
      var x = 0;
      var z = 0;
      var top = 0;
      var found = false;
      for (var attempt = 0; attempt < 12; attempt++) {
        x = 5 + random.nextInt(WorldDims.worldBlocksX - 10);
        z = 5 + random.nextInt(WorldDims.worldBlocksZ - 10);
        top = heights[_columnIndex(x, z)];
        if (top >= seaLevel + 4 && !_insideSpawnBuffer(x, z)) {
          found = true;
          break;
        }
      }
      if (!found) continue;

      var y = 6 + random.nextInt(math.max(1, top - 10));
      final steps = 5 + random.nextInt(11);
      for (var step = 0; step < steps; step++) {
        final radius = random.nextInt(5) == 0 ? 2 : 1;
        _carveSphere(world, x, y, z, radius);
        x = (x + random.nextInt(3) - 1).clamp(3, WorldDims.worldBlocksX - 4);
        y = (y + random.nextInt(3) - 1).clamp(4, top - 4);
        z = (z + random.nextInt(3) - 1).clamp(3, WorldDims.worldBlocksZ - 4);
      }
    }
  }

  static void _carveSphere(
    VoxelWorld world,
    int centerX,
    int centerY,
    int centerZ,
    int radius,
  ) {
    final radiusSquared = radius * radius + 1;
    for (var dz = -radius; dz <= radius; dz++) {
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy + dz * dz > radiusSquared) continue;
          final x = centerX + dx;
          final y = centerY + dy;
          final z = centerZ + dz;
          if (y <= 1 ||
              !VoxelWorld.inBounds(x, y, z) ||
              _insideSpawnBuffer(x, z)) {
            continue;
          }
          if (_rawBlock(world, x, y, z) == Blocks.stone) {
            _writeRaw(world, x, y, z, Blocks.air);
          }
        }
      }
    }
  }

  void _placeOres(VoxelWorld world, Uint8List heights, _IslandsRandom random) {
    _placeOreVeins(
      world,
      heights,
      random,
      block: Blocks.oreCoal,
      veinCount: 390,
      minY: 4,
      maxY: 48,
      steps: 7,
    );
    _placeOreVeins(
      world,
      heights,
      random,
      block: Blocks.oreIron,
      veinCount: 270,
      minY: 4,
      maxY: 38,
      steps: 6,
    );
    _placeOreVeins(
      world,
      heights,
      random,
      block: Blocks.oreGold,
      veinCount: 105,
      minY: 3,
      maxY: 22,
      steps: 5,
    );
  }

  static void _placeOreVeins(
    VoxelWorld world,
    Uint8List heights,
    _IslandsRandom random, {
    required int block,
    required int veinCount,
    required int minY,
    required int maxY,
    required int steps,
  }) {
    for (var vein = 0; vein < veinCount; vein++) {
      var x = 0;
      var y = 0;
      var z = 0;
      var found = false;
      for (var attempt = 0; attempt < 10; attempt++) {
        x = 2 + random.nextInt(WorldDims.worldBlocksX - 4);
        z = 2 + random.nextInt(WorldDims.worldBlocksZ - 4);
        final top = heights[_columnIndex(x, z)];
        final upperY = math.min(maxY, top - 4);
        if (upperY < minY) continue;
        y = minY + random.nextInt(upperY - minY + 1);
        if (_rawBlock(world, x, y, z) == Blocks.stone) {
          found = true;
          break;
        }
      }
      if (!found) continue;

      for (var step = 0; step < steps; step++) {
        final radiusSquared = random.nextInt(4) == 0 ? 3 : 2;
        for (var dz = -1; dz <= 1; dz++) {
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx * dx + dy * dy + dz * dz > radiusSquared) continue;
              final blockX = x + dx;
              final blockY = y + dy;
              final blockZ = z + dz;
              if (!VoxelWorld.inBounds(blockX, blockY, blockZ) ||
                  blockY < minY ||
                  blockY > maxY) {
                continue;
              }
              if (_rawBlock(world, blockX, blockY, blockZ) == Blocks.stone) {
                _writeRaw(world, blockX, blockY, blockZ, block);
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

  static void _placeTrees(
    VoxelWorld world,
    Uint8List heights,
    _IslandsRandom random,
  ) {
    for (var z = 2; z < WorldDims.worldBlocksZ - 2; z++) {
      for (var x = 2; x < WorldDims.worldBlocksX - 2; x++) {
        if (random.nextInt(68) != 0 || _insideSpawnBuffer(x, z)) continue;
        final surfaceY = heights[_columnIndex(x, z)];
        if (_rawBlock(world, x, surfaceY, z) != Blocks.grass) continue;

        final trunkHeight = 4 + random.nextInt(3);
        final baseY = surfaceY + 1;
        final crownTop = baseY + trunkHeight;
        if (crownTop >= WorldDims.worldBlocksY ||
            !_treeVolumeIsClear(world, x, baseY, z, crownTop)) {
          continue;
        }

        for (var y = baseY; y < baseY + trunkHeight; y++) {
          _writeRaw(world, x, y, z, Blocks.logOak);
        }
        for (var y = crownTop - 2; y <= crownTop; y++) {
          for (var dz = -2; dz <= 2; dz++) {
            for (var dx = -2; dx <= 2; dx++) {
              if (dx.abs() == 2 && dz.abs() == 2) continue;
              final blockX = x + dx;
              final blockZ = z + dz;
              if (_rawBlock(world, blockX, y, blockZ) == Blocks.air) {
                _writeRaw(world, blockX, y, blockZ, Blocks.leavesOak);
              }
            }
          }
        }
      }
    }
  }

  static bool _treeVolumeIsClear(
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

  static void _placePlants(
    VoxelWorld world,
    Uint8List heights,
    _IslandsRandom random,
  ) {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        if (_insideSafeSpawn(x, z)) continue;
        final surfaceY = heights[_columnIndex(x, z)];
        if (surfaceY + 1 >= WorldDims.worldBlocksY ||
            _rawBlock(world, x, surfaceY, z) != Blocks.grass ||
            _rawBlock(world, x, surfaceY + 1, z) != Blocks.air) {
          continue;
        }

        final roll = random.nextInt(640);
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

  static bool _insideSafeSpawn(int x, int z) =>
      (x - spawnX).abs() <= safeSpawnHalfExtent &&
      (z - spawnZ).abs() <= safeSpawnHalfExtent;

  static bool _insideSpawnBuffer(int x, int z) =>
      (x - spawnX).abs() <= _spawnFeatureBuffer &&
      (z - spawnZ).abs() <= _spawnFeatureBuffer;

  static int _columnIndex(int x, int z) => x + z * WorldDims.worldBlocksX;

  static void _clear(VoxelWorld world) {
    for (final chunk in world.chunks) {
      chunk.blocks.fillRange(0, chunk.blocks.length, Blocks.air);
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

final class _Island {
  _Island({
    required this.x,
    required this.z,
    required this.radiusX,
    required this.radiusZ,
    required double angle,
    required this.peakHeight,
    required this.reliefPower,
  }) : cosine = math.cos(angle),
       sine = math.sin(angle);

  final double x;
  final double z;
  final double radiusX;
  final double radiusZ;
  final double cosine;
  final double sine;
  final int peakHeight;
  final double reliefPower;

  double strengthAt(int worldX, int worldZ) {
    final dx = worldX - x;
    final dz = worldZ - z;
    final rotatedX = dx * cosine - dz * sine;
    final rotatedZ = dx * sine + dz * cosine;
    final normalizedX = rotatedX / radiusX;
    final normalizedZ = rotatedZ / radiusZ;
    return 1 - math.sqrt(normalizedX * normalizedX + normalizedZ * normalizedZ);
  }
}

final class _IslandsRandom {
  _IslandsRandom(int seed) : _state = seed & 0xffffffff {
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

  double nextDouble() => nextInt(0x1000000) / 0x1000000;
}

/// Value noise whose integer hash deliberately avoids products above 2^53.
///
/// Dart VM integers are arbitrary precision while JavaScript numbers are not.
/// Keeping every hash multiplication split into 16-bit limbs makes the same
/// seed produce the same lattice values on native and web runtimes.
final class _PortableValueNoise {
  const _PortableValueNoise(this.seed);

  final int seed;

  double noise2(double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final tx = _fade(x - x0);
    final ty = _fade(y - y0);
    final a = _lerp(_lattice(x0, y0), _lattice(x0 + 1, y0), tx);
    final b = _lerp(_lattice(x0, y0 + 1), _lattice(x0 + 1, y0 + 1), tx);
    return _lerp(a, b, ty);
  }

  double fbm2(
    double x,
    double y, {
    int octaves = 4,
    double lacunarity = 2,
    double persistence = 0.5,
  }) {
    if (octaves <= 0) return 0;
    var value = 0.0;
    var amplitude = 1.0;
    var frequency = 1.0;
    var amplitudeSum = 0.0;
    for (var octave = 0; octave < octaves; octave++) {
      value += noise2(x * frequency, y * frequency) * amplitude;
      amplitudeSum += amplitude;
      frequency *= lacunarity;
      amplitude *= persistence;
    }
    return value / amplitudeSum;
  }

  double _lattice(int x, int y) {
    var hash =
        (seed & 0x7fffffff) ^
        ((x * 0x1f123bb5) & 0x7fffffff) ^
        ((y * 0x5f356495) & 0x7fffffff);
    hash = _mul32((hash >> 16) ^ hash, 0x045d9f3b) & 0x7fffffff;
    hash = _mul32((hash >> 16) ^ hash, 0x045d9f3b) & 0x7fffffff;
    hash = (hash >> 16) ^ hash;
    return hash / 0x7fffffff * 2.0 - 1.0;
  }

  static int _mul32(int left, int right) {
    final leftLow = left & 0xffff;
    final leftHigh = (left >> 16) & 0xffff;
    final rightLow = right & 0xffff;
    final rightHigh = (right >> 16) & 0xffff;
    final low = leftLow * rightLow;
    final middle = (leftHigh * rightLow + leftLow * rightHigh) & 0xffff;
    return (low + middle * 0x10000) & 0xffffffff;
  }

  static double _fade(double value) => value * value * (3 - 2 * value);

  static double _lerp(double from, double to, double t) =>
      from + (to - from) * t;
}
