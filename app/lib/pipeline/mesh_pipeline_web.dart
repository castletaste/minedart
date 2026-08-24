/// Web pipeline: no isolates on dart2js/wasm, so meshing runs on the main
/// thread in small time-sliced batches scheduled between frames.
library;

import 'dart:async';

import 'package:minedart_core/minedart_core.dart';

import 'mesh_pipeline_base.dart';

class MeshPipeline implements MeshPipelineBase {
  MeshPipeline({int workers = 0});

  static const _budgetMs = 6;

  final _queue = <int, MeshJob>{};
  final _results = StreamController<ChunkMeshData>.broadcast();
  final _mesher = const ChunkMesher();
  bool _scheduled = false;
  bool _disposed = false;

  @override
  Stream<ChunkMeshData> get results => _results.stream;

  @override
  int get pendingCount => _queue.length;

  @override
  Future<void> start() async {}

  @override
  void request(MeshJob job) {
    if (_disposed) return;
    final queued = _queue[job.chunkIndex];
    if (queued == null || queued.snapshot.revision <= job.snapshot.revision) {
      _queue[job.chunkIndex] = job;
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _queue.isEmpty || _disposed) return;
    _scheduled = true;
    Timer.run(_drain);
  }

  void _drain() {
    _scheduled = false;
    if (_disposed) return;
    final sw = Stopwatch()..start();
    while (_queue.isNotEmpty && sw.elapsedMilliseconds < _budgetMs) {
      MeshJob? best;
      for (final j in _queue.values) {
        if (best == null || j.priority < best.priority) best = j;
      }
      final job = best!;
      _queue.remove(job.chunkIndex);
      ChunkMeshData data;
      try {
        data = _mesher.mesh(job.snapshot);
      } on Object {
        continue; // pathological chunk: skip, keep the queue alive
      }
      if (!_results.isClosed) _results.add(data);
    }
    _schedule();
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    _results.close();
  }
}
