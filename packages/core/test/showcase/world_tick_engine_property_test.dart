import 'dart:math';

import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('seeded edit/tick traces remain deterministic and bounded', () {
    for (final seed in [7, 41, 2026, 9001]) {
      final random = Random(seed);
      final first = VoxelWorld();
      final second = VoxelWorld();
      final firstEngine = WorldTickEngine(maxQueue: 12);
      final secondEngine = WorldTickEngine(maxQueue: 12);

      for (var step = 0; step < 160; step++) {
        final x = 8 + random.nextInt(24);
        final y = 1 + random.nextInt(8);
        final z = 8 + random.nextInt(24);
        final raw = _randomBlock(random);
        first.setBlock(x, y, z, raw);
        second.setBlock(x, y, z, raw);
        firstEngine.enqueueAround(x, y, z);
        secondEngine.enqueueAround(x, y, z);

        final budget = 1 + random.nextInt(48);
        final firstChanges = firstEngine.tick(first, budget);
        final secondChanges = secondEngine.tick(second, budget);

        expect(
          _changeSignature(firstChanges),
          _changeSignature(secondChanges),
          reason: 'seed $seed step $step',
        );
        expect(firstEngine.currentTick, secondEngine.currentTick);
        expect(firstEngine.pendingCount, secondEngine.pendingCount);
        expect(firstEngine.retryChunkCount, secondEngine.retryChunkCount);
        expect(firstEngine.droppedUpdates, secondEngine.droppedUpdates);
        expect(firstEngine.pendingCount, lessThanOrEqualTo(12));
        expect(firstEngine.retryChunkCount, greaterThanOrEqualTo(0));
      }
    }
  });
}

int _randomBlock(Random random) {
  switch (random.nextInt(6)) {
    case 0:
      return Blocks.air;
    case 1:
      return Blocks.stone;
    case 2:
      return Blocks.sand;
    case 3:
      return Blocks.gravel;
    case 4:
      return Blocks.pack(Blocks.water, random.nextInt(8));
    case 5:
      return Blocks.pack(Blocks.lava, random.nextInt(8));
    default:
      return Blocks.air;
  }
}

String _changeSignature(WorldChangeSet changes) => changes.changes
    .map(
      (change) =>
          '${change.x},${change.y},${change.z}:${change.oldRaw}>${change.newRaw}',
    )
    .join('|');
