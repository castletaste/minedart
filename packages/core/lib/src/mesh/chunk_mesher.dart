library;

import 'dart:typed_data';

import '../block.dart';
import '../chunk.dart';
import '../mesh_data.dart';
import 'chunk_snapshot.dart';

/// Deterministic culled chunk mesher with skylight, directional shading, and
/// per-corner ambient occlusion. It reads only immutable snapshot buffers and
/// keeps each render pass within the Uint16 indexable vertex set.
final class ChunkMesher {
  const ChunkMesher();

  ChunkMeshData mesh(ChunkSnapshot snapshot) {
    final opaque = _BufferWriter();
    final translucent = _BufferWriter();
    final blocks = snapshot.blocks;
    final opaqueInteriorFaces = <int>[];
    final translucentInteriorFaces = <int>[];

    for (var y = 0; y < WorldDims.chunkSize; y++) {
      final snapshotY = y + 1;
      final sliceOffset = snapshotY * ChunkSnapshot.sliceArea;
      for (var z = 0; z < WorldDims.chunkSize; z++) {
        final snapshotZ = z + 1;
        final rowOffset = sliceOffset + snapshotZ * ChunkSnapshot.size + 1;
        for (var x = 0; x < WorldDims.chunkSize; x++) {
          final raw = blocks[rowOffset + x];
          final id = Blocks.id(raw);
          if (id == Blocks.air) continue;
          final def = blockDefs[id]!;

          if (def.cross) {
            _writeCross(opaque, snapshot, x, y, z, def.tiles[Face.posZ]);
            continue;
          }

          final writer = def.translucent ? translucent : opaque;
          for (var face = 0; face < 6; face++) {
            final normalOffset = face * 3;
            final neighborRaw = snapshot.blockAt(
              x + _faceNormals[normalOffset],
              y + _faceNormals[normalOffset + 1],
              z + _faceNormals[normalOffset + 2],
            );
            if (_shouldEmitFace(id, def, neighborRaw)) {
              if (Blocks.id(neighborRaw) == Blocks.air) {
                _writeCubeFace(
                  writer,
                  snapshot,
                  x,
                  y,
                  z,
                  face,
                  def.tiles[face],
                  isWater:
                      def.behavior == BlockBehavior.water ||
                      def.behavior == BlockBehavior.lava,
                );
              } else {
                final interiorFaces = def.translucent
                    ? translucentInteriorFaces
                    : opaqueInteriorFaces;
                interiorFaces.add(_encodeFace(x, y, z, face));
              }
            }
          }
        }
      }
    }

    // Faces exposed to air and complete X-sprites are already present. Fill
    // the remaining Uint16 budget with occupied-to-occupied interfaces; if a
    // future/adversarial registry arrangement exceeds the proven current
    // bound, omissions are spread deterministically across interior faces and
    // can never erase the chunk silhouette.
    _writeInteriorFaces(opaque, snapshot, opaqueInteriorFaces);
    _writeInteriorFaces(translucent, snapshot, translucentInteriorFaces);

    return ChunkMeshData(
      chunkIndex: snapshot.chunkIndex,
      revision: snapshot.revision,
      opaqueVertices: opaque.takeVertices(),
      opaqueIndices: opaque.takeIndices(),
      translucentVertices: translucent.takeVertices(),
      translucentIndices: translucent.takeIndices(),
    );
  }

  static bool _shouldEmitFace(int id, BlockDef def, int neighborRaw) {
    final neighborId = Blocks.id(neighborRaw);
    if (neighborId == Blocks.air) return true;
    final neighborDef = neighborId < blockDefs.length
        ? blockDefs[neighborId]
        : null;
    if ((def.behavior == BlockBehavior.water ||
            def.behavior == BlockBehavior.lava) &&
        neighborDef?.behavior == def.behavior) {
      return false;
    }
    if (neighborDef?.opaque ?? false) return false;

    // Two non-opaque cubes in the same render pass would otherwise emit
    // opposite coplanar quads. The material is double-sided, so retain one
    // deterministic face. Prefer visually denser leaves/lava over
    // glass/water, then use block id as a stable future-proof tie-breaker.
    if (!def.opaque &&
        neighborDef != null &&
        !neighborDef.opaque &&
        !neighborDef.cross &&
        def.translucent == neighborDef.translucent) {
      if (id == neighborId || !_ownsSharedInteriorFace(id, neighborId)) {
        return false;
      }
    }
    return true;
  }

