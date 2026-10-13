import 'package:minedart_core/minedart_core.dart';

/// Pure view math shared by chunk scheduling and visibility updates.
final class ChunkViewPlanner {
  const ChunkViewPlanner._();

  static ChunkViewPlan plan({
    required double playerX,
    required double playerZ,
    required int renderDistanceChunks,
  }) {
    final distance = renderDistanceChunks.clamp(2, WorldDims.worldChunksX);
    final centerX = (playerX ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksX - 1,
    );
    final centerZ = (playerZ ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksZ - 1,
    );
    return ChunkViewPlan(
      centerX: centerX,
      centerZ: centerZ,
      renderDistanceChunks: distance,
      minX: (centerX - distance).clamp(0, WorldDims.worldChunksX - 1),
      maxX: (centerX + distance).clamp(0, WorldDims.worldChunksX - 1),
      minZ: (centerZ - distance).clamp(0, WorldDims.worldChunksZ - 1),
      maxZ: (centerZ + distance).clamp(0, WorldDims.worldChunksZ - 1),
    );
  }
}

final class ChunkViewPlan {
  const ChunkViewPlan({
    required this.centerX,
    required this.centerZ,
    required this.renderDistanceChunks,
    required this.minX,
    required this.maxX,
    required this.minZ,
    required this.maxZ,
  });

  final int centerX;
  final int centerZ;
  final int renderDistanceChunks;
  final int minX;
  final int maxX;
  final int minZ;
  final int maxZ;

  bool sameView(ChunkViewPlan other) =>
      centerX == other.centerX &&
      centerZ == other.centerZ &&
      renderDistanceChunks == other.renderDistanceChunks;

  bool containsChunk(int chunkX, int chunkZ) =>
      chunkX >= minX && chunkX <= maxX && chunkZ >= minZ && chunkZ <= maxZ;
}
