/// Isolate-based remesh pipeline built on the core ChunkSnapshot ABI.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:minedart_core/minedart_core.dart';

import 'mesh_pipeline_base.dart';
import 'mesh_request_queue.dart';

part 'mesh_worker_fleet.dart';
part 'mesh_worker_protocol.dart';

typedef MeshWorkerEntrypoint = void Function(Object? bootstrap);

typedef MeshWorkerSpawner =
    Future<Isolate> Function(
      MeshWorkerEntrypoint entrypoint,
      Object bootstrap, {
      required SendPort onError,
      required SendPort onExit,
      required String debugName,
    });

/// Narrow deterministic seams used only by native pipeline tests.
///
/// This type is intentionally absent from the platform facade.
final class MeshPipelineTestHooks {
  const MeshPipelineTestHooks({this.spawnWorker, this.afterHandshake});

  final MeshWorkerSpawner? spawnWorker;
  final Future<void> Function(int slotId)? afterHandshake;
}

enum _Lifecycle { created, starting, running, faulted, closing, closed }

class MeshPipeline implements MeshPipelineBase {
  MeshPipeline({
    this.workers = 3,
    this.jobDeadline = const Duration(seconds: 30),
    MeshPipelineActivity activity = MeshPipelineActivity.loading,
    MeshPipelineTestHooks? testHooks,
  }) : // Public API keeps the established `activity` parameter name.
       // ignore: prefer_initializing_formals
       _activity = activity {
    if (workers <= 0) {
      throw ArgumentError.value(workers, 'workers', 'must be positive');
    }
    if (jobDeadline <= Duration.zero) {
      throw ArgumentError.value(jobDeadline, 'jobDeadline', 'must be positive');
    }
    _workerFleet = _WorkerFleet(
      spawnWorker: testHooks?.spawnWorker ?? _defaultSpawnWorker,
      afterHandshake: testHooks?.afterHandshake,
      onMessage: _onWorkerMessage,
      onLoss: _onWorkerTransportLoss,
    );
  }

  static const int _maxJobRetries = 1;
  static const int _maxSlotRestarts = 1;
  static const int _priorityScale = 256;
  static const int _maximumPriorityCoordinate = 94906249;

  final int workers;
  final Duration jobDeadline;
  late final _WorkerFleet _workerFleet;
  final MeshRequestQueue _queue = MeshRequestQueue(maxRetries: _maxJobRetries);
  final StreamController<ChunkMeshData> _results =
      StreamController<ChunkMeshData>.broadcast();
  final Map<int, MeshJob> _latestJobs = <int, MeshJob>{};
  final Map<int, MeshJob> _queuedJobs = <int, MeshJob>{};
  final Map<int, MeshJob> _deferredJobs = <int, MeshJob>{};
  final Map<int, int> _latestGenerations = <int, int>{};
  final Map<int, _RunningJob> _runningByPhysicalId = <int, _RunningJob>{};
  final Map<int, int> _runningPhysicalIdByChunk = <int, int>{};

  MeshPipelineActivity _activity;
  _Lifecycle _lifecycle = _Lifecycle.created;
  Future<void>? _startFuture;
  Future<void>? _closeFuture;
  var _nextPhysicalJobId = 1;
  var _replacementSpawns = 0;
  bool _deadlinesPaused = false;

  @override
  MainThreadMeshTimeObserver? onMainThreadMeshTime;

  @override
  MeshPipelineActivity get activity => _activity;

  @override
  set activity(MeshPipelineActivity value) {
    if (_lifecycle != _Lifecycle.closing && _lifecycle != _Lifecycle.closed) {
      _activity = value;
    }
  }

  @override
  Stream<ChunkMeshData> get results => _results.stream;

  @override
  int get pendingCount =>
      _queue.pendingCount + _runningByPhysicalId.length + _deferredJobs.length;