  static int _encodeFace(int x, int y, int z, int face) =>
      x | (y << 4) | (z << 8) | (face << 12);

  static void _writeInteriorFaces(
    _BufferWriter writer,
    ChunkSnapshot snapshot,
    List<int> faces,
  ) {
    final budget = writer.remainingQuadCapacity;
    if (budget == 0 || faces.isEmpty) return;

    if (faces.length <= budget) {
      for (final encoded in faces) {
        _writeEncodedFace(writer, snapshot, encoded);
      }
      return;
    }

    // Bresenham-style deterministic sampling avoids concentrating rare
    // overflow omissions in one corner of an adversarial builder chunk.
    var accumulator = 0;
    for (final encoded in faces) {
      accumulator += budget;
      if (accumulator < faces.length) continue;
      accumulator -= faces.length;
      _writeEncodedFace(writer, snapshot, encoded);
    }
  }

  static void _writeEncodedFace(
    _BufferWriter writer,
    ChunkSnapshot snapshot,
    int encoded,
  ) {
    final x = encoded & 15;
    final y = (encoded >> 4) & 15;
    final z = (encoded >> 8) & 15;
    final face = (encoded >> 12) & 7;
    final id = Blocks.id(snapshot.blockAt(x, y, z));
    final def = blockDefs[id]!;
    _writeCubeFace(
      writer,
      snapshot,
      x,
      y,
      z,
      face,
      def.tiles[face],
      isWater:
          def.behavior == BlockBehavior.water ||
          def.behavior == BlockBehavior.lava,
    );
  }

  static bool _ownsSharedInteriorFace(int id, int neighborId) {
    final priority = _surfaceCoveragePriority(id);
    final neighborPriority = _surfaceCoveragePriority(neighborId);
    return priority == neighborPriority
        ? id < neighborId
        : priority > neighborPriority;
  }

  static int _surfaceCoveragePriority(int id) => switch (id) {
    Blocks.leavesOak || Blocks.lava => 2,
    Blocks.glass || Blocks.water => 1,
    _ => 0,
  };

  static void _writeCubeFace(
    _BufferWriter writer,
    ChunkSnapshot snapshot,
    int x,
    int y,
    int z,
    int face,
    int tile, {
    required bool isWater,
  }) {
    if (!writer.canWriteQuads(1)) return;
    final normalOffset = face * 3;
    final normalX = _faceNormals[normalOffset];
    final normalY = _faceNormals[normalOffset + 1];
    final normalZ = _faceNormals[normalOffset + 2];
    final light = _faceBaseLight(snapshot, x, y, z, normalX, normalY, normalZ);
    final shadedLight = light * _faceShades[face];
    final cornerOffset = face * 12;

    final ao0 = _cornerAo(snapshot, x, y, z, face, cornerOffset);
    final ao1 = _cornerAo(snapshot, x, y, z, face, cornerOffset + 3);
    final ao2 = _cornerAo(snapshot, x, y, z, face, cornerOffset + 6);
    final ao3 = _cornerAo(snapshot, x, y, z, face, cornerOffset + 9);
    if (!writer.writeQuadIndices(flip: ao0 + ao2 > ao1 + ao3)) return;

    _writeFaceVertex(
      writer,
      x,
      y,
      z,
      cornerOffset,
      0,
      tile,
      normalX,
      normalY,
      normalZ,
      shadedLight * ao0,
      isWater,
    );
    _writeFaceVertex(
      writer,
      x,
      y,
      z,
      cornerOffset + 3,
      1,
      tile,
      normalX,
      normalY,
      normalZ,
      shadedLight * ao1,
      isWater,
    );
    _writeFaceVertex(
      writer,
      x,
      y,
      z,
      cornerOffset + 6,
      2,
      tile,
      normalX,
      normalY,
      normalZ,
      shadedLight * ao2,
      isWater,
    );
    _writeFaceVertex(
      writer,
      x,
      y,
      z,
      cornerOffset + 9,
      3,
      tile,
      normalX,
      normalY,
      normalZ,
      shadedLight * ao3,
      isWater,
    );
  }

