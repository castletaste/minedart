/// Transferable mesh output contract between mesher (isolate) and renderer.
library;

import 'dart:typed_data';

/// Vertex layout matches flame_3d 0.3.0 PackedSurface expectations:
/// 20 float32 per vertex: pos(3) uv(2) color(4) normal(3) joints(4) weights(4).
/// joints/weights are zero-filled.
abstract final class VertexLayout {
  static const int floatsPerVertex = 20;
  static const int bytesPerVertex = floatsPerVertex * 4;
}

/// Mesh for one chunk, split into passes. Buffers are transferable across
/// isolates without copying (send the underlying ByteBuffer).
final class ChunkMeshData {
  const ChunkMeshData({
    required this.chunkIndex,
    required this.revision,
    required this.opaqueVertices,
    required this.opaqueIndices,
    required this.translucentVertices,
    required this.translucentIndices,
  });

  final int chunkIndex;

  /// Chunk.revision at mesh time; renderer drops results older than current.
  final int revision;

  final Float32List opaqueVertices;
  final Uint16List opaqueIndices;
  final Float32List translucentVertices;
  final Uint16List translucentIndices;

  bool get isEmpty => opaqueIndices.isEmpty && translucentIndices.isEmpty;

  int get opaqueVertexCount =>
      opaqueVertices.length ~/ VertexLayout.floatsPerVertex;
  int get translucentVertexCount =>
      translucentVertices.length ~/ VertexLayout.floatsPerVertex;
}
