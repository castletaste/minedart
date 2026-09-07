import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/pipeline/mesh_pipeline_base.dart';
import 'package:minedart/pipeline/mesh_pipeline_io.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('MeshPipeline native isolates', () {
    test(
      'round-trips a real snapshot and mesh through transferable data',
      () async {
        final world = VoxelWorld()..setBlock(8, 8, 8, Blocks.stone);
        final snapshot = ChunkSnapshot.capture(world, 0, 0, 0);
        final expected = const ChunkMesher().mesh(snapshot);
        final pipeline = MeshPipeline(workers: 1);
        await pipeline.start();

        final resultFuture = pipeline.results.first;
        pipeline.request(MeshJob(snapshot: snapshot, priority: 0));
        final result = await resultFuture.timeout(const Duration(seconds: 2));

        expect(result.chunkIndex, expected.chunkIndex);
        expect(result.revision, expected.revision);
        expect(result.opaqueVertices, orderedEquals(expected.opaqueVertices));
        expect(result.opaqueIndices, orderedEquals(expected.opaqueIndices));
        expect(
          result.translucentVertices,
          orderedEquals(expected.translucentVertices),
        );
        expect(
          result.translucentIndices,
          orderedEquals(expected.translucentIndices),
        );
        expect(pipeline.pendingCount, 0);
        await pipeline.close();
      },
    );

    test(
      'runs one generation per chunk and retains only the latest queued one',
      () async {
        final world = VoxelWorld()..setBlock(8, 8, 8, Blocks.stone);
        final captured = ChunkSnapshot.capture(world, 0, 0, 0);
        final pipeline = MeshPipeline(workers: 2);
        final results = <ChunkMeshData>[];
        final subscription = pipeline.results.listen(results.add);
        await pipeline.start();

        pipeline.request(_job(captured, generation: 1));
        pipeline.request(_job(captured, generation: 2));
        pipeline.request(_job(captured, generation: 3));
        expect(pipeline.pendingCount, 2);

        await _waitUntil(() => results.isNotEmpty);
        expect(results, hasLength(1));
        expect(results.single.revision, 3);
        expect(pipeline.pendingCount, 0);
        await pipeline.close();
        await subscription.cancel();
      },
    );

    test(
      'deadline failure retries once, faults, and rejects with typed errors',
      () async {
        final world = VoxelWorld()..setBlock(8, 8, 8, Blocks.stone);
        final captured = ChunkSnapshot.capture(world, 0, 0, 0);
        final pipeline = MeshPipeline(
          workers: 1,
          jobDeadline: const Duration(microseconds: 1),
        );
        final failures = <MeshPipelineFailure>[];
        final subscription = pipeline.results.listen(
          (_) => fail('an expired job must not publish mesh success'),
          onError: (Object error) => failures.add(error as MeshPipelineFailure),
        );
        await pipeline.start();

        pipeline.request(_job(captured, generation: 1));
        await _waitUntil(() => failures.isNotEmpty);
        expect(failures.single.kind, MeshPipelineFailureKind.deadlineExceeded);
        expect(failures.single.generation, 1);
        expect(pipeline.pendingCount, 0);

        pipeline.request(_job(captured, generation: 2));
        await _waitUntil(() => failures.length == 2);
        expect(failures.last.kind, MeshPipelineFailureKind.workerUnavailable);
        expect(failures.last.generation, 2);
        expect(pipeline.pendingCount, 0);

        await pipeline.close();
        await subscription.cancel();
      },
    );

    test('paused deadlines do not charge suspended wall-clock time', () async {
      final world = VoxelWorld()..setBlock(8, 8, 8, Blocks.stone);
      final pipeline = MeshPipeline(
        workers: 1,
        jobDeadline: const Duration(milliseconds: 50),
      );
      await pipeline.start();
      pipeline.pauseDeadlines();

      final resultFuture = pipeline.results.first;
      pipeline.request(
        MeshJob(snapshot: ChunkSnapshot.capture(world, 0, 0, 0), priority: 0),
      );
      final result = await resultFuture.timeout(const Duration(seconds: 1));
      expect(result.opaqueIndices, isNotEmpty);

      pipeline.resumeDeadlines();
      await pipeline.close();
    });

    test('close waits for an unresolved real isolate spawn', () async {
      final spawned = Completer<void>();
      final releaseSpawnReturn = Completer<void>();

      Future<Isolate> delayedSpawner(
        MeshWorkerEntrypoint entrypoint,
        Object bootstrap, {
        required SendPort onError,
        required SendPort onExit,
        required String debugName,
      }) async {
        final isolate = await Isolate.spawn<Object?>(
          entrypoint,
          bootstrap,
          onError: onError,
          onExit: onExit,
          errorsAreFatal: true,
          debugName: debugName,
        );
        spawned.complete();
        await releaseSpawnReturn.future;
        return isolate;
      }

      final pipeline = MeshPipeline(
        workers: 1,
        testHooks: MeshPipelineTestHooks(spawnWorker: delayedSpawner),
      );
      final starting = pipeline.start();
      final startFailure = expectLater(starting, throwsStateError);
      await spawned.future.timeout(const Duration(seconds: 1));

      var closed = false;
      final closing = pipeline.close()..then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);

      releaseSpawnReturn.complete();
      await closing.timeout(const Duration(seconds: 1));
      await startFailure;
      expect(pipeline.pendingCount, 0);
    });

    test(
      'ready worker that exits before registration cannot complete startup',
      () async {
        Isolate? spawned;

        Future<Isolate> captureSpawner(
          MeshWorkerEntrypoint entrypoint,
          Object bootstrap, {
          required SendPort onError,
          required SendPort onExit,
          required String debugName,
        }) async {
          return spawned = await Isolate.spawn<Object?>(
            entrypoint,
            bootstrap,
            onError: onError,
            onExit: onExit,
            errorsAreFatal: true,
            debugName: debugName,
          );
        }

        final pipeline = MeshPipeline(
          workers: 1,
          testHooks: MeshPipelineTestHooks(
            spawnWorker: captureSpawner,
            afterHandshake: (_) async {
              spawned!.kill(priority: Isolate.immediate);
              await Future<void>.delayed(const Duration(milliseconds: 20));
            },
          ),
        );

        await expectLater(pipeline.start(), throwsStateError);
        expect(pipeline.pendingCount, 0);
        await pipeline.close();
      },
    );

    test('paused result listener cannot block resource close', () async {
      final pipeline = MeshPipeline(workers: 1);
      await pipeline.start();
      final subscription = pipeline.results.listen((_) {})..pause();

      await pipeline.close().timeout(const Duration(milliseconds: 100));
      expect(pipeline.pendingCount, 0);

      await subscription.cancel();
    });
  });
}

MeshJob _job(ChunkSnapshot source, {required int generation}) => MeshJob(
  snapshot: ChunkSnapshot(
    cx: source.cx,
    cy: source.cy,
    cz: source.cz,
    revision: generation,
    blocks: source.blocks,
    skyHeight: source.skyHeight,
  ),
  priority: 0,
);

Future<void> _waitUntil(bool Function() condition) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 2)) {
      throw TimeoutException('condition was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