  static void _writeFaceVertex(
    _BufferWriter writer,
    int x,
    int y,
    int z,
    int cornerOffset,
    int uvCorner,
    int tile,
    int normalX,
    int normalY,
    int normalZ,
    double light,
    bool isWater,
  ) {
    final cornerY = _faceCorners[cornerOffset + 1];
    writer.writeVertex(
      x + _faceCorners[cornerOffset].toDouble(),
      y + (isWater && cornerY == 1 ? _waterSurfaceHeight : cornerY.toDouble()),
      z + _faceCorners[cornerOffset + 2].toDouble(),
      uvCorner,
      tile,
      light,
      normalX.toDouble(),
      normalY.toDouble(),
      normalZ.toDouble(),
    );
  }

  static double _cornerAo(
    ChunkSnapshot snapshot,
    int x,
    int y,
    int z,
    int face,
    int cornerOffset,
  ) {
    final normalOffset = face * 3;
    final normalX = _faceNormals[normalOffset];
    final normalY = _faceNormals[normalOffset + 1];
    final normalZ = _faceNormals[normalOffset + 2];
    final axisA = _tangentAxisA[face];
    final axisB = _tangentAxisB[face];
    final signA = _faceCorners[cornerOffset + axisA] == 0 ? -1 : 1;
    final signB = _faceCorners[cornerOffset + axisB] == 0 ? -1 : 1;

    final externalX = x + normalX;
    final externalY = y + normalY;
    final externalZ = z + normalZ;
    var sideAX = externalX;
    var sideAY = externalY;
    var sideAZ = externalZ;
    var sideBX = externalX;
    var sideBY = externalY;
    var sideBZ = externalZ;
    if (axisA == 0) {
      sideAX += signA;
    } else if (axisA == 1) {
      sideAY += signA;
    } else {
      sideAZ += signA;
    }
    if (axisB == 0) {
      sideBX += signB;
    } else if (axisB == 1) {
      sideBY += signB;
    } else {
      sideBZ += signB;
    }

    final sideA = _isOpaque(snapshot, sideAX, sideAY, sideAZ);
    final sideB = _isOpaque(snapshot, sideBX, sideBY, sideBZ);
    var cornerX = sideAX;
    var cornerY = sideAY;
    var cornerZ = sideAZ;
    if (axisB == 0) {
      cornerX += signB;
    } else if (axisB == 1) {
      cornerY += signB;
    } else {
      cornerZ += signB;
    }
    final corner = _isOpaque(snapshot, cornerX, cornerY, cornerZ);

    final occlusion = sideA && sideB
        ? 3
        : (sideA ? 1 : 0) + (sideB ? 1 : 0) + (corner ? 1 : 0);
    return _aoLight[occlusion];
  }

  static bool _isOpaque(
    ChunkSnapshot snapshot,
    int localX,
    int localY,
    int localZ,
  ) {
    final raw = snapshot
        .blocks[ChunkSnapshot.indexOf(localX + 1, localY + 1, localZ + 1)];
    final id = Blocks.id(raw);
    return id != Blocks.air && blockDefs[id]!.blocksLight;
  }

  static double _faceBaseLight(
    ChunkSnapshot snapshot,
    int x,
    int y,
    int z,
    int normalX,
    int normalY,
    int normalZ,
  ) {
    final worldY = snapshot.worldOriginY + y + normalY;
    if (worldY < 0 || worldY >= WorldDims.worldBlocksY) return 1;
    final snapshotX = x + normalX + 1;
    final snapshotZ = z + normalZ + 1;
    final height =
        snapshot.skyHeight[ChunkSnapshot.skyIndexOf(snapshotX, snapshotZ)];
    return worldY >= height ? 1 : 0.6;
  }

