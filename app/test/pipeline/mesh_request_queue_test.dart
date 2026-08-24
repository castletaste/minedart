import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/pipeline/mesh_request_queue.dart';

void main() {
  group('MeshRequestQueue', () {
    test('takes nearest chunks first', () {
      final queue = MeshRequestQueue();
      _request(queue, index: 30, x: 3);
      _request(queue, index: 10, x: 1);
      _request(queue, index: 20, x: 2);

      final first = queue.takeNext()!;
      expect(first.chunkIndex, 10);
      expect(first.distanceSquared, 1);
      expect(queue.complete(first), isTrue);

      final second = queue.takeNext()!;
      expect(second.chunkIndex, 20);
      expect(queue.complete(second), isTrue);

      final third = queue.takeNext()!;
      expect(third.chunkIndex, 30);
      expect(queue.complete(third), isTrue);
      expect(queue.takeNext(), isNull);
    });

    test('breaks equal-distance ties by chunk index deterministically', () {
      final queue = MeshRequestQueue();
      _request(queue, index: 7, x: 1);
      _request(queue, index: 3, x: -1);
      _request(queue, index: 5, y: 1);

      final order = <int>[];
      while (!queue.isEmpty) {
        final request = queue.takeNext()!;
        order.add(request.chunkIndex);
        expect(queue.complete(request), isTrue);
      }

      expect(order, <int>[3, 5, 7]);
    });

    test('coalesces to the latest generation before capture', () {
      final queue = MeshRequestQueue(compactionFactor: 100);

      expect(_request(queue, index: 4, x: 2, generation: 1), isTrue);
      expect(_request(queue, index: 4, x: 2, generation: 3), isTrue);
      expect(_request(queue, index: 4, x: 2, generation: 2), isFalse);
      expect(queue.pendingCount, 1);
      expect(queue.heapNodeCount, 2);

      final request = queue.takeNext()!;
      expect(request.chunkIndex, 4);
      expect(request.generation, 3);
      expect(request.retryCount, 0);
      expect(queue.staleDiscardCount, 1);
      expect(queue.complete(request), isTrue);
    });

    test('rejects stale requests and stale in-flight results', () {
      final queue = MeshRequestQueue();
      _request(queue, index: 8, generation: 5);
      final oldRequest = queue.takeNext()!;

      expect(_request(queue, index: 8, generation: 4), isFalse);
      expect(_request(queue, index: 8, generation: 6), isTrue);
      expect(queue.isCurrent(oldRequest), isFalse);
      expect(queue.complete(oldRequest), isFalse);
      expect(queue.fail(oldRequest), MeshFailureOutcome.stale);

      final current = queue.takeNext()!;
      expect(current.generation, 6);
      expect(queue.isCurrent(current), isTrue);
      expect(queue.complete(current), isTrue);
      expect(queue.isLatestGeneration(8, 6), isTrue);

      // Completion does not erase the high-water mark.
      expect(_request(queue, index: 8, generation: 5), isFalse);
      expect(queue.isEmpty, isTrue);
    });

    test('rebuilds queued priorities when the origin changes chunk', () {
      final queue = MeshRequestQueue();
      _request(queue, index: 1, x: 1);
      _request(queue, index: 2, x: 9);

      expect(queue.setPriorityOrigin(x: 10, y: 0, z: 0), isTrue);
      expect(queue.priorityOrigin, (x: 10, y: 0, z: 0));
      expect(queue.originRebuildCount, 1);
      expect(queue.heapNodeCount, queue.pendingCount);
      expect(queue.staleNodeCount, 0);
      expect(queue.setPriorityOrigin(x: 10, y: 0, z: 0), isFalse);

      final nearest = queue.takeNext()!;
      expect(nearest.chunkIndex, 2);
      expect(nearest.distanceSquared, 1);
      expect(queue.complete(nearest), isTrue);
    });

    test('failed jobs yield to other work and stop at the retry cap', () {
      final queue = MeshRequestQueue(maxRetries: 2);
      _request(queue, index: 1, x: 0);
      _request(queue, index: 2, x: 10);

      final firstAttempt = queue.takeNext()!;
      expect(firstAttempt.chunkIndex, 1);
      expect(firstAttempt.retryCount, 0);
      expect(queue.fail(firstAttempt), MeshFailureOutcome.retryScheduled);

      // A first attempt outranks a retry even though it is farther away.
      final otherChunk = queue.takeNext()!;
      expect(otherChunk.chunkIndex, 2);
      expect(queue.complete(otherChunk), isTrue);

      final firstRetry = queue.takeNext()!;
      expect(firstRetry.chunkIndex, 1);
      expect(firstRetry.retryCount, 1);
      expect(queue.fail(firstRetry), MeshFailureOutcome.retryScheduled);

      final finalAttempt = queue.takeNext()!;
      expect(finalAttempt.retryCount, 2);
      expect(queue.fail(finalAttempt), MeshFailureOutcome.retryLimitReached);
      expect(queue.isEmpty, isTrue);
      expect(queue.activeCount, 0);

      // Retry exhaustion applies to the generation, not future edits.
      expect(_request(queue, index: 1, generation: 1), isFalse);
      expect(_request(queue, index: 1, generation: 2), isTrue);
      expect(queue.takeNext()!.retryCount, 0);
    });

    test('lazily removes stale nodes and bounds them with compaction', () {
      final lazyQueue = MeshRequestQueue(
        compactionFactor: 100,
        compactionSlack: 100,
      );
      _request(lazyQueue, index: 1, generation: 1);
      _request(lazyQueue, index: 1, generation: 2);
      expect(lazyQueue.staleNodeCount, 1);

      final latest = lazyQueue.takeNext()!;
      expect(latest.generation, 2);
      expect(lazyQueue.staleDiscardCount, 1);

      final boundedQueue = MeshRequestQueue(
        compactionFactor: 2,
        compactionSlack: 1,
      );
      for (var generation = 0; generation < 100; generation++) {
        _request(boundedQueue, index: 9, generation: generation);
      }

      expect(boundedQueue.pendingCount, 1);
      expect(boundedQueue.heapNodeCount, lessThanOrEqualTo(3));
      expect(boundedQueue.compactionCount, greaterThan(0));
      expect(boundedQueue.compact(), isTrue);
      expect(boundedQueue.heapNodeCount, 1);
      expect(boundedQueue.staleNodeCount, 0);
      expect(boundedQueue.takeNext()!.generation, 99);
    });

    test('empty and disposed queues are inert', () {
      final queue = MeshRequestQueue();
      expect(queue.isEmpty, isTrue);
      expect(queue.takeNext(), isNull);

      _request(queue, index: 1);
      final inFlight = queue.takeNext()!;
      expect(queue.isEmpty, isTrue);
      expect(queue.activeCount, 1);

      queue.dispose();
      queue.dispose();
      expect(queue.isDisposed, isTrue);
      expect(queue.pendingCount, 0);
      expect(queue.activeCount, 0);
      expect(queue.heapNodeCount, 0);
      expect(queue.takeNext(), isNull);
      expect(queue.complete(inFlight), isFalse);
      expect(queue.fail(inFlight), MeshFailureOutcome.disposed);
      expect(queue.isLatestGeneration(1, 1), isFalse);
      expect(_request(queue, index: 2), isFalse);
      expect(queue.setPriorityOrigin(x: 1, y: 1, z: 1), isFalse);
      expect(queue.compact(), isFalse);
    });
  });
}

bool _request(
  MeshRequestQueue queue, {
  required int index,
  int x = 0,
  int y = 0,
  int z = 0,
  int generation = 1,
}) => queue.request(
  chunkIndex: index,
  chunkX: x,
  chunkY: y,
  chunkZ: z,
  generation: generation,
);
