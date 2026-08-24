import 'package:minedart_core/minedart_core.dart';

void main() {
  const runs = 5;
  final timings = <int>[];
  var checksum = 0;
  late VoxelWorld sampledWorld;

  for (var run = 0; run < runs; run++) {
    final world = VoxelWorld();
    final stopwatch = Stopwatch()..start();
    WorldGenerator(0x5eed + run).generate(world);
    stopwatch.stop();
    timings.add(stopwatch.elapsedMicroseconds);
    checksum ^= _sampleChecksum(world);
    sampledWorld = world;
  }

  timings.sort();
  final medianUs = timings[runs ~/ 2];
  final bestUs = timings.first;
  print('worldgen_us=$timings');
  print('best_ms=${(bestUs / 1000).toStringAsFixed(3)}');
  print('median_ms=${(medianUs / 1000).toStringAsFixed(3)}');
  print('checksum=$checksum');
  print('block_counts=${_blockCounts(sampledWorld)}');
}

Map<int, int> _blockCounts(VoxelWorld world) {
  final counts = <int, int>{};
  for (final chunk in world.chunks) {
    for (final raw in chunk.blocks) {
      final block = Blocks.id(raw);
      counts[block] = (counts[block] ?? 0) + 1;
    }
  }
  return counts;
}

int _sampleChecksum(VoxelWorld world) {
  var result = 0;
  for (var i = 0; i < world.chunks.length; i += 17) {
    final chunk = world.chunks[i];
    result = (result * 31 + chunk.nonAirCount) & 0x7fffffff;
    result ^= chunk.blocks[(i * 97) & (ChunkIndex.volume - 1)];
  }
  return result;
}
