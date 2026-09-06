import 'dart:async';

import 'package:flame_3d/camera.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/game/chunk_mesh_coordinator.dart';
import 'package:minedart/pipeline/mesh_pipeline_base.dart';
import 'package:minedart/render/chunk_render_manager.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('ChunkMeshCoordinator', () {
    test('captures real snapshots with coordinator-owned generations', () {
      final world = VoxelWorld()..setBlock(0, 0, 0, Blocks.stone);
      final pipeline = _FakePipeline();
      final coordinator = _coordinator(world, pipeline)..start();
      addTearDown(coordinator.close);
      addTearDown(pipeline.close);

      coordinator.updateView(
        playerX: 1,
        playerY: 2,
        playerZ: 3,
        renderDistanceChunks: 2,
        force: true,
      );

      expect(pipeline.jobs, hasLength(1));
      expect(pipeline.jobs.single.snapshot.blockAt(0, 0, 0), Blocks.stone);
      expect(pipeline.jobs.single.snapshot.revision, 1);
      expect(pipeline.jobs.single.priority, 110);

      // This stays inside chunk zero, but must update later job priority.
      coordinator.updateView(
        playerX: 14,
        playerY: 2,
        playerZ: 3,
        renderDistanceChunks: 2,
      );
      coordinator.remeshDirty(<int>{0}, playerX: 14, playerY: 2, playerZ: 3);

      expect(pipeline.jobs, hasLength(2));
      expect(pipeline.jobs.last.snapshot.revision, 2);
      expect(pipeline.jobs.last.priority, 97);
    });

    test('coalesces deferred captures to the latest generation', () {
      final world = VoxelWorld()..setBlock(0, 0, 0, Blocks.stone);
      final pipeline = _FakePipeline();
      final coordinator = _coordinator(
        world,
        pipeline,
        deferSnapshotCapture: true,
      )..start();
      addTearDown(coordinator.close);
      addTearDown(pipeline.close);

      coordinator.updateView(
        playerX: 0,
        playerY: 0,
        playerZ: 0,
        renderDistanceChunks: 2,
        force: true,
      );
      coordinator
        ..remeshDirty(<int>{0}, playerX: 0, playerY: 0, playerZ: 0)
        ..remeshDirty(<int>{0}, playerX: 0, playerY: 0, playerZ: 0);

      expect(pipeline.jobs, isEmpty);
      expect(coordinator.pendingCount, 1);

      coordinator.drainPendingCaptures();

      expect(pipeline.jobs, hasLength(1));
      expect(pipeline.jobs.single.snapshot.revision, 3);
      expect(coordinator.pendingCount, 1);
    });

    test('only the latest typed failure releases request ownership', () {
      final world = VoxelWorld()..setBlock(0, 0, 0, Blocks.stone);
      final pipeline = _FakePipeline();
      final failures = <Object>[];
      final coordinator = _coordinator(
        world,
        pipeline,
        onFailure: (error, _) => failures.add(error),
      )..start();
      addTearDown(coordinator.close);
      addTearDown(pipeline.close);

      void update() => coordinator.updateView(
        playerX: 0,
        playerY: 0,
        playerZ: 0,
        renderDistanceChunks: 2,
        force: true,
      );

      update();
      expect(pipeline.jobs, hasLength(1));
      pipeline.emitFailure(
        const MeshPipelineFailure(
          chunkIndex: 0,
          generation: 0,
          kind: MeshPipelineFailureKind.meshing,
          cause: 'stale',
        ),
      );
      update();
      expect(pipeline.jobs, hasLength(1));

      pipeline.emitFailure(
        const MeshPipelineFailure(
          chunkIndex: 0,
          generation: 1,
          kind: MeshPipelineFailureKind.meshing,
          cause: 'terminal',
        ),
      );
      update();

      expect(failures, hasLength(2));
      expect(pipeline.jobs, hasLength(2));
      expect(pipeline.jobs.last.snapshot.revision, 2);
    });

    test('eviction releases ownership and returning requests a fresh mesh', () {
      const farChunk = 10;
      final world = VoxelWorld()
        ..setBlock(0, 0, 0, Blocks.stone)
        ..setBlock(
          farChunk * WorldDims.chunkSize,
          0,
          farChunk * WorldDims.chunkSize,
          Blocks.stone,
        );
      final pipeline = _FakePipeline();
      final manager = ChunkRenderManager(
        world: World3D(),
        material: Material.defaultMaterial,
      );
      final coordinator = _coordinator(world, pipeline, chunks: manager)
        ..start();
      addTearDown(coordinator.close);
      addTearDown(pipeline.close);

      coordinator.updateView(
        playerX: 0,
        playerY: 0,
        playerZ: 0,
        renderDistanceChunks: 2,
        force: true,
      );
      pipeline.emitSuccess(
        const ChunkMesher().mesh(pipeline.jobs.single.snapshot),
      );
      expect(manager.loadedChunkCount, 1);

      coordinator.updateView(
        playerX: farChunk * WorldDims.chunkSize.toDouble(),
        playerY: 0,
        playerZ: farChunk * WorldDims.chunkSize.toDouble(),
        renderDistanceChunks: 2,
      );
      expect(manager.loadedChunkCount, 0);
      expect(pipeline.jobs.last.chunkIndex, VoxelWorld.chunkIndexOf(10, 0, 10));

      coordinator.updateView(
        playerX: 0,
        playerY: 0,
        playerZ: 0,
        renderDistanceChunks: 2,
      );

      final originJobs = pipeline.jobs.where((job) => job.chunkIndex == 0);
      expect(originJobs, hasLength(2));
      expect(originJobs.last.snapshot.revision, 2);
    });

    test('bounds deferred submission failures and releases ownership', () {
      final world = VoxelWorld()..setBlock(0, 0, 0, Blocks.stone);
      final pipeline = _FakePipeline(failRequests: true);
      final failures = <Object>[];
      final coordinator = _coordinator(
        world,
        pipeline,
        deferSnapshotCapture: true,
        onFailure: (error, _) => failures.add(error),
      )..start();
      addTearDown(coordinator.close);
      addTearDown(pipeline.close);

      void update() => coordinator.updateView(
        playerX: 0,
        playerY: 0,
        playerZ: 0,
        renderDistanceChunks: 2,
        force: true,
      );

      update();
      coordinator
        ..drainPendingCaptures()
        ..drainPendingCaptures();

      expect(coordinator.pendingCount, 0);
      expect(failures, hasLength(1));
      final failure = failures.single as MeshPipelineFailure;
      expect(failure.chunkIndex, 0);
      expect(failure.generation, 1);
      expect(failure.kind, MeshPipelineFailureKind.transport);
      expect(failure.cause, isA<StateError>());

      update();
      expect(coordinator.pendingCount, 1);
    });

    test(
      'close is an immediate callback guard and awaitable barrier',
      () async {
        final world = VoxelWorld()..setBlock(0, 0, 0, Blocks.stone);
        final pipeline = _FakePipeline();
        final timings = <double>[];
        final failures = <Object>[];
        final manager = ChunkRenderManager(
          world: World3D(),
          material: Material.defaultMaterial,
        );
        final coordinator = _coordinator(
          world,
          pipeline,
          chunks: manager,
          onMainThreadMeshTime: timings.add,
          onFailure: (error, _) => failures.add(error),
        )..start();
        coordinator.updateView(
          playerX: 0,
          playerY: 0,
          playerZ: 0,
          renderDistanceChunks: 2,
          force: true,
        );
        final job = pipeline.jobs.single;

        final firstClose = coordinator.close();
        final secondClose = coordinator.close();
        expect(identical(firstClose, secondClose), isTrue);
        await firstClose;
        expect(pipeline.onMainThreadMeshTime, isNull);

        pipeline
          ..emitSuccess(const ChunkMesher().mesh(job.snapshot))
          ..emitFailure(
            const MeshPipelineFailure(
              chunkIndex: 0,
              generation: 1,
              kind: MeshPipelineFailureKind.transport,
              cause: 'late',
            ),
          );
        coordinator
          ..updateView(
            playerX: 0,
            playerY: 0,
            playerZ: 0,
            renderDistanceChunks: 2,
            force: true,
          )
          ..remeshDirty(<int>{0}, playerX: 0, playerY: 0, playerZ: 0)
          ..drainPendingCaptures();

        expect(manager.loadedChunkCount, 0);
        expect(timings, isEmpty);
        expect(failures, isEmpty);
        expect(pipeline.jobs, hasLength(1));
        await pipeline.close();
      },
    );
  });
}

