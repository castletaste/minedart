/// Chunk storage: 16^3 blocks in a Uint16List, plus a per-chunk skylight map.
library;

import 'dart:typed_data';

/// World/chunk dimension constants (Minecraft Classic scale).
abstract final class WorldDims {
  static const int chunkSize = 16;
  static const int worldChunksX = 16; // 256 blocks
  static const int worldChunksY = 4; // 64 blocks
  static const int worldChunksZ = 16; // 256 blocks
  static const int worldBlocksX = worldChunksX * chunkSize;
  static const int worldBlocksY = worldChunksY * chunkSize;
  static const int worldBlocksZ = worldChunksZ * chunkSize;
  static const int seaLevel = 32;
}

/// Index math shared by every consumer. Storage order: x + z*16 + y*256
/// (y-major so horizontal slices are contiguous).
abstract final class ChunkIndex {
  static const int size = WorldDims.chunkSize;
  static const int sliceArea = size * size;
  static const int volume = size * size * size;

  static int of(int x, int y, int z) => x + z * size + y * sliceArea;
}

final class Chunk {
  Chunk(this.cx, this.cy, this.cz) : blocks = Uint16List(ChunkIndex.volume);

  Chunk.fromBlocks(this.cx, this.cy, this.cz, this.blocks)
    : assert(blocks.length == ChunkIndex.volume);

  final int cx;
  final int cy;
  final int cz;
  final Uint16List blocks;

  /// Monotonically increasing revision; bumped on every mutation. Used by the
  /// remesh pipeline to drop stale mesh jobs.
  int revision = 0;

  /// True when the chunk contains no non-air blocks (skip meshing entirely).
  bool get isEmpty => _nonAir == 0;
  int _nonAir = 0;

  int get nonAirCount => _nonAir;

  int at(int x, int y, int z) => blocks[ChunkIndex.of(x, y, z)];

  void set(int x, int y, int z, int raw) {
    final i = ChunkIndex.of(x, y, z);
    final old = blocks[i];
    if (old == raw) return;
    if (old == 0 && raw != 0) _nonAir++;
    if (old != 0 && raw == 0) _nonAir--;
    blocks[i] = raw;
    revision++;
  }

  /// Recomputes [nonAirCount] after bulk writes into [blocks].
  void recount() {
    var n = 0;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i] != 0) n++;
    }
    _nonAir = n;
    revision++;
  }
}