  static void _writeCross(
    _BufferWriter writer,
    ChunkSnapshot snapshot,
    int x,
    int y,
    int z,
    int tile,
  ) {
    // Keep both crossed planes or neither. With current block definitions the
    // air-facing faces plus complete sprites fit before interior faces.
    if (!writer.canWriteQuads(2)) return;
    final worldY = snapshot.worldOriginY + y;
    final height = snapshot.skyHeight[ChunkSnapshot.skyIndexOf(x + 1, z + 1)];
    final base =
        (worldY < 0 || worldY >= WorldDims.worldBlocksY || worldY >= height)
        ? 0.8
        : 0.48;
    const diagonal = 0.7071067811865476;

    _writeCrossQuad(
      writer,
      x,
      y,
      z,
      tile,
      base,
      0,
      0,
      0,
      1,
      0,
      1,
      1,
      1,
      1,
      0,
      1,
      0,
      -diagonal,
      0,
      diagonal,
    );
    _writeCrossQuad(
      writer,
      x,
      y,
      z,
      tile,
      base,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      1,
      1,
      1,
      1,
      0,
      -diagonal,
      0,
      -diagonal,
    );
  }

  static void _writeCrossQuad(
    _BufferWriter writer,
    int x,
    int y,
    int z,
    int tile,
    double light,
    int x0,
    int y0,
    int z0,
    int x1,
    int y1,
    int z1,
    int x2,
    int y2,
    int z2,
    int x3,
    int y3,
    int z3,
    double normalX,
    double normalY,
    double normalZ,
  ) {
    if (!writer.writeQuadIndices(flip: false)) return;
    writer.writeVertex(
      x + x0.toDouble(),
      y + y0.toDouble(),
      z + z0.toDouble(),
      0,
      tile,
      light,
      normalX,
      normalY,
      normalZ,
    );
    writer.writeVertex(
      x + x1.toDouble(),
      y + y1.toDouble(),
      z + z1.toDouble(),
      1,
      tile,
      light,
      normalX,
      normalY,
      normalZ,
    );
    writer.writeVertex(
      x + x2.toDouble(),
      y + y2.toDouble(),
      z + z2.toDouble(),
      2,
      tile,
      light,
      normalX,
      normalY,
      normalZ,
    );
    writer.writeVertex(
      x + x3.toDouble(),
      y + y3.toDouble(),
      z + z3.toDouble(),
      3,
      tile,
      light,
      normalX,
      normalY,
      normalZ,
    );
  }
}

final class _BufferWriter {
  _BufferWriter()
    : _vertices = Float32List(64 * 4 * VertexLayout.floatsPerVertex),
      _indices = Uint16List(64 * 6);

  Float32List _vertices;
  Uint16List _indices;
  int _vertexFloatOffset = 0;
  int _indexOffset = 0;

  int get _vertexCount => _vertexFloatOffset ~/ VertexLayout.floatsPerVertex;

  int get remainingQuadCapacity => (_uint16VertexCount - _vertexCount) ~/ 4;

  bool canWriteQuads(int count) =>
      _vertexCount + count * 4 <= _uint16VertexCount;

  bool writeQuadIndices({required bool flip}) {
    final first = _vertexCount;
    if (!canWriteQuads(1)) return false;
    assert(first + 3 <= 0xFFFF, 'Every vertex index must fit Uint16.');
    _ensureIndexCapacity(6);
    if (flip) {
      _indices[_indexOffset++] = first;
      _indices[_indexOffset++] = first + 1;
      _indices[_indexOffset++] = first + 3;
      _indices[_indexOffset++] = first + 1;
      _indices[_indexOffset++] = first + 2;
      _indices[_indexOffset++] = first + 3;
    } else {
      _indices[_indexOffset++] = first;
      _indices[_indexOffset++] = first + 1;
      _indices[_indexOffset++] = first + 2;
      _indices[_indexOffset++] = first;
      _indices[_indexOffset++] = first + 2;
      _indices[_indexOffset++] = first + 3;
    }
    return true;
  }