  @override
  Future<void> start() {
    switch (_lifecycle) {
      case _Lifecycle.created:
        _lifecycle = _Lifecycle.starting;
        return _startFuture = _startWorkers();
      case _Lifecycle.starting:
        return _startFuture!;
      case _Lifecycle.running:
        return Future<void>.value();
      case _Lifecycle.faulted:
      case _Lifecycle.closing:
      case _Lifecycle.closed:
        return Future<void>.error(
          StateError('MeshPipeline cannot start after shutdown or failure'),
        );
    }
  }

  @override
  void request(MeshJob job) {
    if (_lifecycle == _Lifecycle.faulted) {
      _rejectWithoutWorkers(job);
      return;
    }
    if (_lifecycle != _Lifecycle.running) return;

    final generation = job.snapshot.revision;
    final latest = _latestGenerations[job.chunkIndex];
    if (latest != null && generation <= latest) return;
    _latestGenerations[job.chunkIndex] = generation;
    _latestJobs[job.chunkIndex] = job;

    if (_runningPhysicalIdByChunk.containsKey(job.chunkIndex)) {
      _deferredJobs[job.chunkIndex] = job;
    } else {
      _enqueue(job);
    }
    _pump();
  }

  @override
  void pauseDeadlines() {
    if (_deadlinesPaused) return;
    _deadlinesPaused = true;
    for (final running in _runningByPhysicalId.values) {
      running.pauseDeadline();
    }
  }

