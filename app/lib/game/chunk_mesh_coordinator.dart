import 'dart:async';

import 'package:minedart_core/minedart_core.dart';

import '../pipeline/mesh_pipeline.dart';
import '../pipeline/mesh_request_queue.dart';
import '../render/chunk_render_manager.dart';
import 'chunk_view_planner.dart';

typedef MeshFailureObserver =
    void Function(Object error, StackTrace stackTrace);

/// Owns chunk-mesh scheduling between the voxel world, pipeline, and renderer.
///
/// The game supplies player position and activity. This coordinator owns the
/// per-chunk logical generation, request membership, deferred web captures,
/// result subscription, and renderer eviction bookkeeping.
final class ChunkMeshCoordinator {
  ChunkMeshCoordinator({
    required VoxelWorld world,
    required MeshPipelineBase pipeline,
    required ChunkRenderManager chunks,
    required bool deferSnapshotCapture,
    required MainThreadMeshTimeObserver onMainThreadMeshTime,
    required MeshFailureObserver onFailure,
  }) : // Public constructor arguments intentionally omit private underscores.
       // ignore: prefer_initializing_formals
       _world = world,
       // ignore: prefer_initializing_formals
       _pipeline = pipeline,
       // ignore: prefer_initializing_formals
       _chunks = chunks,
       // ignore: prefer_initializing_formals
       _deferSnapshotCapture = deferSnapshotCapture,
       // ignore: prefer_initializing_formals
       _onMainThreadMeshTime = onMainThreadMeshTime,
       // ignore: prefer_initializing_formals
       _onFailure = onFailure;

  final VoxelWorld _world;
  final MeshPipelineBase _pipeline;
  final ChunkRenderManager _chunks;
  final bool _deferSnapshotCapture;
  final MainThreadMeshTimeObserver _onMainThreadMeshTime;
  final MeshFailureObserver _onFailure;

  /// Keeps the generation watermark and the active ownership flag together.
  /// A completed request remains in the map so a late result cannot restart an
  /// old generation, while [requested] says whether the chunk is still owned
  /// by the current view.
  final Map<int, _ChunkRequestState> _requests =
      <int, _ChunkRequestState>{};
  final MeshRequestQueue _pendingCaptures = MeshRequestQueue(maxRetries: 1);
  final Stopwatch _captureStopwatch = Stopwatch();
  final Stopwatch _applyStopwatch = Stopwatch();

  StreamSubscription<ChunkMeshData>? _resultSubscription;
  Future<void>? _closing;
  bool _started = false;
  bool _closed = false;
  double _playerX = 0;
  double _playerY = 0;
  double _playerZ = 0;
  ChunkViewPlan? _viewPlan;

  int get pendingCount =>
      _pipeline.pendingCount + _pendingCaptures.pendingCount;

  void start() {
    if (_closed) throw StateError('Chunk mesh coordinator is closed');
    if (_started) return;
    _started = true;
    _pipeline.onMainThreadMeshTime = _onMainThreadMeshTime;
    _resultSubscription = _pipeline.results.listen(
      _applyResult,
      onError: _handleFailure,
    );
  }

