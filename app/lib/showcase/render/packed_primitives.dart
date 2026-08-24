import 'dart:typed_data';

import 'package:flame_3d/resources.dart';
import 'package:minedart_core/minedart_core.dart';

import '../../render/packed_surface.dart';

/// Immutable bounds used by the small, eagerly-built showcase meshes.
final class PackedCuboid {
  const PackedCuboid({
    required this.minX,
    required this.minY,
    required this.minZ,
    required this.maxX,
    required this.maxY,
    required this.maxZ,
  }) : assert(minX <= maxX),
       assert(minY <= maxY),
       assert(minZ <= maxZ);

  final double minX;
  final double minY;
  final double minZ;
  final double maxX;
  final double maxY;
  final double maxZ;
}

/// Packed 20-float geometry for tiny meshes created outside the frame loop.
///
/// This deliberately mirrors the canonical [PackedSurface] path. It never
/// materializes Flame `Vertex` objects and the generated buffers are retained
/// for the lifetime of the owning outline/particle pool.
final class PackedPrimitiveGeometry {
  PackedPrimitiveGeometry._(this._vertices, this._indices);

  factory PackedPrimitiveGeometry.cuboids(List<PackedCuboid> cuboids) {
    if (cuboids.isEmpty) {
      throw ArgumentError.value(cuboids, 'cuboids', 'must not be empty');
    }
    const verticesPerCuboid = 8;
    const indicesPerCuboid = 36;
    final vertices = Float32List(
      cuboids.length * verticesPerCuboid * VertexLayout.floatsPerVertex,
    );
    final indices = Uint16List(cuboids.length * indicesPerCuboid);

    for (var cuboidIndex = 0; cuboidIndex < cuboids.length; cuboidIndex++) {
      _writeCuboid(
        cuboids[cuboidIndex],
        vertices,
        cuboidIndex * verticesPerCuboid,
        indices,
        cuboidIndex * indicesPerCuboid,
      );
    }
    return PackedPrimitiveGeometry._(vertices, indices);
  }

  final Float32List _vertices;
  final Uint16List _indices;

  int get vertexCount => _vertices.length ~/ VertexLayout.floatsPerVertex;
  int get indexCount => _indices.length;

  Mesh createMesh(Material material) => Mesh()
    ..addSurface(
      PackedSurface(vertices: _vertices, indices: _indices, material: material),
    );
}

const _cuboidIndices = <int>[
  0, 2, 1, 0, 3, 2, // -Z
  4, 5, 6, 4, 6, 7, // +Z
  0, 4, 7, 0, 7, 3, // -X
  1, 2, 6, 1, 6, 5, // +X
  0, 1, 5, 0, 5, 4, // -Y
  3, 7, 6, 3, 6, 2, // +Y
];

void _writeCuboid(
  PackedCuboid cuboid,
  Float32List vertices,
  int firstVertex,
  Uint16List indices,
  int firstIndex,
) {
  _writeVertex(vertices, firstVertex, cuboid.minX, cuboid.minY, cuboid.minZ);
  _writeVertex(
    vertices,
    firstVertex + 1,
    cuboid.maxX,
    cuboid.minY,
    cuboid.minZ,
  );
  _writeVertex(
    vertices,
    firstVertex + 2,
    cuboid.maxX,
    cuboid.maxY,
    cuboid.minZ,
  );
  _writeVertex(
    vertices,
    firstVertex + 3,
    cuboid.minX,
    cuboid.maxY,
    cuboid.minZ,
  );
  _writeVertex(
    vertices,
    firstVertex + 4,
    cuboid.minX,
    cuboid.minY,
    cuboid.maxZ,
  );
  _writeVertex(
    vertices,
    firstVertex + 5,
    cuboid.maxX,
    cuboid.minY,
    cuboid.maxZ,
  );
  _writeVertex(
    vertices,
    firstVertex + 6,
    cuboid.maxX,
    cuboid.maxY,
    cuboid.maxZ,
  );
  _writeVertex(
    vertices,
    firstVertex + 7,
    cuboid.minX,
    cuboid.maxY,
    cuboid.maxZ,
  );

  for (var i = 0; i < _cuboidIndices.length; i++) {
    indices[firstIndex + i] = firstVertex + _cuboidIndices[i];
  }
}

void _writeVertex(
  Float32List vertices,
  int vertexIndex,
  double x,
  double y,
  double z,
) {
  final offset = vertexIndex * VertexLayout.floatsPerVertex;
  vertices[offset] = x;
  vertices[offset + 1] = y;
  vertices[offset + 2] = z;
  vertices[offset + 3] = x;
  vertices[offset + 4] = z;
  vertices[offset + 5] = 1;
  vertices[offset + 6] = 1;
  vertices[offset + 7] = 1;
  vertices[offset + 8] = 1;
  vertices[offset + 9] = 0;
  vertices[offset + 10] = 1;
  vertices[offset + 11] = 0;
  // Joint indices and weights (offsets 12..19) stay zero-initialized.
}