  @override
  void resumeDeadlines() {
    if (!_deadlinesPaused) return;
    _deadlinesPaused = false;
    for (final running in _runningByPhysicalId.values.toList()) {
      _armDeadline(running);
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  @override
  void dispose() {
    unawaited(close());
  }

  Future<void> _startWorkers() async {
    try {
      for (var slotId = 0; slotId < workers; slotId++) {
        if (_lifecycle != _Lifecycle.starting) {
          throw StateError('MeshPipeline startup was cancelled');
        }
        final slot = await _workerFleet.spawnAndRegister(
          slotId: slotId,
          restartCount: 0,
        );
        if (_lifecycle != _Lifecycle.starting) {
          _workerFleet.destroy(slot);
          throw StateError('MeshPipeline startup was cancelled');
        }
      }
      if (_workerFleet.liveCount != workers ||
          _workerFleet.slots.any((slot) => !slot.isHealthy)) {
        throw StateError('MeshPipeline lost a worker during startup');
      }
      _lifecycle = _Lifecycle.running;
      _pump();
    } catch (error, stackTrace) {
      if (_closeFuture == null) {
        _lifecycle = _Lifecycle.closing;
        await _finishClose();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _onWorkerMessage(_WorkerSlot slot, Object? message) {
    if (slot.destroyed) return;
    switch (message) {
      case _WorkerSuccess(
        :final physicalJobId,
        :final chunkIndex,
        :final generation,
        :final opaqueVertices,
        :final opaqueIndices,
        :final translucentVertices,
        :final translucentIndices,
      ):
        final running = _takeRunning(
          slot: slot,
          physicalJobId: physicalJobId,
          chunkIndex: chunkIndex,
          generation: generation,
        );
        if (running == null) {
          _onWorkerLoss(
            slot,
            kind: MeshPipelineFailureKind.transport,
            cause: StateError('Worker success did not match its active job'),
          );
          return;
        }
        _completeAttempt(
          running,
          ChunkMeshData(
            chunkIndex: chunkIndex,
            revision: generation,
            opaqueVertices: opaqueVertices.materialize().asFloat32List(),
            opaqueIndices: opaqueIndices.materialize().asUint16List(),
            translucentVertices: translucentVertices
                .materialize()
                .asFloat32List(),
            translucentIndices: translucentIndices.materialize().asUint16List(),
          ),
        );
      case _WorkerFailure(
        :final physicalJobId,
        :final chunkIndex,
        :final generation,
        :final error,
        :final stackTrace,
      ):
        final running = _takeRunning(
          slot: slot,
          physicalJobId: physicalJobId,
          chunkIndex: chunkIndex,
          generation: generation,
        );
        if (running == null) {
          _onWorkerLoss(
            slot,
            kind: MeshPipelineFailureKind.transport,
            cause: StateError('Worker failure did not match its active job'),
          );
          return;
        }
        _failAttempt(
          running,
          kind: MeshPipelineFailureKind.meshing,
          cause: StateError(error),
          stackTrace: StackTrace.fromString(stackTrace),
        );
      default:
        _onWorkerLoss(
          slot,
          kind: MeshPipelineFailureKind.transport,
          cause: StateError('Unexpected worker message: $message'),
        );
    }
  }

  void _pump() {
    if (_lifecycle != _Lifecycle.running) return;
    var sendFailed = false;
    for (final slot in _workerFleet.slots.toList()) {
      if (!slot.isHealthy || slot.activePhysicalJobId != null) continue;
      final request = _takeNextRunnable();
      if (request == null) break;
      final job = _queuedJobs[request.chunkIndex];
      if (job == null || job.snapshot.revision != request.generation) {
        _queue.complete(request);
        continue;
      }

      final physicalJobId = _nextPhysicalJobId++;
      final running = _RunningJob(
        physicalJobId: physicalJobId,
        request: request,
        job: job,
        slot: slot,
        deadlineRemaining: jobDeadline,
      );
      _runningByPhysicalId[physicalJobId] = running;
      _runningPhysicalIdByChunk[job.chunkIndex] = physicalJobId;
      slot.activePhysicalJobId = physicalJobId;
      _armDeadline(running);

      try {
        final buffers = job.snapshot.toBuffers();
        slot.commands!.send(
          _RunMesh(
            physicalJobId: physicalJobId,
            chunkIndex: job.chunkIndex,
            cx: buffers.cx,
            cy: buffers.cy,
            cz: buffers.cz,
            generation: buffers.revision,
            blocks: TransferableTypedData.fromList([
              buffers.blocks.asUint8List(),
            ]),
            skyHeight: TransferableTypedData.fromList([
              buffers.skyHeight.asUint8List(),
            ]),
          ),
        );
      } on Object catch (error, stackTrace) {
        final failed = _takeRunning(
          slot: slot,
          physicalJobId: physicalJobId,
          chunkIndex: job.chunkIndex,
          generation: job.snapshot.revision,
        );
        if (failed != null) {
          _failAttempt(
            failed,
            kind: MeshPipelineFailureKind.transport,
            cause: error,
            stackTrace: stackTrace,
          );
        }
        sendFailed = true;
      }
    }
    if (sendFailed) scheduleMicrotask(_pump);
  }

  MeshRequest? _takeNextRunnable() {
    while (!_queue.isEmpty) {
      final request = _queue.takeNext();
      if (request == null) return null;
      if (_runningPhysicalIdByChunk.containsKey(request.chunkIndex)) {
        throw StateError(
          'A running chunk must not also enter the native queue',
        );
      }
      return request;
    }
    return null;
  }

  void _completeAttempt(_RunningJob running, ChunkMeshData data) {
    final isCurrent = _isLatest(running.job);
    _queue.complete(running.request);
    _queuedJobs.remove(running.job.chunkIndex);
    if (isCurrent) {
      _latestJobs.remove(running.job.chunkIndex);
      if (_lifecycle == _Lifecycle.running && !_results.isClosed) {
        _results.add(data);
      }
    }
    _promoteDeferred(running.job.chunkIndex);
    _pump();
  }

  void _failAttempt(
    _RunningJob running, {
    required MeshPipelineFailureKind kind,
    required Object cause,
    StackTrace? stackTrace,
  }) {
    if (!_isLatest(running.job)) {
      _queue.complete(running.request);
      _queuedJobs.remove(running.job.chunkIndex);
      _promoteDeferred(running.job.chunkIndex);
      _pump();
      return;
    }

    final outcome = _queue.fail(running.request);
    switch (outcome) {
      case MeshFailureOutcome.retryScheduled:
        _pump();
      case MeshFailureOutcome.retryLimitReached:
        _queuedJobs.remove(running.job.chunkIndex);
        _latestJobs.remove(running.job.chunkIndex);
        _emitFailure(
          running.job,
          kind: kind,
          cause: cause,
          stackTrace: stackTrace,
        );
        _promoteDeferred(running.job.chunkIndex);
        _pump();
      case MeshFailureOutcome.stale:
      case MeshFailureOutcome.disposed:
        _promoteDeferred(running.job.chunkIndex);
        _pump();
    }
  }

  _RunningJob? _takeRunning({
    required _WorkerSlot slot,
    required int physicalJobId,
    required int chunkIndex,
    required int generation,
  }) {
    final running = _runningByPhysicalId[physicalJobId];
    if (running == null ||
        running.slot != slot ||
        running.job.chunkIndex != chunkIndex ||
        running.job.snapshot.revision != generation) {
      return null;
    }
    _runningByPhysicalId.remove(physicalJobId);
    _runningPhysicalIdByChunk.remove(chunkIndex);
    running.cancelDeadline();
    slot.activePhysicalJobId = null;
    return running;
  }

  void _onWorkerLoss(
    _WorkerSlot slot, {
    required MeshPipelineFailureKind kind,
    required Object cause,
  }) {
    if (!_workerFleet.lose(slot, cause)) return;
    final activeId = slot.activePhysicalJobId;
    if (activeId != null) {
      final running = _runningByPhysicalId.remove(activeId);
      if (running != null) {
        _runningPhysicalIdByChunk.remove(running.job.chunkIndex);
        running.cancelDeadline();
        _failAttempt(running, kind: kind, cause: cause);
      }
    }
    if (_lifecycle == _Lifecycle.running &&
        slot.restartCount < _maxSlotRestarts) {
      _scheduleReplacement(slot.id, slot.restartCount + 1);
    } else {
      _faultIfNoWorkers(cause);
    }
  }

  void _onWorkerTransportLoss(_WorkerSlot slot, Object cause) {
    _onWorkerLoss(
      slot,
      kind: MeshPipelineFailureKind.workerUnavailable,
      cause: cause,
    );
  }

  void _scheduleReplacement(int slotId, int restartCount) {
    _replacementSpawns++;
    unawaited(() async {
      try {
        final slot = await _workerFleet.spawnAndRegister(
          slotId: slotId,
          restartCount: restartCount,
        );
        if (_lifecycle == _Lifecycle.running) {
          _pump();
        } else {
          _workerFleet.destroy(slot);
        }
      } catch (error, stackTrace) {
        _faultIfNoWorkers(error, stackTrace);
      } finally {
        _replacementSpawns--;
        _faultIfNoWorkers(StateError('Worker restart budget exhausted'));
      }
    }());
  }

  void _faultIfNoWorkers(Object cause, [StackTrace? stackTrace]) {
    if (_lifecycle != _Lifecycle.running ||
        _workerFleet.liveCount > 0 ||
        _replacementSpawns > 0) {
      return;
    }
    _lifecycle = _Lifecycle.faulted;
    for (final job in _latestJobs.values.toList()) {
      _emitFailure(
        job,
        kind: MeshPipelineFailureKind.workerUnavailable,
        cause: cause,
        stackTrace: stackTrace,
      );
    }
    _clearWork();
  }

  void _rejectWithoutWorkers(MeshJob job) {
    final generation = job.snapshot.revision;
    final latest = _latestGenerations[job.chunkIndex];
    if (latest != null && generation <= latest) return;
    _latestGenerations[job.chunkIndex] = generation;
    _emitFailure(
      job,
      kind: MeshPipelineFailureKind.workerUnavailable,
      cause: StateError('No mesh workers remain'),
    );
  }

  void _emitFailure(
    MeshJob job, {
    required MeshPipelineFailureKind kind,
    required Object cause,
    StackTrace? stackTrace,
  }) {
    if (_results.isClosed || _lifecycle == _Lifecycle.closed) return;
    _results.addError(
      MeshPipelineFailure(
        chunkIndex: job.chunkIndex,
        generation: job.snapshot.revision,
        kind: kind,
        cause: cause,
      ),
      stackTrace ?? StackTrace.current,
    );
  }

  void _enqueue(MeshJob job) {
    final accepted = _queue.request(
      chunkIndex: job.chunkIndex,
      chunkX: _priorityCoordinate(job.priority),
      chunkY: 0,
      chunkZ: 0,
      generation: job.snapshot.revision,
    );
    if (accepted) _queuedJobs[job.chunkIndex] = job;
  }

  void _promoteDeferred(int chunkIndex) {
    final deferred = _deferredJobs.remove(chunkIndex);
    if (deferred != null && _lifecycle == _Lifecycle.running) {
      _enqueue(deferred);
    }
  }

  bool _isLatest(MeshJob job) =>
      _latestGenerations[job.chunkIndex] == job.snapshot.revision;

  void _armDeadline(_RunningJob running) {
    if (_deadlinesPaused || running.deadlineTimer != null) return;
    if (running.deadlineRemaining <= Duration.zero) {
      scheduleMicrotask(() => _onDeadline(running));
      return;
    }
    running.deadlineClock
      ..reset()
      ..start();
    running.deadlineTimer = Timer(
      running.deadlineRemaining,
      () => _onDeadline(running),
    );
  }

  void _onDeadline(_RunningJob running) {
    if (_runningByPhysicalId[running.physicalJobId] != running ||
        running.slot.activePhysicalJobId != running.physicalJobId) {
      return;
    }
    running.deadlineTimer = null;
    running.deadlineClock.stop();
    _onWorkerLoss(
      running.slot,
      kind: MeshPipelineFailureKind.deadlineExceeded,
      cause: TimeoutException(
        'Mesh job exceeded $jobDeadline of active foreground time',
        jobDeadline,
      ),
    );
  }

  Future<void> _close() async {
    if (_lifecycle == _Lifecycle.closed) return;
    _lifecycle = _Lifecycle.closing;
    _clearWork();
    await _workerFleet.close();
    if (_startFuture != null) {
      try {
        await _startFuture;
      } on Object {
        // Cancellation during startup is expected.
      }
    }
    _completeClose();
  }

  Future<void> _finishClose() async {
    _lifecycle = _Lifecycle.closing;
    await _workerFleet.close();
    _completeClose();
  }

  void _completeClose() {
    onMainThreadMeshTime = null;
    if (!_results.isClosed) unawaited(_results.close());
    _lifecycle = _Lifecycle.closed;
  }

  void _clearWork() {
    for (final running in _runningByPhysicalId.values) {
      running.cancelDeadline();
    }
    _runningByPhysicalId.clear();
    _runningPhysicalIdByChunk.clear();
    _queuedJobs.clear();
    _deferredJobs.clear();
    _latestJobs.clear();
    _queue.dispose();
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

final class _RunningJob {
  _RunningJob({
    required this.physicalJobId,
    required this.request,
    required this.job,
    required this.slot,
    required this.deadlineRemaining,
  });

  final int physicalJobId;
  final MeshRequest request;
  final MeshJob job;
  final _WorkerSlot slot;
  final Stopwatch deadlineClock = Stopwatch();
  Duration deadlineRemaining;
  Timer? deadlineTimer;

  void pauseDeadline() {
    final timer = deadlineTimer;
    if (timer == null) return;
    timer.cancel();
    deadlineTimer = null;
    deadlineClock.stop();
    deadlineRemaining -= deadlineClock.elapsed;
    deadlineClock.reset();
  }

  void cancelDeadline() {
    deadlineTimer?.cancel();
    deadlineTimer = null;
    deadlineClock
      ..stop()
      ..reset();
  }
}