  /// Updates the active chunk view and schedules previously unseen chunks.
  ///
  /// Exact player coordinates are retained even without a chunk transition so
  /// later edit remeshes and deferred captures use current distance priority.
  void updateView({
    required double playerX,
    required double playerY,
    required double playerZ,
    required int renderDistanceChunks,
    bool force = false,
  }) {
    if (_closed) return;
    _playerX = playerX;
    _playerY = playerY;
    _playerZ = playerZ;
    final plan = ChunkViewPlanner.plan(
      playerX: playerX,
      playerZ: playerZ,
      renderDistanceChunks: renderDistanceChunks,
    );
    if (!force && _viewPlan?.sameView(plan) == true) {
      return;
    }
    _viewPlan = plan;
    if (_deferSnapshotCapture) {
      _pendingCaptures.setPriorityOrigin(
        x: plan.centerX,
        y: 0,
        z: plan.centerZ,
      );
    }
    _chunks.updateVisibility(
      playerX: playerX,
      playerZ: playerZ,
      renderDistanceChunks: plan.renderDistanceChunks,
    );
    _chunks.evictOutsideView(onEvicted: _cancelChunk);
    // A request may still be in the mesh pipeline before its first component
    // exists, so renderer eviction alone cannot cancel it.
    for (final entry in _requests.entries.toList()) {
      if (!entry.value.requested) continue;
      final index = entry.key;
      final chunk = _world.chunks[index];
      if (!_isChunkInView(chunk.cx, chunk.cz)) _cancelChunk(index);
    }

    for (var chunkZ = plan.minZ; chunkZ <= plan.maxZ; chunkZ++) {
      for (var chunkX = plan.minX; chunkX <= plan.maxX; chunkX++) {
        for (var chunkY = 0; chunkY < WorldDims.worldChunksY; chunkY++) {
          final index = VoxelWorld.chunkIndexOf(chunkX, chunkY, chunkZ);
          final chunk = _world.chunks[index];
          if (chunk.isEmpty || !_claimChunk(index)) continue;
          _requestChunk(chunk);
        }
      }
    }
  }

  void remeshDirty(
    Set<int> dirtyChunks, {
    required double playerX,
    required double playerY,
    required double playerZ,
  }) {
    if (_closed) return;
    _playerX = playerX;
    _playerY = playerY;
    _playerZ = playerZ;
    for (final index in dirtyChunks) {
      _markChunkRequested(index);
      _requestChunk(_world.chunks[index]);
    }
  }

  /// Captures deferred snapshots within the pipeline's current web budget.
  void drainPendingCaptures() {
    if (_closed || !_deferSnapshotCapture || _pendingCaptures.isEmpty) return;
    final budget = _pipeline.activity.budgetMicroseconds;
    _captureStopwatch
      ..reset()
      ..start();
    var attempted = false;
    try {
      while (!_pendingCaptures.isEmpty &&
          (!attempted || _captureStopwatch.elapsedMicroseconds < budget)) {
        final request = _pendingCaptures.takeNext();
        if (request == null) break;
        attempted = true;
        final state = _requests[request.chunkIndex];
        if (state == null ||
            !state.requested ||
            state.generation != request.generation) {
          _pendingCaptures.complete(request);
          continue;
        }
        if (!_isChunkInView(request.chunkX, request.chunkZ)) {
          _pendingCaptures.complete(request);
          _cancelChunk(request.chunkIndex);
          continue;
        }
        try {
          _submitSnapshot(
            _world.chunks[request.chunkIndex],
            request.generation,
            token: state.token,
          );
        } on Object catch (error, stackTrace) {
          final outcome = _pendingCaptures.fail(request);
          if (outcome == MeshFailureOutcome.retryLimitReached) {
            _deactivateChunk(request.chunkIndex, request.generation);
            _reportSubmissionFailure(
              chunkIndex: request.chunkIndex,
              generation: request.generation,
              error: error,
              stackTrace: stackTrace,
            );
          }
          continue;
        }
        _pendingCaptures.complete(request);
      }
    } finally {
      _captureStopwatch.stop();
      if (attempted && !_closed) {
        _onMainThreadMeshTime(_captureStopwatch.elapsedMicroseconds / 1000);
      }
    }
  }

