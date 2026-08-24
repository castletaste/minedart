/// Isolate-based remesh pipeline built on the core ChunkSnapshot ABI.
///
/// [MeshPipeline] owns a pool of long-lived worker isolates. Jobs carry
/// snapshot buffers (zero-copy via TransferableTypedData); results are
/// [ChunkMeshData]. Coalescing keeps at most one queued job per chunk;
/// consumers drop stale results by revision (ChunkRenderManager does).
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:minedart_core/minedart_core.dart';

import 'mesh_pipeline_base.dart';

class MeshPipeline implements MeshPipelineBase {
  MeshPipeline({this.workers = 3});

  final int workers;
  final _idle = <SendPort>[];
  final _isolates = <Isolate>[];
  final _queue = <int, MeshJob>{};
  final _inFlight = <int, int>{};
  final _results = StreamController<ChunkMeshData>.broadcast();

  @override
  Stream<ChunkMeshData> get results => _results.stream;

  @override
  int get pendingCount => _queue.length + _inFlight.length;

  @override
  Future<void> start() async {
    for (var i = 0; i < workers; i++) {
      final ready = Completer<SendPort>();
      final rp = ReceivePort();
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
    for (final iso in _isolates) {
      iso.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _idle.clear();
    _queue.clear();
    _inFlight.clear();
    _results.close();
  }

  /// Queue a remesh; keeps the newest revision per chunk.
  @override
  void request(MeshJob job) {
    final queued = _queue[job.chunkIndex];
    if (queued == null || queued.snapshot.revision <= job.snapshot.revision) {
      _queue[job.chunkIndex] = job;
    }
    _pump();
  }

  void _pump() {
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
    final chunkIndex = msg[0] as int;
    final revision = msg[1] as int;
    final worker = msg[6] as SendPort;
    _inFlight.remove(chunkIndex);
    _idle.add(worker);
    if (!_results.isClosed) {
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
    try {
      mesh = mesher.mesh(snapshot);
    } on Object {
      // Pathological chunk (e.g. vertex overflow): fall back to an empty mesh
      // so the worker survives and the pipeline keeps flowing.
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
    ]);
  });
}

TransferableTypedData _transfer(TypedData data) =>
    TransferableTypedData.fromList([
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    ]);
