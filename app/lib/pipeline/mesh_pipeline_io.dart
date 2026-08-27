/// Isolate-based remesh pipeline built on the core ChunkSnapshot ABI.
///
/// [MeshPipeline] owns a pool of long-lived worker isolates. Jobs carry
/// snapshot buffers (zero-copy via TransferableTypedData); results are
/// [ChunkMeshData]. Coalescing keeps at most one queued job per chunk;
/// consumers drop stale results by revision (ChunkRenderManager does).
///
/// Every chunk is tracked by its newest requested revision. A result is
/// published only when it still matches that revision, so an older in-flight
/// attempt can neither clear the newer attempt's bookkeeping nor overwrite it
/// with stale geometry.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:minedart_core/minedart_core.dart';

import 'mesh_pipeline_base.dart';

class MeshPipeline implements MeshPipelineBase {
  MeshPipeline({
    this.workers = 3,
    MeshPipelineActivity activity = MeshPipelineActivity.loading,
  }) : // Keep the public parameter name out of the private field spelling.
       // ignore: prefer_initializing_formals
       _activity = activity;

  final int workers;
  final _idle = <SendPort>[];
  final _isolates = <Isolate>[];
  final _receivePorts = <ReceivePort>[];
  final _queue = <int, MeshJob>{};
  final _inFlight = <int, int>{};

  /// Newest revision requested per chunk, kept until that revision resolves.
  final _latestRevisions = <int, int>{};
  final _results = StreamController<ChunkMeshData>.broadcast();
  MeshPipelineActivity _activity;
  bool _disposed = false;

  @override
  MeshPipelineActivity get activity => _activity;

  @override
  set activity(MeshPipelineActivity value) => _activity = value;

  @override
  MainThreadMeshTimeObserver? onMainThreadMeshTime;

  @override
  MeshFailureObserver? onMeshFailure;

  @override
  Stream<ChunkMeshData> get results => _results.stream;

  @override
  int get pendingCount => _queue.length + _inFlight.length;

  @override
  Future<void> start() async {
    for (var i = 0; i < workers; i++) {
      final ready = Completer<SendPort>();
      final rp = ReceivePort();
      _receivePorts.add(rp);
      rp.listen((msg) {
        if (msg is SendPort) {
          ready.complete(msg);
        } else if (msg is List) {
          _onResult(msg);
        }
      });
      final iso = await Isolate.spawn(
        meshWorkerMain,
        rp.sendPort,
        debugName: 'mesh-worker-$i',
      );
      _isolates.add(iso);
      _idle.add(await ready.future);
    }
    _pump();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final iso in _isolates) {
      iso.kill(priority: Isolate.immediate);
    }
    for (final port in _receivePorts) {
      port.close();
    }
    _receivePorts.clear();
    _isolates.clear();
    _idle.clear();
    _queue.clear();
    _inFlight.clear();
    _latestRevisions.clear();
    onMainThreadMeshTime = null;
    onMeshFailure = null;
    _results.close();
  }

  /// Queue a remesh; keeps the newest revision per chunk.
  @override
  void request(MeshJob job) {
    if (_disposed) return;
    final queued = _queue[job.chunkIndex];
    if (queued == null || queued.snapshot.revision <= job.snapshot.revision) {
      _queue[job.chunkIndex] = job;
    }
    final latest = _latestRevisions[job.chunkIndex];
    if (latest == null || latest < job.snapshot.revision) {
      _latestRevisions[job.chunkIndex] = job.snapshot.revision;
    }
    _pump();
  }

  void _pump() {
    if (_disposed) return;
    while (_idle.isNotEmpty && _queue.isNotEmpty) {
      MeshJob? best;
      for (final j in _queue.values) {
        if (best == null || j.priority < best.priority) best = j;
      }
      final job = best!;
      _queue.remove(job.chunkIndex);
      final port = _idle.removeLast();
      _inFlight[job.chunkIndex] = job.snapshot.revision;
      final b = job.snapshot.toBuffers();
      port.send([
        job.chunkIndex,
        b.cx,
        b.cy,
        b.cz,
        b.revision,
        TransferableTypedData.fromList([b.blocks.asUint8List()]),
        TransferableTypedData.fromList([b.skyHeight.asUint8List()]),
      ]);
    }
  }

  void _onResult(List msg) {
    if (_disposed) return;
    final chunkIndex = msg[0] as int;
    final revision = msg[1] as int;
    final worker = msg[6] as SendPort;
    final failure = msg[7];

    // Only the attempt that is still the newest owns this chunk's slots.
    // An older attempt returning late must not clear a newer one.
    if (_inFlight[chunkIndex] == revision) _inFlight.remove(chunkIndex);
    _idle.add(worker);

    final isLatest = _latestRevisions[chunkIndex] == revision;
    if (isLatest) _latestRevisions.remove(chunkIndex);

    if (failure != null) {
      // The snapshot moved into the worker and cannot be replayed here. Tell
      // the consumer so it can re-request from the authoritative world.
      if (isLatest) {
        onMeshFailure?.call(
          chunkIndex,
          StateError('mesh worker failed for chunk $chunkIndex: $failure'),
          StackTrace.current,
        );
      }
      _pump();
      return;
    }

    if (isLatest && !_results.isClosed) {
      _results.add(
        ChunkMeshData(
          chunkIndex: chunkIndex,
          revision: revision,
          opaqueVertices: (msg[2] as TransferableTypedData)
              .materialize()
              .asFloat32List(),
          opaqueIndices: (msg[3] as TransferableTypedData)
              .materialize()
              .asUint16List(),
          translucentVertices: (msg[4] as TransferableTypedData)
              .materialize()
              .asFloat32List(),
          translucentIndices: (msg[5] as TransferableTypedData)
              .materialize()
              .asUint16List(),
        ),
      );
    }
    _pump();
  }
}

/// Worker isolate entry point.
void meshWorkerMain(SendPort host) {
  final rp = ReceivePort();
  host.send(rp.sendPort);
  const mesher = ChunkMesher();
  rp.listen((msg) {
    final list = msg as List;
    final chunkIndex = list[0] as int;
    final snapshot = ChunkSnapshot.fromBuffers(
      cx: list[1] as int,
      cy: list[2] as int,
      cz: list[3] as int,
      revision: list[4] as int,
      blocks: list[5] as TransferableTypedData,
      skyHeight: list[6] as TransferableTypedData,
    );
    ChunkMeshData mesh;
    Object? failure;
    try {
      mesh = mesher.mesh(snapshot);
    } on Object catch (error) {
      // Keep the worker alive, but never publish an empty mesh as if it were
      // real geometry: that silently deletes a chunk the player can still see.
      // Report the failure and let the host decide whether to re-request.
      failure = error.toString();
      mesh = ChunkMeshData(
        chunkIndex: chunkIndex,
        revision: snapshot.revision,
        opaqueVertices: Float32List(0),
        opaqueIndices: Uint16List(0),
        translucentVertices: Float32List(0),
        translucentIndices: Uint16List(0),
      );
    }
    host.send([
      chunkIndex,
      snapshot.revision,
      _transfer(mesh.opaqueVertices),
      _transfer(mesh.opaqueIndices),
      _transfer(mesh.translucentVertices),
      _transfer(mesh.translucentIndices),
      rp.sendPort,
      failure,
    ]);
  });
}

TransferableTypedData _transfer(TypedData data) =>
    TransferableTypedData.fromList([
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    ]);