ChunkMeshCoordinator _coordinator(
  VoxelWorld world,
  _FakePipeline pipeline, {
  ChunkRenderManager? chunks,
  bool deferSnapshotCapture = false,
  MainThreadMeshTimeObserver? onMainThreadMeshTime,
  MeshFailureObserver? onFailure,
}) => ChunkMeshCoordinator(
  world: world,
  pipeline: pipeline,
  chunks:
      chunks ??
      ChunkRenderManager(world: World3D(), material: Material.defaultMaterial),
  deferSnapshotCapture: deferSnapshotCapture,
  onMainThreadMeshTime: onMainThreadMeshTime ?? (_) {},
  onFailure: onFailure ?? (_, _) {},
);

final class _FakePipeline implements MeshPipelineBase {
  _FakePipeline({this.failRequests = false});

  final bool failRequests;
  final StreamController<ChunkMeshData> _results =
      StreamController<ChunkMeshData>.broadcast(sync: true);
  final List<MeshJob> jobs = <MeshJob>[];
  int _pendingCount = 0;

  @override
  MeshPipelineActivity activity = MeshPipelineActivity.loading;

  @override
  MainThreadMeshTimeObserver? onMainThreadMeshTime;

  @override
  int get pendingCount => _pendingCount;

  @override
  Stream<ChunkMeshData> get results => _results.stream;

  @override
  Future<void> start() async {}

  @override
  void request(MeshJob job) {
    if (failRequests) throw StateError('synthetic send failure');
    jobs.add(job);
    _pendingCount++;
  }

  void emitSuccess(ChunkMeshData data) {
    if (_pendingCount > 0) _pendingCount--;
    _results.add(data);
  }

  void emitFailure(MeshPipelineFailure failure) {
    if (_pendingCount > 0) _pendingCount--;
    _results.addError(failure, StackTrace.current);
  }

  @override
  void pauseDeadlines() {}

  @override
  void resumeDeadlines() {}

  @override
  Future<void> close() => _results.close();

  @override
  void dispose() {
    unawaited(close());
  }
}
