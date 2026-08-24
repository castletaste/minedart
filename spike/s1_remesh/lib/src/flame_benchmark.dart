import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';

import 'chunk_mesher.dart';
import 'stats.dart';

Object? benchmarkSink;

List<Vertex> buildFlameVertices(ChunkMeshData data) {
  return List<Vertex>.generate(data.vertexCount, (i) {
    final offset = i * floatsPerVertex;
    final packed = data.vertices;
    return Vertex(
      position: Vector3(packed[offset], packed[offset + 1], packed[offset + 2]),
      texCoord: Vector2(packed[offset + 3], packed[offset + 4]),
      color: const Color(0xffffffff),
      normal: Vector3(
        packed[offset + 9],
        packed[offset + 10],
        packed[offset + 11],
      ),
    );
  }, growable: false);
}

/// Public-API workaround for flame_3d 0.3.0. The superclass has no raw-buffer
/// constructor, so one dummy vertex is unavoidable. Every geometry getter used
/// by GraphicsDevice.bindGeometry is virtual and redirected to packed data.
final class PackedSurface extends Surface {
  PackedSurface(ChunkMeshData data, {super.material})
    : _vertices = data.vertices,
      _indices = data.indices,
      _positions = _extractPositions(data.vertices, data.vertexCount),
      _aabb = _calculatePackedAabb(data.vertices, data.vertexCount),
      super(
        vertices: [
          Vertex(
            position: Vector3.zero(),
            texCoord: Vector2.zero(),
            normal: Vector3(0, 1, 0),
          ),
        ],
        indices: const [],
        calculateNormals: false,
      );

  final Float32List _vertices;
  final Uint16List _indices;
  final Float32List _positions;
  final Aabb3 _aabb;

  @override
  int get verticesBytes => _vertices.lengthInBytes;
  @override
  int get vertexCount => _vertices.length ~/ floatsPerVertex;
  @override
  int get indicesBytes => _indices.lengthInBytes;
  @override
  int get indexCount => _indices.length;
  @override
  Float32List get positions => _positions;
  @override
  Uint16List get indices => _indices;
  @override
  Aabb3 get aabb => _aabb;

  @override
  bool get recreateResource =>
      resourceSizeInByes != _vertices.lengthInBytes + _indices.lengthInBytes;

  @override
  GpuBuffer createResource() {
    final size = _vertices.lengthInBytes + _indices.lengthInBytes;
    resourceSizeInByes = size;
    return GpuBackend.instance.createBuffer(
        storageMode: GpuStorageMode.hostVisible,
        sizeInBytes: size,
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

Float32List _extractPositions(Float32List vertices, int vertexCount) {
  final result = Float32List(vertexCount * 3);
  for (var i = 0; i < vertexCount; i++) {
    final source = i * floatsPerVertex;
    final target = i * 3;
    result[target] = vertices[source];
    result[target + 1] = vertices[source + 1];
    result[target + 2] = vertices[source + 2];
  }
  return result;
}

Aabb3 _calculatePackedAabb(Float32List vertices, int vertexCount) {
  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  var maxZ = double.negativeInfinity;
  for (var i = 0; i < vertexCount; i++) {
    final offset = i * floatsPerVertex;
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

Map<String, Object> runFlameBenchmark({
  int warmupIterations = 20,
  int measuredIterations = 100,
}) {
  final blocks = makeBenchmarkChunk();
  final fixedData = meshChunk(blocks);
  final fixedVertices = buildFlameVertices(fixedData);
  final frequency = Stopwatch().frequency;
  List<int> samples(Object? Function() operation) {
    for (var i = 0; i < warmupIterations; i++) {
      benchmarkSink = operation();
    }
    return List<int>.generate(
      measuredIterations,
      (_) => measureTicks(() => benchmarkSink = operation()),
      growable: false,
    );
  }

  final generation = samples(() => meshChunk(blocks));
  final vertices = samples(() => buildFlameVertices(fixedData));
  final surface = samples(
    () => Surface(vertices: fixedVertices, indices: fixedData.indices),
  );
  final surfaceNoNormalScan = samples(
    () => Surface(
      vertices: fixedVertices,
      indices: fixedData.indices,
      calculateNormals: false,
    ),
  );
  final packed = samples(() => PackedSurface(fixedData));
  final stockTotal = samples(() => _stockPipeline(blocks));
  final packedTotal = samples(() => _packedPipeline(blocks));
  Map<String, Object> stats(List<int> values) =>
      SampleStats(values, frequency).toJson();
  return {
    'runtime': 'flutter_test_jit_or_flutter_release_aot',
    'iterations': measuredIterations,
    'warmup_iterations': warmupIterations,
    'stopwatch_frequency': frequency,
    'chunk': {
      'dimensions': '16x16x16',
      'solid_blocks': blocks.where((value) => value != 0).length,
      'quads': fixedData.quadCount,
      'vertices': fixedData.vertexCount,
      'indices': fixedData.indexCount,
      'vertex_bytes': fixedData.vertices.lengthInBytes,
      'index_bytes': fixedData.indices.lengthInBytes,
      'checksum': meshChecksum(fixedData),
    },
    'stages': {
      'a_generate_typed_face_data': stats(generation),
      'b_construct_list_vertex': stats(vertices),
      'c_surface_constructor': stats(surface),
      'c_surface_constructor_calculate_normals_false': stats(
        surfaceNoNormalScan,
      ),
      'packed_surface_constructor': stats(packed),
      'stock_total_a_b_c': stats(stockTotal),
      'packed_total_a_hack': stats(packedTotal),
    },
  };
}

Surface _stockPipeline(Uint16List blocks) {
  final data = meshChunk(blocks);
  return Surface(vertices: buildFlameVertices(data), indices: data.indices);
}

PackedSurface _packedPipeline(Uint16List blocks) =>
    PackedSurface(meshChunk(blocks));

String flameBenchmarkJson({int warmup = 20, int iterations = 100}) =>
    const JsonEncoder.withIndent('  ').convert(
      runFlameBenchmark(
        warmupIterations: warmup,
        measuredIterations: iterations,
      ),
    );
