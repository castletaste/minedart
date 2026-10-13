import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/pipeline/mesh_request_queue.dart';

void main() {
  for (final seed in [17, 43, 2026, 9001]) {
    test('queue matches a sorted-list model for seed $seed', () {
      final random = Random(seed);
      final queue = MeshRequestQueue(maxRetries: 1);
      final newest = <int, int>{};
      final pending = <int, (int generation, int retries)>{};
      final active = <int, MeshRequest>{};
      final attempts = <MeshRequest>[];
      var origin = 0;
      for (var step = 0; step < 1200; step++) {
        final reason = 'seed=$seed step=$step';
        switch (random.nextInt(6)) {
          case 0 || 1:
            final id = random.nextInt(12);
            final generation = (newest[id] ?? 0) + random.nextInt(3) - 1;
            final accepted =
                !newest.containsKey(id) || generation > newest[id]!;
            expect(
              queue.request(
                chunkIndex: id,
                chunkX: id,
                chunkY: 0,
                chunkZ: 0,
                generation: generation,
              ),
              accepted,
              reason: reason,
            );
            if (accepted) {
              newest[id] = generation;
              pending[id] = (generation, 0);
              active.remove(id);
            }
          case 2:
            final candidates = pending.keys.toList()
              ..sort((a, b) {
                final retry = pending[a]!.$2.compareTo(pending[b]!.$2);
                if (retry != 0) return retry;
                final distance = (a - origin).abs().compareTo(
                  (b - origin).abs(),
                );
                return distance != 0 ? distance : a.compareTo(b);
              });
            final request = queue.takeNext();
            expect(request?.chunkIndex, candidates.firstOrNull, reason: reason);
            if (request != null) {
              expect(
                (request.generation, request.retryCount),
                pending.remove(request.chunkIndex),
                reason: reason,
              );
              active[request.chunkIndex] = request;
              attempts.add(request);
            }
          case 3 || 4:
            if (attempts.isEmpty) break;
            final request = attempts[random.nextInt(attempts.length)];
            final current = identical(active[request.chunkIndex], request);
            expect(queue.isCurrent(request), current, reason: reason);
            if (random.nextBool()) {
              expect(queue.complete(request), current, reason: reason);
            } else {
              final expected = !current
                  ? MeshFailureOutcome.stale
                  : request.retryCount == 1
                  ? MeshFailureOutcome.retryLimitReached
                  : MeshFailureOutcome.retryScheduled;
              expect(queue.fail(request), expected, reason: reason);
              if (expected == MeshFailureOutcome.retryScheduled) {
                pending[request.chunkIndex] = (request.generation, 1);
              }
            }
            if (current) active.remove(request.chunkIndex);
          case 5:
            origin = random.nextInt(12);
            queue.setPriorityOrigin(x: origin, y: 0, z: 0);
            if (random.nextBool()) queue.compact();
        }
        expect(queue.pendingCount, pending.length, reason: reason);
        expect(
          queue.activeCount,
          pending.length + active.length,
          reason: reason,
        );
        expect(
          queue.heapNodeCount,
          lessThanOrEqualTo(pending.length * 2 + 32),
          reason: reason,
        );
        for (final entry in newest.entries) {
          expect(
            queue.isLatestGeneration(entry.key, entry.value),
            isTrue,
            reason: reason,
          );
        }
      }
      queue.dispose();
      for (final attempt in attempts) {
        expect(queue.complete(attempt), isFalse);
        expect(queue.fail(attempt), MeshFailureOutcome.disposed);
      }
      expect(queue.takeNext(), isNull);
      expect(queue.activeCount, 0);
    });
  }
}