  void _requestChunk(Chunk chunk) {
    final index = VoxelWorld.chunkIndexOf(chunk.cx, chunk.cy, chunk.cz);
    final previous = _requests[index];
    final generation = (previous?.generation ?? 0) + 1;
    previous?.token?.cancel();
    final token = MeshCancellationToken();
    _requests[index] = _ChunkRequestState(
      generation: generation,
      token: token,
      requested: true,
    );
    if (_deferSnapshotCapture) {
      _pendingCaptures.request(
        chunkIndex: index,
        chunkX: chunk.cx,
        chunkY: chunk.cy,
        chunkZ: chunk.cz,
        generation: generation,
      );
      return;
    }
    try {
      _submitSnapshot(chunk, generation, token: token);
    } on Object catch (error, stackTrace) {
      _deactivateChunk(index, generation);
      _reportSubmissionFailure(
        chunkIndex: index,
        generation: generation,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _submitSnapshot(
    Chunk chunk,
    int generation, {
    MeshCancellationToken? token,
  }) {
    if (_closed) return;
    final index = VoxelWorld.chunkIndexOf(chunk.cx, chunk.cy, chunk.cz);
    final dx = chunk.cx * WorldDims.chunkSize + 8.0 - _playerX;
    final dy = chunk.cy * WorldDims.chunkSize + 8.0 - _playerY;
    final dz = chunk.cz * WorldDims.chunkSize + 8.0 - _playerZ;
    final captured = ChunkSnapshot.capture(
      _world,
      chunk.cx,
      chunk.cy,
      chunk.cz,
    );
    _pipeline.request(
      MeshJob(
        snapshot: ChunkSnapshot.fromBuffers(
          cx: captured.cx,
          cy: captured.cy,
          cz: captured.cz,
          revision: generation,
          blocks: captured.blocks,
          skyHeight: captured.skyHeight,
        ),
        priority: dx * dx + dy * dy + dz * dz,
        token: token ?? _requests[index]?.token,
      ),
    );
  }

  void _applyResult(ChunkMeshData data) {
    if (_closed) return;
    final state = _requests[data.chunkIndex];
    if (state?.generation != data.revision || state?.requested != true) {
      return;
    }
    if (!_chunks.isChunkInView(data.chunkIndex)) {
      _cancelChunk(data.chunkIndex);
      return;
    }
    _applyStopwatch
      ..reset()
      ..start();
    try {
      _chunks.apply(data);
      state!.token = null;
    } finally {
      _applyStopwatch.stop();
      if (!_closed) {
        _onMainThreadMeshTime(_applyStopwatch.elapsedMicroseconds / 1000);
      }
    }
  }

  void _cancelChunk(int chunkIndex) {
    _deactivateChunk(chunkIndex);
  }

  void _handleFailure(Object error, StackTrace stackTrace) {
    if (_closed) return;
    if (error is MeshPipelineFailure) {
      _deactivateChunk(error.chunkIndex, error.generation);
    }
    _onFailure(error, stackTrace);
  }

  void _reportSubmissionFailure({
    required int chunkIndex,
    required int generation,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (_closed) return;
    _onFailure(
      MeshPipelineFailure(
        chunkIndex: chunkIndex,
        generation: generation,
        kind: MeshPipelineFailureKind.transport,
        cause: error,
      ),
      stackTrace,
    );
  }

  bool _isChunkInView(int chunkX, int chunkZ) =>
      _viewPlan?.containsChunk(chunkX, chunkZ) ?? false;

  bool _claimChunk(int chunkIndex) {
    final state = _requests[chunkIndex];
    if (state?.requested == true) return false;
    _markChunkRequested(chunkIndex);
    return true;
  }

  void _markChunkRequested(int chunkIndex) {
    final state = _requests[chunkIndex];
    if (state == null) {
      _requests[chunkIndex] = _ChunkRequestState(
        generation: 0,
        requested: true,
      );
    } else {
      state.requested = true;
    }
  }

  void _deactivateChunk(int chunkIndex, [int? generation]) {
    final state = _requests[chunkIndex];
    if (state == null ||
        (generation != null && state.generation != generation)) {
      return;
    }
    state.token?.cancel();
    state.token = null;
    state.requested = false;
  }

  /// Stops callbacks immediately and awaits removal of the stream listener.
  ///
  /// Pipeline lifetime belongs to the session/runtime owner and is not closed
  /// here.
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    for (final state in _requests.values) {
      state.token?.cancel();
    }
    _requests.clear();
    _pipeline.onMainThreadMeshTime = null;
    _pendingCaptures.dispose();
    final subscription = _resultSubscription;
    _resultSubscription = null;
    return _closing = subscription?.cancel() ?? Future<void>.value();
  }
}

final class _ChunkRequestState {
  _ChunkRequestState({
    required this.generation,
    required this.requested,
    this.token,
  });

  final int generation;
  MeshCancellationToken? token;
  bool requested;
}
