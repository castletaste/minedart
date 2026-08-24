import 'dart:convert';
import 'dart:typed_data';

import 'chunk_mesher.dart';
import 'stats.dart';

Object? mirrorBenchmarkSink;

final class MirrorVector2 {
  MirrorVector2(double x, double y) : storage = Float32List(2) {
    storage[0] = x;
    storage[1] = y;
  }

  final Float32List storage;
  double get x => storage[0];
  double get y => storage[1];
}

final class MirrorVector3 {
  MirrorVector3(double x, double y, double z) : storage = Float32List(3) {
    storage[0] = x;
    storage[1] = y;
    storage[2] = z;
  }

  final Float32List storage;
  double get x => storage[0];
  double get y => storage[1];
  double get z => storage[2];
}

final class MirrorVector4 {
  MirrorVector4.zero() : storage = Float32List(4);

  final Float32List storage;
}

final class MirrorAabb {
  MirrorAabb.minMax(MirrorVector3 minimum, MirrorVector3 maximum)
    : min = MirrorVector3(minimum.x, minimum.y, minimum.z),
      max = MirrorVector3(maximum.x, maximum.y, maximum.z);

  final MirrorVector3 min;
  final MirrorVector3 max;
}

final class MirrorVertex {
  MirrorVertex({
    required MirrorVector3 position,
    required MirrorVector2 texCoord,
    required MirrorVector3 normal,
  }) : storage = Float32List.fromList([
         ...position.storage,
         ...texCoord.storage,
         ...[1.0, 1.0, 1.0, 1.0],
         ...normal.storage,
         ...MirrorVector4.zero().storage,
         ...MirrorVector4.zero().storage,
       ]),
       position = (position.x, position.y, position.z),
       texCoord = (texCoord.x, texCoord.y),
       normal = (normal.x, normal.y, normal.z);

  final (double, double, double) position;
  final (double, double) texCoord;
  final (double, double, double)? normal;
  final Float32List storage;
}

List<MirrorVertex> buildMirrorVertices(ChunkMeshData data) =>
    List<MirrorVertex>.generate(data.vertexCount, (i) {
      final offset = i * floatsPerVertex;
      final packed = data.vertices;
      return MirrorVertex(
        position: MirrorVector3(
          packed[offset],
          packed[offset + 1],
          packed[offset + 2],
        ),
        texCoord: MirrorVector2(packed[offset + 3], packed[offset + 4]),
        normal: MirrorVector3(
          packed[offset + 9],
          packed[offset + 10],
          packed[offset + 11],
        ),
      );
    }, growable: false);

/// Mechanical CPU mirror of Surface(..., calculateNormals: false): same
/// fold/addAll, typed copies, positions extraction and AABB scan. It excludes
/// dart:ui/GPU types so `dart compile exe` can compile it.
final class MirrorSurface {
  MirrorSurface({
    required List<MirrorVertex> vertices,
    required List<int> indices,
  }) {
    if (vertices.any((vertex) => vertex.normal == null)) {
      throw StateError('normal calculation is outside this CPU mirror');
    }
    packedVertices = Float32List.fromList(
      vertices.fold([], (previous, vertex) => previous..addAll(vertex.storage)),
    );
    positions = Float32List(vertices.length * 3);
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;
    for (var i = 0; i < vertices.length; i++) {
      final p = vertices[i].position;
      positions[i * 3] = p.$1;
      positions[i * 3 + 1] = p.$2;
      positions[i * 3 + 2] = p.$3;
      if (p.$1 < minX) minX = p.$1;
      if (p.$2 < minY) minY = p.$2;
      if (p.$3 < minZ) minZ = p.$3;
      if (p.$1 > maxX) maxX = p.$1;
      if (p.$2 > maxY) maxY = p.$2;
      if (p.$3 > maxZ) maxZ = p.$3;
    }
    this.indices = Uint16List.fromList(indices);
    aabb = MirrorAabb.minMax(
      MirrorVector3(minX, minY, minZ),
      MirrorVector3(maxX, maxY, maxZ),
    );
  }

  late final Float32List packedVertices;
  late final Float32List positions;
  late final Uint16List indices;
  late final MirrorAabb aabb;
}

/// CPU mirror of the useful work in PackedSurface: keep the already packed
/// buffers, derive the public positions array, and compute bounds.
final class MirrorPackedSurface {
  MirrorPackedSurface(ChunkMeshData data)
    : packedVertices = data.vertices,
      indices = data.indices {
    positions = Float32List(data.vertexCount * 3);
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;
    for (var i = 0; i < data.vertexCount; i++) {
      final source = i * floatsPerVertex;
      final target = i * 3;
      final x = data.vertices[source];
      final y = data.vertices[source + 1];
      final z = data.vertices[source + 2];
      positions[target] = x;
      positions[target + 1] = y;
      positions[target + 2] = z;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    aabb = MirrorAabb.minMax(
      MirrorVector3(minX, minY, minZ),
      MirrorVector3(maxX, maxY, maxZ),
    );
  }

  final Float32List packedVertices;
  final Uint16List indices;
  late final Float32List positions;
  late final MirrorAabb aabb;
}

Map<String, Object> runMirrorBenchmark({
  int warmupIterations = 20,
  int measuredIterations = 100,
}) {
  final blocks = makeBenchmarkChunk();
  final fixedData = meshChunk(blocks);
  final fixedVertices = buildMirrorVertices(fixedData);
  final frequency = Stopwatch().frequency;
  List<int> samples(Object? Function() operation) {
    for (var i = 0; i < warmupIterations; i++) {
      mirrorBenchmarkSink = operation();
    }
    return List<int>.generate(
      measuredIterations,
      (_) => measureTicks(() => mirrorBenchmarkSink = operation()),
      growable: false,
    );
  }

  final generation = samples(() => meshChunk(blocks));
  final vertices = samples(() => buildMirrorVertices(fixedData));
  final surface = samples(
    () => MirrorSurface(vertices: fixedVertices, indices: fixedData.indices),
  );
  final packed = samples(() => MirrorPackedSurface(fixedData));
  final stockTotal = samples(() => _stockPipeline(blocks));
  final packedTotal = samples(() => _packedPipeline(blocks));
  Map<String, Object> stats(List<int> values) =>
      SampleStats(values, frequency).toJson();
  return {
    'runtime': 'dart_compile_exe_aot_cpu_mirror',
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
      'b_construct_mirror_vertices': stats(vertices),
      'c_mirror_surface_constructor': stats(surface),
      'packed_surface_cpu_work': stats(packed),
      'stock_total_a_b_c': stats(stockTotal),
      'packed_total_a_hack': stats(packedTotal),
    },
  };
}

MirrorSurface _stockPipeline(Uint16List blocks) {
  final data = meshChunk(blocks);
  return MirrorSurface(
    vertices: buildMirrorVertices(data),
    indices: data.indices,
  );
}

MirrorPackedSurface _packedPipeline(Uint16List blocks) =>
    MirrorPackedSurface(meshChunk(blocks));

String mirrorBenchmarkJson({int warmup = 20, int iterations = 100}) =>
    const JsonEncoder.withIndent('  ').convert(
      runMirrorBenchmark(
        warmupIterations: warmup,
        measuredIterations: iterations,
      ),
    );
