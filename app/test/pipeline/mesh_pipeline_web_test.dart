import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/pipeline/mesh_pipeline_base.dart';
import 'package:minedart/pipeline/mesh_pipeline_web.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('MeshPipeline web scheduler', () {
    test('selects allocation-stable budgets from the activity signal', () {
      expect(MeshPipelineActivity.interactive.budgetMicroseconds, 1000);
      expect(MeshPipelineActivity.moving.budgetMicroseconds, 3000);
      expect(MeshPipelineActivity.loading.budgetMicroseconds, 6000);
      expect(MeshPipelineActivity.idle.budgetMicroseconds, 6000);

      final pipeline = MeshPipeline();
      expect(pipeline.activity, MeshPipelineActivity.loading);
      expect(pipeline.budgetMicroseconds, 6000);

      pipeline.activity = MeshPipelineActivity.interactive;
      expect(pipeline.budgetMicroseconds, 1000);
      pipeline.dispose();

      pipeline.activity = MeshPipelineActivity.idle;
      expect(pipeline.activity, MeshPipelineActivity.interactive);
    });

    test(
      'uses the heap queue for nearest order, stable ties, and coalescing',
      () async {
        final scheduler = _ManualDrainScheduler();
        final attempts = <({int index, int revision})>[];
        final pipeline = MeshPipeline(
          scheduleDrain: scheduler.schedule,
          meshChunk: (snapshot) {
            attempts.add((
              index: snapshot.chunkIndex,
              revision: snapshot.revision,
            ));
            return _emptyMesh(snapshot);
          },
        );
        final results = pipeline.results.toList();

        pipeline.request(_job(index: 4, revision: 1, priority: 9));
        pipeline.request(_job(index: 4, revision: 3, priority: 16));
        pipeline.request(_job(index: 4, revision: 2, priority: 0));
        pipeline.request(_job(index: 7, priority: 1));
        pipeline.request(_job(index: 5, priority: 4));
        pipeline.request(_job(index: 3, priority: 4));

        expect(pipeline.pendingCount, 4);
        expect(scheduler.pendingCount, 1);
        expect(scheduler.maximumPendingCount, 1);

        scheduler.drain();
        expect(attempts, <({int index, int revision})>[
          (index: 7, revision: 1),
          (index: 3, revision: 1),
          (index: 5, revision: 1),
          (index: 4, revision: 3),
        ]);
        expect(pipeline.pendingCount, 0);

        pipeline.dispose();
        expect((await results).map((mesh) => mesh.chunkIndex), <int>[
          7,
          3,
          5,
          4,
        ]);
      },
    );

    test(
      'failed work yields, retries, and does not stop queue progress',
      () async {
        final scheduler = _ManualDrainScheduler();
        final attempts = <int>[];
        final failures = <int, int>{};
        final pipeline = MeshPipeline(
          scheduleDrain: scheduler.schedule,
          meshChunk: (snapshot) {
            attempts.add(snapshot.chunkIndex);
            final failureCount = failures[snapshot.chunkIndex] ?? 0;
            if (snapshot.chunkIndex == 1 && failureCount < 1) {
              failures[snapshot.chunkIndex] = failureCount + 1;
              throw StateError('synthetic mesh failure');
            }
            return _emptyMesh(snapshot);
          },
        );
        final results = pipeline.results.toList();

        pipeline.request(_job(index: 1, priority: 1));
        pipeline.request(_job(index: 2, priority: 100));
        scheduler.drain();

        expect(attempts, <int>[1, 2, 1]);
        expect(pipeline.pendingCount, 0);
        pipeline.dispose();
        expect((await results).map((mesh) => mesh.chunkIndex), <int>[2, 1]);
      },
    );

    test('reports a typed terminal error after one retry', () async {
      final scheduler = _ManualDrainScheduler();
      final pipeline = MeshPipeline(
        scheduleDrain: scheduler.schedule,
        meshChunk: (_) => throw StateError('synthetic terminal failure'),
      );
      final failure = Completer<MeshPipelineFailure>();
      final subscription = pipeline.results.listen(
        (_) => fail('a failed mesh must not emit an empty success'),
        onError: (Object error) =>
            failure.complete(error as MeshPipelineFailure),
      );

      pipeline.request(_job(index: 8));
      scheduler.drain();

      final error = await failure.future;
      expect(error.chunkIndex, 8);
      expect(error.generation, 1);
      expect(error.kind, MeshPipelineFailureKind.meshing);
      expect(error.cause, isA<StateError>());
      expect(pipeline.pendingCount, 0);
      await pipeline.close();
      await subscription.cancel();
    });

    test(
      'drops an in-flight result superseded by a newer generation',
      () async {
        final scheduler = _ManualDrainScheduler();
        final attempts = <int>[];
        late MeshPipeline pipeline;
        pipeline = MeshPipeline(
          scheduleDrain: scheduler.schedule,
          meshChunk: (snapshot) {
            attempts.add(snapshot.revision);
            if (snapshot.revision == 1) {
              pipeline.request(_job(index: 6, revision: 2, priority: 1));
              pipeline.request(_job(index: 6, revision: 0, priority: 0));
            }
            return _emptyMesh(snapshot);
          },
        );
        final results = pipeline.results.toList();

        pipeline.request(_job(index: 6, revision: 1, priority: 10));
        scheduler.drain();

        expect(attempts, <int>[1, 2]);
        expect(pipeline.pendingCount, 0);
        pipeline.dispose();
        expect((await results).map((mesh) => mesh.revision), <int>[2]);
      },
    );

    test('attempts one job even when it consumes the interactive budget', () {
      final scheduler = _ManualDrainScheduler();
      final attempts = <int>[];
      final pipeline = MeshPipeline(
        activity: MeshPipelineActivity.interactive,
        scheduleDrain: scheduler.schedule,
        meshChunk: (snapshot) {
          attempts.add(snapshot.chunkIndex);
          final work = Stopwatch()..start();
          while (work.elapsedMicroseconds < 2000) {}
          return _emptyMesh(snapshot);
        },
      );

      pipeline.request(_job(index: 1, priority: 1));
      pipeline.request(_job(index: 2, priority: 2));
      scheduler.runNext();

      expect(attempts, <int>[1]);
      expect(pipeline.pendingCount, 1);
      expect(scheduler.pendingCount, 1);
      expect(scheduler.maximumPendingCount, 1);

      scheduler.drain();
      pipeline.dispose();
    });

    test('reports one non-negative main-thread timing per non-empty slice', () {
      final scheduler = _ManualDrainScheduler();
      final timings = <double>[];
      final pipeline = MeshPipeline(
        scheduleDrain: scheduler.schedule,
        meshChunk: _emptyMesh,
      )..onMainThreadMeshTime = timings.add;

      pipeline.request(_job(index: 1));
      pipeline.request(_job(index: 2));
      scheduler.runNext();

      expect(timings, hasLength(1));
      expect(timings.single, isNonNegative);
      pipeline.dispose();
      expect(pipeline.onMainThreadMeshTime, isNull);
    });

    test('disposal cancels scheduled work and is re-entrant safe', () async {
      final scheduler = _ManualDrainScheduler();
      var attemptCount = 0;
      late MeshPipeline pipeline;
      pipeline = MeshPipeline(
        scheduleDrain: scheduler.schedule,
        meshChunk: (snapshot) {
          attemptCount++;
          pipeline.dispose();
          return _emptyMesh(snapshot);
        },
      );
      final results = pipeline.results.toList();

      pipeline.request(_job(index: 1));
      scheduler.runNext();
      pipeline.dispose();
      pipeline.request(_job(index: 2));
      scheduler.drain();

      expect(attemptCount, 1);
      expect(pipeline.pendingCount, 0);
      expect(scheduler.pendingCount, 0);
      expect(await results, isEmpty);

      final canceledScheduler = _ManualDrainScheduler();
      final canceledPipeline = MeshPipeline(
        scheduleDrain: canceledScheduler.schedule,
        meshChunk: (snapshot) {
          fail('a canceled drain must not process work');
        },
      );
      canceledPipeline.request(_job(index: 3));
      expect(canceledScheduler.pendingCount, 1);
      canceledPipeline.dispose();
      canceledScheduler.drain();
      expect(canceledPipeline.pendingCount, 0);
    });

    test('paused result subscriber cannot block close', () async {
      final pipeline = MeshPipeline();
      final subscription = pipeline.results.listen((_) {})..pause();

      await pipeline.close().timeout(const Duration(milliseconds: 100));

      await subscription.cancel();
    });
  });
}

