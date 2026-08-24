import 'package:minedart_core/minedart_core.dart';

void main() {
  const runs = 5;
  final timings = <int>[];
  final hashes = <int>[];
  var checksum = 0;

  for (var run = 0; run < runs; run++) {
    final world = VoxelWorld();
    final stopwatch = Stopwatch()..start();
    IslandsWorldGenerator(0x5eed + run).generate(world);
    stopwatch.stop();
    timings.add(stopwatch.elapsedMicroseconds);
    final hash = _fullBlockHash(world);
    hashes.add(hash);
    checksum ^= hash;
  }

  timings.sort();
  final medianUs = timings[runs ~/ 2];
  final bestUs = timings.first;
  print('islands_worldgen_us=$timings');
  print('best_ms=${(bestUs / 1000).toStringAsFixed(3)}');
  print('median_ms=${(medianUs / 1000).toStringAsFixed(3)}');
  print('hashes=$hashes');
  print('checksum=$checksum');
}

int _fullBlockHash(VoxelWorld world) {
  var result = 1;
  for (final chunk in world.chunks) {
    for (final block in chunk.blocks) {
      result = (result * 31 + block) & 0x7fffffff;
    }
  }
  return result;
}
