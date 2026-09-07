/// Web pipeline: no isolates on dart2js/wasm, so meshing runs on the main
/// thread in small time-sliced batches scheduled between frames.
library;

import 'dart:async';

import 'package:minedart_core/minedart_core.dart';

import 'mesh_pipeline_base.dart';
import 'mesh_request_queue.dart';

/// Synchronous chunk processor used by the web pipeline.
typedef MeshChunkProcessor = ChunkMeshData Function(ChunkSnapshot snapshot);

/// Schedules one asynchronous drain and returns its cancellable timer.
typedef MeshDrainScheduler = Timer Function(void Function() callback);

class MeshPipeline implements MeshPipelineBase {
  MeshPipeline({
    int workers = 0,
    MeshPipelineActivity activity = MeshPipelineActivity.loading,
    MeshChunkProcessor? meshChunk,
    MeshDrainScheduler? scheduleDrain,
  }) : // Keep the public parameter name out of the private field spelling.
       // ignore: prefer_initializing_formals
       _activity = activity,
       _meshChunk = meshChunk ?? const ChunkMesher().mesh,
       _scheduleDrain = scheduleDrain ?? _scheduleWithTimer;

  // MeshJob.priority is a non-negative squared world-space distance. Encoding
  // it on one queue axis keeps the established ordering while MeshRequestQueue
  // supplies heap scheduling, coalescing, generations, and bounded retries.
  // The finite world stays well below this exact-integer web range.
  static const int _priorityScale = 256;
  static const int _maximumPriorityCoordinate = 94906249;

  final MeshRequestQueue _queue = MeshRequestQueue(maxRetries: 1);
  final Map<int, MeshJob> _jobs = <int, MeshJob>{};
  final StreamController<ChunkMeshData> _results =
      StreamController<ChunkMeshData>.broadcast();
  final MeshChunkProcessor _meshChunk;
  final MeshDrainScheduler _scheduleDrain;
  final Stopwatch _sliceStopwatch = Stopwatch();

  MeshPipelineActivity _activity;
  @override
  MainThreadMeshTimeObserver? onMainThreadMeshTime;
  Timer? _scheduledDrain;
  bool _draining = false;
  bool _disposed = false;

  /// The load signal that will be used for the next mesh slice.
  @override
  MeshPipelineActivity get activity => _activity;

  @override
  set activity(MeshPipelineActivity value) {
    if (!_disposed) _activity = value;
  }

  /// Current main-thread mesh budget in microseconds.
  int get budgetMicroseconds => _activity.budgetMicroseconds;

  @override
  Stream<ChunkMeshData> get results => _results.stream;

  @override
  int get pendingCount => _queue.pendingCount;

  @override
  Future<void> start() async {}

  @override
  void pauseDeadlines() {}

  @override
  void resumeDeadlines() {}

  @override
  void request(MeshJob job) {
    if (_disposed) return;

    // The caller has already captured this snapshot. This stage coalesces the
    // captured jobs; pre-capture coalescing belongs to the later integration.
    final accepted = _queue.request(
      chunkIndex: job.chunkIndex,
      chunkX: _priorityCoordinate(job.priority),
      chunkY: 0,
      chunkZ: 0,
      generation: job.snapshot.revision,
    );
    if (!accepted) return;

    _jobs[job.chunkIndex] = job;
    _schedule();
  }

  void _schedule() {
    if (_scheduledDrain != null || _draining || _queue.isEmpty || _disposed) {
      return;
    }
    _scheduledDrain = _scheduleDrain(_drain);
  }

  void _drain() {
    _scheduledDrain = null;
    if (_disposed || _draining) return;

    _draining = true;
    final budget = budgetMicroseconds;
    _sliceStopwatch
      ..reset()
      ..start();
    var attemptedJob = false;
    try {
      while (!_disposed &&
          !_queue.isEmpty &&
          (!attemptedJob || _sliceStopwatch.elapsedMicroseconds < budget)) {
        final request = _queue.takeNext();
        if (request == null) break;
        attemptedJob = true;
        _process(request);
      }
    } finally {
      _sliceStopwatch.stop();
      final elapsedMilliseconds = _sliceStopwatch.elapsedMicroseconds / 1000;
      _draining = false;
      _schedule();
      if (attemptedJob) {
        onMainThreadMeshTime?.call(elapsedMilliseconds);
      }
    }
  }

  void _process(MeshRequest request) {
    final job = _jobs[request.chunkIndex];
    if (job == null || job.snapshot.revision != request.generation) {
      _queue.complete(request);
      return;
    }

    ChunkMeshData data;
    try {
      data = _meshChunk(job.snapshot);
    } on Object catch (error, stackTrace) {
      final outcome = _queue.fail(request);
      if (outcome == MeshFailureOutcome.retryLimitReached) {
        _forgetJob(request.chunkIndex, request.generation);
        if (!_disposed && !_results.isClosed) {
          _results.addError(
            MeshPipelineFailure(
              chunkIndex: request.chunkIndex,
              generation: request.generation,
              kind: MeshPipelineFailureKind.meshing,
              cause: error,
            ),
            stackTrace,
          );
        }
      }
      return;
    }

    // A re-entrant newer request or disposal makes this result stale.
    if (!_queue.complete(request)) return;
    _forgetJob(request.chunkIndex, request.generation);
    if (!_disposed && !_results.isClosed) _results.add(data);
  }

  void _forgetJob(int chunkIndex, int generation) {
    final current = _jobs[chunkIndex];
    if (current?.snapshot.revision == generation) {
      _jobs.remove(chunkIndex);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduledDrain?.cancel();
    _scheduledDrain = null;
    _queue.dispose();
    _jobs.clear();
    onMainThreadMeshTime = null;
    _sliceStopwatch.stop();
    unawaited(_results.close());
  }

  @override
  Future<void> close() {
    dispose();
    return Future<void>.value();
  }

  static int _priorityCoordinate(double priority) {
    if (priority.isNaN || priority == double.infinity) {
      return _maximumPriorityCoordinate;
    }
    if (priority <= 0) return 0;

    final scaled = priority * _priorityScale;
    if (scaled >= _maximumPriorityCoordinate) {
      return _maximumPriorityCoordinate;
    }
    return scaled.round();
  }
}

Timer _scheduleWithTimer(void Function() callback) =>
    Timer(Duration.zero, callback);