MeshJob _job({required int index, int revision = 1, double priority = 0}) =>
    MeshJob(
      snapshot: ChunkSnapshot(
        cx: index,
        cy: 0,
        cz: 0,
        revision: revision,
        blocks: Uint16List(ChunkSnapshot.volume),
        skyHeight: Uint8List(ChunkSnapshot.skyArea),
      ),
      priority: priority,
    );

ChunkMeshData _emptyMesh(ChunkSnapshot snapshot) => ChunkMeshData(
  chunkIndex: snapshot.chunkIndex,
  revision: snapshot.revision,
  opaqueVertices: Float32List(0),
  opaqueIndices: Uint16List(0),
  translucentVertices: Float32List(0),
  translucentIndices: Uint16List(0),
);

final class _ManualDrainScheduler {
  final List<({void Function() callback, _ManualTimer timer})> _pending =
      <({void Function() callback, _ManualTimer timer})>[];
  int maximumPendingCount = 0;

  int get pendingCount => _pending.length;

  Timer schedule(void Function() callback) {
    final timer = _ManualTimer();
    _pending.add((callback: callback, timer: timer));
    if (_pending.length > maximumPendingCount) {
      maximumPendingCount = _pending.length;
    }
    return timer;
  }

  void runNext() {
    final scheduled = _pending.removeAt(0);
    if (scheduled.timer.fire()) scheduled.callback();
  }

  void drain() {
    while (_pending.isNotEmpty) {
      runNext();
    }
  }
}

final class _ManualTimer implements Timer {
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  bool fire() {
    if (!_active) return false;
    _active = false;
    _tick++;
    return true;
  }

  @override
  void cancel() {
    _active = false;
  }
}
