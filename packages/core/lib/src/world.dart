/// Finite world: fixed grid of chunks + column skylight heightmap.
library;

import 'dart:typed_data';

import 'block.dart';
import 'chunk.dart';

final class VoxelWorld {
  VoxelWorld()
    : chunks = List.generate(
        WorldDims.worldChunksX *
            WorldDims.worldChunksY *
            WorldDims.worldChunksZ,
        (i) {
          final cx = i % WorldDims.worldChunksX;
          final cz = (i ~/ WorldDims.worldChunksX) % WorldDims.worldChunksZ;
          final cy = i ~/ (WorldDims.worldChunksX * WorldDims.worldChunksZ);
          return Chunk(cx, cy, cz);
        },
        growable: false,
      ),
      skyHeight = Uint8List(WorldDims.worldBlocksX * WorldDims.worldBlocksZ);

  /// Chunk order: cx + cz*chunksX + cy*chunksX*chunksZ.
  final List<Chunk> chunks;

  /// Per-column height of the highest light-blocking block + 1.
  /// Blocks at y >= skyHeight[col] are in full skylight.
  final Uint8List skyHeight;

  int seed = 0;

  static int chunkIndexOf(int cx, int cy, int cz) =>
      cx +
      cz * WorldDims.worldChunksX +
      cy * WorldDims.worldChunksX * WorldDims.worldChunksZ;

  Chunk chunkAt(int cx, int cy, int cz) => chunks[chunkIndexOf(cx, cy, cz)];

  static bool inBounds(int x, int y, int z) =>
      x >= 0 &&
      y >= 0 &&
      z >= 0 &&
      x < WorldDims.worldBlocksX &&
      y < WorldDims.worldBlocksY &&
      z < WorldDims.worldBlocksZ;

  /// Raw Uint16 value; air (0) outside bounds.
  int blockAt(int x, int y, int z) {
    if (!inBounds(x, y, z)) return 0;
    final chunk = chunkAt(x >> 4, y >> 4, z >> 4);
    return chunk.at(x & 15, y & 15, z & 15);
  }

  /// Sets a block and maintains the skylight heightmap. Returns the set of
  /// chunk indices whose meshes are affected (every chunk whose one-voxel
  /// snapshot halo contains the changed voxel; light updates can extend this
  /// vertically).
  Set<int> setBlock(int x, int y, int z, int raw) {
    if (!inBounds(x, y, z)) return const {};
    final dirty = <int>{};
    final cx = x >> 4, cy = y >> 4, cz = z >> 4;
    final chunk = chunkAt(cx, cy, cz);
    final old = chunk.at(x & 15, y & 15, z & 15);
    if (old == raw) return const {};
    chunk.set(x & 15, y & 15, z & 15, raw);
    _markVoxelHaloDirty(x, y, z, dirty);

    // Skylight heightmap maintenance.
    final col = x + z * WorldDims.worldBlocksX;
    final oldHeight = skyHeight[col];
    final blocksLight = _blocksLight(raw);
    if (blocksLight && y + 1 > oldHeight) {
      skyHeight[col] = y + 1;
      _markColumnDirty(x, z, oldHeight, y + 1, dirty);
    } else if (!blocksLight && y + 1 == oldHeight) {
      var h = y;
      while (h > 0 && !_blocksLight(blockAt(x, h - 1, z))) {
        h--;
      }
      skyHeight[col] = h;
      _markColumnDirty(x, z, h, oldHeight, dirty);
    }
    return dirty;
  }

  static bool _blocksLight(int raw) {
    final def = blockDefs[Blocks.id(raw)];
    return def != null && def.blocksLight;
  }

  /// Recomputes the whole skylight heightmap (after worldgen/load).
  void recomputeSkylight() {
    for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
      for (var x = 0; x < WorldDims.worldBlocksX; x++) {
        var h = 0;
        for (var y = WorldDims.worldBlocksY - 1; y >= 0; y--) {
          if (_blocksLight(blockAt(x, y, z))) {
            h = y + 1;
            break;
          }
        }
        skyHeight[x + z * WorldDims.worldBlocksX] = h;
      }
    }
  }

  /// True when the block at (x,y,z) sees the sky directly.
  bool inSkylight(int x, int y, int z) {
    if (!inBounds(x, y, z)) return true;
    return y >= skyHeight[x + z * WorldDims.worldBlocksX];
  }

  /// Marks the Cartesian product of chunk coordinates whose 18^3 snapshots
  /// contain this voxel. At a three-axis chunk corner that is eight chunks,
  /// including edge and corner diagonals needed by per-corner AO.
  void _markVoxelHaloDirty(int x, int y, int z, Set<int> dirty) {
    final cx = x >> 4, cy = y >> 4, cz = z >> 4;
    final lx = x & 15, ly = y & 15, lz = z & 15;
    final minCx = lx == 0 && cx > 0 ? cx - 1 : cx;
    final maxCx = lx == 15 && cx < WorldDims.worldChunksX - 1 ? cx + 1 : cx;
    final minCy = ly == 0 && cy > 0 ? cy - 1 : cy;
    final maxCy = ly == 15 && cy < WorldDims.worldChunksY - 1 ? cy + 1 : cy;
    final minCz = lz == 0 && cz > 0 ? cz - 1 : cz;
    final maxCz = lz == 15 && cz < WorldDims.worldChunksZ - 1 ? cz + 1 : cz;

    for (var dirtyCy = minCy; dirtyCy <= maxCy; dirtyCy++) {
      for (var dirtyCz = minCz; dirtyCz <= maxCz; dirtyCz++) {
        for (var dirtyCx = minCx; dirtyCx <= maxCx; dirtyCx++) {
          dirty.add(chunkIndexOf(dirtyCx, dirtyCy, dirtyCz));
        }
      }
    }
  }

  void _markColumnDirty(int x, int z, int fromY, int toY, Set<int> dirty) {
    final cx = x >> 4, cz = z >> 4;
    final loCy = ((fromY - 1).clamp(0, WorldDims.worldBlocksY - 1)) >> 4;
    final hiCy = ((toY - 1).clamp(0, WorldDims.worldBlocksY - 1)) >> 4;
    final lx = x & 15, lz = z & 15;
    final minCx = lx == 0 && cx > 0 ? cx - 1 : cx;
    final maxCx = lx == 15 && cx < WorldDims.worldChunksX - 1 ? cx + 1 : cx;
    final minCz = lz == 0 && cz > 0 ? cz - 1 : cz;
    final maxCz = lz == 15 && cz < WorldDims.worldChunksZ - 1 ? cz + 1 : cz;
    for (var cy = loCy; cy <= hiCy; cy++) {
      // Snapshot skylight has the same one-column x/z halo as block data, so
      // a corner column belongs to all four horizontal chunk snapshots.
      for (var dirtyCz = minCz; dirtyCz <= maxCz; dirtyCz++) {
        for (var dirtyCx = minCx; dirtyCx <= maxCx; dirtyCx++) {
          dirty.add(chunkIndexOf(dirtyCx, cy, dirtyCz));
        }
      }
    }
  }
}
