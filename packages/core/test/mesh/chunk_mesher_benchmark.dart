import 'package:minedart_core/minedart_core.dart';

Object? benchmarkSink;

void main() {
  const warmupRuns = 300;
  const measuredRuns = 2000;
  const mesher = ChunkMesher();
  final world = VoxelWorld();
  WorldGenerator(0x5eed).generate(world);
  final snapshot = ChunkSnapshot.capture(world, 8, 2, 8);

  for (var i = 0; i < warmupRuns; i++) {
    benchmarkSink = mesher.mesh(snapshot);
  }

  final samples = List<int>.filled(measuredRuns, 0);
  var checksum = 0;
  for (var i = 0; i < measuredRuns; i++) {
    final stopwatch = Stopwatch()..start();
    final mesh = mesher.mesh(snapshot);
    stopwatch.stop();
    samples[i] = stopwatch.elapsedMicroseconds;
    checksum ^= mesh.opaqueIndices.length + mesh.translucentIndices.length;
    benchmarkSink = mesh;
  }
  samples.sort();
  final medianUs = samples[samples.length ~/ 2];
  final p99Index = ((samples.length * 99 + 99) ~/ 100) - 1;
  final p99Us = samples[p99Index];
  final mesh = benchmarkSink! as ChunkMeshData;

  print('chunk=8,2,8');
  print('opaque_vertices=${mesh.opaqueVertexCount}');
  print('translucent_vertices=${mesh.translucentVertexCount}');
  print('median_us=$medianUs');
  print('p99_us=$p99Us');
  print('best_us=${samples.first}');
  print('worst_us=${samples.last}');
  print('checksum=$checksum');
}
