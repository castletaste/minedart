import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:minedart_core/minedart_core.dart';

/// Immutable painter input copied from the world's top non-air surface.
///
/// The snapshot is detached from later world mutations and exposes only
/// unmodifiable typed-data views. A Flutter CustomPainter can therefore read it
/// without touching the mutable voxel world or scheduling a second 3D pass.
@immutable
final class MinimapSnapshot {
  factory MinimapSnapshot.fromWorld(VoxelWorld world, {int? sourceRevision}) {
    final width = WorldDims.worldBlocksX;
    final depth = WorldDims.worldBlocksZ;
    final heights = Uint8List(width * depth);
    final surfaceBlockIds = Uint16List(width * depth);
    var maxElevation = 0;
    for (var z = 0; z < depth; z++) {
      final row = z * width;
      for (var x = 0; x < width; x++) {
        final index = row + x;
        var elevation = 0;
        var surfaceId = Blocks.air;
        for (var cy = WorldDims.worldChunksY - 1; cy >= 0; cy--) {
          final chunk = world.chunkAt(x >> 4, cy, z >> 4);
          if (chunk.isEmpty) continue;
          for (var localY = WorldDims.chunkSize - 1; localY >= 0; localY--) {
            final raw = chunk.at(x & 15, localY, z & 15);
            final id = Blocks.id(raw);
            if (id == Blocks.air) continue;
            elevation = cy * WorldDims.chunkSize + localY + 1;
            surfaceId = id;
            break;
          }
          if (surfaceId != Blocks.air) break;
        }
        heights[index] = elevation;
        if (elevation > maxElevation) maxElevation = elevation;
        surfaceBlockIds[index] = surfaceId;
      }
    }
    return MinimapSnapshot._(
      width: width,
      depth: depth,
      heights: heights,
      surfaceBlockIds: surfaceBlockIds,
      maxElevation: maxElevation,
      seed: world.seed,
      sourceRevision: sourceRevision ?? revisionOf(world),
    );
  }

  factory MinimapSnapshot.fromHeightmap({
    required int width,
    required int depth,
    required Uint8List heights,
    Uint16List? surfaceBlockIds,
    int seed = 0,
    int sourceRevision = 0,
  }) {
    if (width <= 0 || depth <= 0) {
      throw ArgumentError('width and depth must be positive');
    }
    final expectedLength = width * depth;
    if (heights.length != expectedLength) {
      throw ArgumentError.value(
        heights.length,
        'heights.length',
        'expected $expectedLength',
      );
    }
    if (surfaceBlockIds != null && surfaceBlockIds.length != expectedLength) {
      throw ArgumentError.value(
        surfaceBlockIds.length,
        'surfaceBlockIds.length',
        'expected $expectedLength',
      );
    }
    final heightCopy = Uint8List.fromList(heights);
    var maxElevation = 0;
    for (var i = 0; i < heightCopy.length; i++) {
      if (heightCopy[i] > maxElevation) maxElevation = heightCopy[i];
    }
    return MinimapSnapshot._(
      width: width,
      depth: depth,
      heights: heightCopy,
      surfaceBlockIds: surfaceBlockIds == null
          ? Uint16List(expectedLength)
          : Uint16List.fromList(surfaceBlockIds),
      maxElevation: maxElevation,
      seed: seed,
      sourceRevision: sourceRevision,
    );
  }

  MinimapSnapshot._({
    required this.width,
    required this.depth,
    required Uint8List heights,
    required Uint16List surfaceBlockIds,
    required this.maxElevation,
    required this.seed,
    required this.sourceRevision,
  }) : heights = heights.asUnmodifiableView(),
       surfaceBlockIds = surfaceBlockIds.asUnmodifiableView();

  final int width;
  final int depth;

  /// Alias used by 2D painters where Z is the vertical canvas dimension.
  int get height => depth;

  final Uint8List heights;
  final Uint16List surfaceBlockIds;
  final int maxElevation;
  final int seed;
  final int sourceRevision;

  static int revisionOf(VoxelWorld world) {
    var hash = 17;
    for (var i = 0; i < world.chunks.length; i++) {
      hash = ((hash * 31) ^ world.chunks[i].revision ^ i) & 0x7fffffff;
    }
    return hash;
  }

  int get cellCount => width * depth;

  int elevationAt(int x, int z) => heights[_indexOf(x, z)];

  int heightAt(int x, int z) => elevationAt(x, z);

  int surfaceBlockAt(int x, int z) => surfaceBlockIds[_indexOf(x, z)];

  int blockIdAt(int x, int z) => surfaceBlockAt(x, z);

  double normalizedElevationAt(int x, int z) =>
      maxElevation == 0 ? 0 : elevationAt(x, z) / maxElevation;

  int _indexOf(int x, int z) {
    if (x < 0 || x >= width) {
      throw RangeError.range(x, 0, width - 1, 'x');
    }
    if (z < 0 || z >= depth) {
      throw RangeError.range(z, 0, depth - 1, 'z');
    }
    return x + z * width;
  }
}
