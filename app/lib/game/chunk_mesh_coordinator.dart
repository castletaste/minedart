import 'dart:async';

import 'package:minedart_core/minedart_core.dart';

import '../pipeline/mesh_pipeline.dart';
import '../pipeline/mesh_request_queue.dart';
import '../render/chunk_render_manager.dart';

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

  final Map<int, int> _generations = <int, int>{};
  final Set<int> _requested = <int>{};
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
  int _viewChunkX = -1;
  int _viewChunkZ = -1;
  int _renderDistanceChunks = 6;

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
    final nextDistance = renderDistanceChunks.clamp(2, WorldDims.worldChunksX);
    final cx = (playerX ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksX - 1,
    );
    final cz = (playerZ ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksZ - 1,
    );
    if (!force &&
        cx == _viewChunkX &&
        cz == _viewChunkZ &&
        nextDistance == _renderDistanceChunks) {
      return;
    }
    _viewChunkX = cx;
    _viewChunkZ = cz;
    _renderDistanceChunks = nextDistance;
    if (_deferSnapshotCapture) {
      _pendingCaptures.setPriorityOrigin(x: cx, y: 0, z: cz);
    }
    _chunks.updateVisibility(
      playerX: playerX,
      playerZ: playerZ,
      renderDistanceChunks: nextDistance,
    );
    _chunks.evictOutsideView(onEvicted: _requested.remove);

    final minX = (cx - nextDistance).clamp(0, WorldDims.worldChunksX - 1);
    final maxX = (cx + nextDistance).clamp(0, WorldDims.worldChunksX - 1);
    final minZ = (cz - nextDistance).clamp(0, WorldDims.worldChunksZ - 1);
    final maxZ = (cz + nextDistance).clamp(0, WorldDims.worldChunksZ - 1);
    for (var chunkZ = minZ; chunkZ <= maxZ; chunkZ++) {
      for (var chunkX = minX; chunkX <= maxX; chunkX++) {
        for (var chunkY = 0; chunkY < WorldDims.worldChunksY; chunkY++) {
          final index = VoxelWorld.chunkIndexOf(chunkX, chunkY, chunkZ);
          final chunk = _world.chunks[index];
          if (chunk.isEmpty || !_requested.add(index)) continue;
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
      _requested.add(index);
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
        if (!_isChunkInView(request.chunkX, request.chunkZ)) {
          _pendingCaptures.complete(request);
          _requested.remove(request.chunkIndex);
          continue;
        }
        try {
          _submitSnapshot(
            _world.chunks[request.chunkIndex],
            request.generation,
          );
        } on Object catch (error, stackTrace) {
          final outcome = _pendingCaptures.fail(request);
          if (outcome == MeshFailureOutcome.retryLimitReached) {
            _requested.remove(request.chunkIndex);
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
    final generation = (_generations[index] ?? 0) + 1;
    _generations[index] = generation;
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
      _submitSnapshot(chunk, generation);
    } on Object catch (error, stackTrace) {
      _requested.remove(index);
      _reportSubmissionFailure(
        chunkIndex: index,
        generation: generation,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _submitSnapshot(Chunk chunk, int generation) {
    if (_closed) return;
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
      ),
    );
  }

  void _applyResult(ChunkMeshData data) {
    if (_closed) return;
    if (!_chunks.isChunkInView(data.chunkIndex)) {
      _requested.remove(data.chunkIndex);
      return;
    }
    _applyStopwatch
      ..reset()
      ..start();
    try {
      _chunks.apply(data);
    } finally {
      _applyStopwatch.stop();
      if (!_closed) {
        _onMainThreadMeshTime(_applyStopwatch.elapsedMicroseconds / 1000);
      }
    }
  }

  void _handleFailure(Object error, StackTrace stackTrace) {
    if (_closed) return;
    if (error is MeshPipelineFailure &&
        _generations[error.chunkIndex] == error.generation) {
      _requested.remove(error.chunkIndex);
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
      (chunkX - _viewChunkX).abs() <= _renderDistanceChunks &&
      (chunkZ - _viewChunkZ).abs() <= _renderDistanceChunks;

  /// Stops callbacks immediately and awaits removal of the stream listener.
  ///
  /// Pipeline lifetime belongs to the session/runtime owner and is not closed
  /// here.
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    _pipeline.onMainThreadMeshTime = null;
    _pendingCaptures.dispose();
    final subscription = _resultSubscription;
    _resultSubscription = null;
    return _closing = subscription?.cancel() ?? Future<void>.value();
  }
}