  void writeVertex(
    double x,
    double y,
    double z,
    int uvCorner,
    int tile,
    double light,
    double normalX,
    double normalY,
    double normalZ,
  ) {
    _ensureVertexCapacity(VertexLayout.floatsPerVertex);
    final offset = _vertexFloatOffset;
    _vertices[offset] = x;
    _vertices[offset + 1] = y;
    _vertices[offset + 2] = z;

    final tileX = tile & 15;
    final tileY = tile >> 4;
    final u0 = tileX / 16 + _atlasInset;
    final v0 = tileY / 16 + _atlasInset;
    final u1 = (tileX + 1) / 16 - _atlasInset;
    final v1 = (tileY + 1) / 16 - _atlasInset;
    _vertices[offset + 3] = uvCorner == 0 || uvCorner == 3 ? u0 : u1;
    // Corners 0,1 are the block-space bottom of the face; they must sample the
    // tile's bottom row (v1). Texture images have v0 at the top.
    _vertices[offset + 4] = uvCorner < 2 ? v1 : v0;

    _vertices[offset + 5] = light;
    _vertices[offset + 6] = light;
    _vertices[offset + 7] = light;
    _vertices[offset + 8] = 1;
    _vertices[offset + 9] = normalX;
    _vertices[offset + 10] = normalY;
    _vertices[offset + 11] = normalZ;
    // joints[4] and weights[4] occupy slots 12..19 and remain zero.
    _vertexFloatOffset += VertexLayout.floatsPerVertex;
  }

  Float32List takeVertices() {
    if (_vertexFloatOffset == 0) return Float32List(0);
    final result = Float32List(_vertexFloatOffset);
    result.setRange(0, _vertexFloatOffset, _vertices);
    return result;
  }

  Uint16List takeIndices() {
    if (_indexOffset == 0) return Uint16List(0);
    final result = Uint16List(_indexOffset);
    result.setRange(0, _indexOffset, _indices);
    return result;
  }

  void _ensureVertexCapacity(int additionalFloats) {
    final required = _vertexFloatOffset + additionalFloats;
    if (required <= _vertices.length) return;
    var capacity = _vertices.length * 2;
    while (capacity < required) {
      capacity *= 2;
    }
    final grown = Float32List(capacity);
    grown.setRange(0, _vertexFloatOffset, _vertices);
    _vertices = grown;
  }

  void _ensureIndexCapacity(int additionalIndices) {
    final required = _indexOffset + additionalIndices;
    if (required <= _indices.length) return;
    var capacity = _indices.length * 2;
    while (capacity < required) {
      capacity *= 2;
    }
    final grown = Uint16List(capacity);
    grown.setRange(0, _indexOffset, _indices);
    _indices = grown;
  }
}

const double _atlasInset = 0.5 / 256;
const double _waterSurfaceHeight = 0.875;
const int _uint16VertexCount = 1 << 16;

/// Face order: +X, -X, +Y, -Y, +Z, -Z.
const _faceNormals = <int>[
  1,
  0,
  0,
  -1,
  0,
  0,
  0,
  1,
  0,
  0,
  -1,
  0,
  0,
  0,
  1,
  0,
  0,
  -1,
];

const _faceShades = <double>[0.6, 0.6, 1, 0.5, 0.8, 0.8];
const _aoLight = <double>[1, 0.75, 0.5, 0.35];
const _tangentAxisA = <int>[1, 1, 0, 0, 0, 0];
const _tangentAxisB = <int>[2, 2, 2, 2, 1, 1];

/// Four outward-CCW corners for each face.
const _faceCorners = <int>[
  // +X
  1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1,
  // -X
  0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0,
  // +Y
  0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0,
  // -Y
  0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1,
  // +Z
  0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1,
  // -Z
  1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0,
];
