library;

import 'dart:isolate';
import 'dart:typed_data';

import '../chunk.dart';
import '../world.dart';

/// The transferable input for meshing one chunk.
///
/// [blocks] contains the 16^3 chunk plus a one-voxel halo on every side.
/// Snapshot coordinate (0, 0, 0) corresponds to chunk-local (-1, -1, -1).
/// Storage order is x + z * 18 + y * 18 * 18.
///
/// [skyHeight] contains the matching 18x18 x/z columns. Values are world-space
/// y coordinates. Columns outside the finite world use zero, which makes every
/// out-of-bounds block position count as open sky.
final class ChunkSnapshot {
  ChunkSnapshot({
    required this.cx,
    required this.cy,
    required this.cz,
    required this.revision,
    required this.blocks,
    required this.skyHeight,
  }) : assert(blocks.length == volume),
       assert(skyHeight.length == skyArea) {
    if (blocks.length != volume) {
      throw ArgumentError.value(blocks.length, 'blocks.length', volume);
    }
    if (skyHeight.length != skyArea) {
      throw ArgumentError.value(skyHeight.length, 'skyHeight.length', skyArea);
    }
    RangeError.checkValueInInterval(cx, 0, WorldDims.worldChunksX - 1, 'cx');
    RangeError.checkValueInInterval(cy, 0, WorldDims.worldChunksY - 1, 'cy');
    RangeError.checkValueInInterval(cz, 0, WorldDims.worldChunksZ - 1, 'cz');
  }

  static const int size = WorldDims.chunkSize + 2;
  static const int sliceArea = size * size;
  static const int volume = size * size * size;
  static const int skyArea = size * size;

  final int cx;
  final int cy;
  final int cz;
  final int revision;
  final Uint16List blocks;
  final Uint8List skyHeight;

  int get chunkIndex => VoxelWorld.chunkIndexOf(cx, cy, cz);
  int get worldOriginY => cy * WorldDims.chunkSize;

  static int indexOf(int snapshotX, int snapshotY, int snapshotZ) =>
      snapshotX + snapshotZ * size + snapshotY * sliceArea;

  static int skyIndexOf(int snapshotX, int snapshotZ) =>
      snapshotX + snapshotZ * size;

  /// Reads a block using chunk-local coordinates in the inclusive -1..16
  /// halo range.
  int blockAt(int localX, int localY, int localZ) =>
      blocks[indexOf(localX + 1, localY + 1, localZ + 1)];

  factory ChunkSnapshot.capture(VoxelWorld world, int cx, int cy, int cz) {
    RangeError.checkValueInInterval(cx, 0, WorldDims.worldChunksX - 1, 'cx');
    RangeError.checkValueInInterval(cy, 0, WorldDims.worldChunksY - 1, 'cy');
    RangeError.checkValueInInterval(cz, 0, WorldDims.worldChunksZ - 1, 'cz');

    final blocks = Uint16List(volume);
    final skyHeight = Uint8List(skyArea);
    final originX = cx * WorldDims.chunkSize;
    final originY = cy * WorldDims.chunkSize;
    final originZ = cz * WorldDims.chunkSize;

    for (var snapshotY = 0; snapshotY < size; snapshotY++) {
      final worldY = originY + snapshotY - 1;
      final sliceOffset = snapshotY * sliceArea;
      for (var snapshotZ = 0; snapshotZ < size; snapshotZ++) {
        final worldZ = originZ + snapshotZ - 1;
        final rowOffset = sliceOffset + snapshotZ * size;
        for (var snapshotX = 0; snapshotX < size; snapshotX++) {
          final worldX = originX + snapshotX - 1;
          blocks[rowOffset + snapshotX] = world.blockAt(worldX, worldY, worldZ);
        }
      }
    }

    for (var snapshotZ = 0; snapshotZ < size; snapshotZ++) {
      final worldZ = originZ + snapshotZ - 1;
      final rowOffset = snapshotZ * size;
      for (var snapshotX = 0; snapshotX < size; snapshotX++) {
        final worldX = originX + snapshotX - 1;
        if (worldX >= 0 &&
            worldX < WorldDims.worldBlocksX &&
            worldZ >= 0 &&
            worldZ < WorldDims.worldBlocksZ) {
          skyHeight[rowOffset + snapshotX] =
              world.skyHeight[worldX + worldZ * WorldDims.worldBlocksX];
        }
      }
    }

    final chunk = world.chunkAt(cx, cy, cz);
    return ChunkSnapshot(
      cx: cx,
      cy: cy,
      cz: cz,
      revision: chunk.revision,
      blocks: blocks,
      skyHeight: skyHeight,
    );
  }

  /// Reconstructs a snapshot from isolate-safe typed data, byte buffers, or
  /// one-shot [TransferableTypedData] values.
  factory ChunkSnapshot.fromBuffers({
    required int cx,
    required int cy,
    required int cz,
    required int revision,
    required Object blocks,
    required Object skyHeight,
  }) => ChunkSnapshot(
    cx: cx,
    cy: cy,
    cz: cz,
    revision: revision,
    blocks: _asUint16List(blocks, volume, 'blocks'),
    skyHeight: _asUint8List(skyHeight, skyArea, 'skyHeight'),
  );

  /// Returns exact-length buffers suitable for wrapping in
  /// [TransferableTypedData] or sending directly to a same-code isolate.
  ({
    int cx,
    int cy,
    int cz,
    int revision,
    ByteBuffer blocks,
    ByteBuffer skyHeight,
  })
  toBuffers() => (
    cx: cx,
    cy: cy,
    cz: cz,
    revision: revision,
    blocks: _exactBuffer(blocks),
    skyHeight: _exactBuffer(skyHeight),
  );
}

Uint16List _asUint16List(Object value, int length, String name) {
  if (value is Uint16List) {
    if (value.length != length) {
      throw ArgumentError.value(value.length, '$name.length', length);
    }
    return Uint16List.view(value.buffer, value.offsetInBytes, length);
  }
  final buffer = switch (value) {
    ByteBuffer buffer => buffer,
    TransferableTypedData data => data.materialize(),
    _ => throw ArgumentError.value(
      value,
      name,
      'Expected Uint16List or buffer',
    ),
  };
  if (buffer.lengthInBytes != length * Uint16List.bytesPerElement) {
    throw ArgumentError.value(buffer.lengthInBytes, '$name.lengthInBytes');
  }
  return buffer.asUint16List(0, length);
}

Uint8List _asUint8List(Object value, int length, String name) {
  if (value is Uint8List) {
    if (value.length != length) {
      throw ArgumentError.value(value.length, '$name.length', length);
    }
    return Uint8List.view(value.buffer, value.offsetInBytes, length);
  }
  final buffer = switch (value) {
    ByteBuffer buffer => buffer,
    TransferableTypedData data => data.materialize(),
    _ => throw ArgumentError.value(value, name, 'Expected Uint8List or buffer'),
  };
  if (buffer.lengthInBytes != length) {
    throw ArgumentError.value(buffer.lengthInBytes, '$name.lengthInBytes');
  }
  return buffer.asUint8List(0, length);
}

ByteBuffer _exactBuffer(TypedData data) {
  if (data.offsetInBytes == 0 &&
      data.lengthInBytes == data.buffer.lengthInBytes) {
    return data.buffer;
  }
  return Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  ).buffer;
}
