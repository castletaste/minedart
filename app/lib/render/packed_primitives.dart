import 'dart:typed_data';

import 'package:minedart_core/minedart_core.dart';

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

  /// Packed vertices in the `VertexLayout` mesh ABI.
  Float32List get vertices => _vertices;
  Uint16List get indices => _indices;
}

/// Twelve thin edge cuboids around a unit block, offset by [padding].
PackedPrimitiveGeometry targetOutlineGeometry({
  double thickness = 0.018,
  double padding = 0.003,
}) {
  if (!thickness.isFinite || thickness <= 0 || thickness >= 0.25) {
    throw ArgumentError.value(
      thickness,
      'thickness',
      'must be finite and between 0 and 0.25',
    );
  }
  if (!padding.isFinite || padding < 0 || padding >= 0.25) {
    throw ArgumentError.value(
      padding,
      'padding',
      'must be finite and between 0 and 0.25',
    );
  }
  final half = thickness / 2;
  final min = -padding;
  final max = 1 + padding;
  return PackedPrimitiveGeometry.cuboids(<PackedCuboid>[
    for (final y in <double>[min, max])
      for (final z in <double>[min, max])
        PackedCuboid(
          minX: min - half,
          minY: y - half,
          minZ: z - half,
          maxX: max + half,
          maxY: y + half,
          maxZ: z + half,
        ),
    for (final x in <double>[min, max])
      for (final z in <double>[min, max])
        PackedCuboid(
          minX: x - half,
          minY: min - half,
          minZ: z - half,
          maxX: x + half,
          maxY: max + half,
          maxZ: z + half,
        ),
    for (final x in <double>[min, max])
      for (final y in <double>[min, max])
        PackedCuboid(
          minX: x - half,
          minY: y - half,
          minZ: min - half,
          maxX: x + half,
          maxY: y + half,
          maxZ: max + half,
        ),
  ]);
}

/// A unit cube centred on the origin, used for block particles.
final PackedPrimitiveGeometry unitCubeGeometry =
    PackedPrimitiveGeometry.cuboids(const <PackedCuboid>[
      PackedCuboid(
        minX: -0.5,
        minY: -0.5,
        minZ: -0.5,
        maxX: 0.5,
        maxY: 0.5,
        maxZ: 0.5,
      ),
    ]);

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
