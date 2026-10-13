import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/game/chunk_view_planner.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  test('clamps the player chunk and render distance to world bounds', () {
    final plan = ChunkViewPlanner.plan(
      playerX: -100,
      playerZ: 10000,
      renderDistanceChunks: 1,
    );

    expect(plan.centerX, 0);
    expect(plan.centerZ, WorldDims.worldChunksZ - 1);
    expect(plan.renderDistanceChunks, 2);
    expect(plan.minX, 0);
    expect(plan.maxZ, WorldDims.worldChunksZ - 1);
  });

  test('same view ignores exact player movement inside one chunk', () {
    final first = ChunkViewPlanner.plan(
      playerX: 1,
      playerZ: 2,
      renderDistanceChunks: 6,
    );
    final second = ChunkViewPlanner.plan(
      playerX: 15,
      playerZ: 15,
      renderDistanceChunks: 6,
    );

    expect(first.sameView(second), isTrue);
    expect(first.containsChunk(first.centerX, first.centerZ), isTrue);
    expect(first.containsChunk(first.maxX + 1, first.centerZ), isFalse);
  });
}
