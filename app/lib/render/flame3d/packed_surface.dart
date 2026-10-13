import 'dart:typed_data';

import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:minedart_core/minedart_core.dart';

/// A [Surface] backed directly by the packed vertex layout produced by the
/// voxel mesher. This bypasses Flame's per-[Vertex] normalization path.
final class PackedSurface extends Surface {
  PackedSurface({
    required Float32List vertices,
    required Uint16List indices,
    required Material material,
    Aabb3? aabb,
  }) : _vertices = vertices,
       // A public `indices` argument keeps call sites aligned with Surface.
       // ignore: prefer_initializing_formals
       _indices = indices,
       // Known bounds let the hot path defer the separate XYZ allocation
       // until a caller actually asks for Surface.positions.
       _positions = aabb == null ? _extractPositions(vertices) : null,
       _aabb = aabb ?? _calculateAabb(vertices),
       super(
         vertices: [_dummyVertex],
         indices: const [],
         material: material,
         calculateNormals: false,
       );

  static final Vertex _dummyVertex = Vertex(
    position: Vector3.zero(),
    texCoord: Vector2.zero(),
    normal: Vector3(0, 1, 0),
  );

  final Float32List _vertices;
  final Uint16List _indices;
  Float32List? _positions;
  final Aabb3 _aabb;

  /// Whether the separate public XYZ view has been materialized.
  ///
  /// This is exposed for allocation telemetry and focused regression tests;
  /// rendering continues to use the original packed vertex buffer directly.
  bool get hasMaterializedPositions => _positions != null;

  @override
  int get verticesBytes => _vertices.lengthInBytes;

  @override
  int get vertexCount => _vertices.length ~/ VertexLayout.floatsPerVertex;

  @override
  int get indicesBytes => _indices.lengthInBytes;

  @override
  int get indexCount => _indices.length;

  @override
  Float32List get positions => _positions ??= _extractPositions(_vertices);

  @override
  Uint16List get indices => _indices;

  @override
  Aabb3 get aabb => _aabb;

  @override
  bool get recreateResource =>
      resourceSizeInByes != _vertices.lengthInBytes + _indices.lengthInBytes;

  @override
  GpuBuffer createResource() {
    final sizeInBytes = _vertices.lengthInBytes + _indices.lengthInBytes;
    resourceSizeInByes = sizeInBytes;
    return GpuBackend.instance.createBuffer(
        storageMode: GpuStorageMode.hostVisible,
        sizeInBytes: sizeInBytes,
      )
      ..write(
        _vertices.buffer.asByteData(
          _vertices.offsetInBytes,
          _vertices.lengthInBytes,
        ),
      )
      ..write(
        _indices.buffer.asByteData(
          _indices.offsetInBytes,
          _indices.lengthInBytes,
        ),
        destinationOffsetInBytes: _vertices.lengthInBytes,
      );
  }
}

Float32List _extractPositions(Float32List vertices) {
  final vertexCount = vertices.length ~/ VertexLayout.floatsPerVertex;
  final positions = Float32List(vertexCount * 3);
  for (var vertex = 0; vertex < vertexCount; vertex++) {
    final source = vertex * VertexLayout.floatsPerVertex;
    final target = vertex * 3;
    positions[target] = vertices[source];
    positions[target + 1] = vertices[source + 1];
    positions[target + 2] = vertices[source + 2];
  }
  return positions;
}

Aabb3 _calculateAabb(Float32List vertices) {
  if (vertices.isEmpty) {
    return Aabb3.minMax(Vector3.zero(), Vector3.zero());
  }

  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  var maxZ = double.negativeInfinity;
  for (
    var offset = 0;
    offset < vertices.length;
    offset += VertexLayout.floatsPerVertex
  ) {
    final x = vertices[offset];
    final y = vertices[offset + 1];
    final z = vertices[offset + 2];
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
  return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
}
