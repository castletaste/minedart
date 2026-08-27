@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/pipeline/mesh_pipeline_base.dart';
import 'package:minedart/pipeline/mesh_pipeline_io.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('MeshPipeline isolate pool', () {
    test('publishes a mesh for a requested chunk', () async {
      final pipeline = MeshPipeline(workers: 1);
      addTearDown(pipeline.dispose);
      await pipeline.start();

      final result = pipeline.results.first;
      pipeline.request(_job(index: 0, revision: 1));

      final mesh = await result.timeout(const Duration(seconds: 20));
      expect(mesh.chunkIndex, 0);
      expect(mesh.revision, 1);
      expect(pipeline.pendingCount, 0);
    });

    test('drops a superseded revision and keeps the newest one', () async {
      final pipeline = MeshPipeline(workers: 1);
      addTearDown(pipeline.dispose);
      await pipeline.start();

      final published = <int>[];
      final sub = pipeline.results.listen(
        (mesh) => published.add(mesh.revision),
      );
      addTearDown(sub.cancel);

      // Both revisions target the same chunk. Only the newest may be applied,
      // and the older one must not clear the newer attempt's bookkeeping.
      pipeline.request(_job(index: 0, revision: 1));
      pipeline.request(_job(index: 0, revision: 2));

      await _settle(pipeline);
      expect(published, <int>[2]);
      expect(pipeline.pendingCount, 0);
    });

    test('reports a failed chunk instead of publishing an empty mesh', () async {
      final pipeline = MeshPipeline(workers: 1);
      addTearDown(pipeline.dispose);
      await pipeline.start();

      final failures = <int>[];
      final published = <int>[];
      pipeline.onMeshFailure = (chunkIndex, _, _) => failures.add(chunkIndex);
      final sub = pipeline.results.listen(
        (mesh) => published.add(mesh.chunkIndex),
      );
      addTearDown(sub.cancel);

      // A block id outside the palette makes the mesher throw inside the
      // worker. An empty mesh here would delete visible terrain.
      pipeline.request(_job(index: 0, revision: 1, fill: 0xFFFF));

      await _settle(pipeline);
      expect(failures, <int>[0]);
      expect(published, isEmpty);
      expect(pipeline.pendingCount, 0);
    });

    test('keeps serving other chunks after a failure', () async {
      final pipeline = MeshPipeline(workers: 1);
      addTearDown(pipeline.dispose);
      await pipeline.start();

      final published = <int>[];
      final sub = pipeline.results.listen(
        (mesh) => published.add(mesh.chunkIndex),
      );
      addTearDown(sub.cancel);

      pipeline.request(_job(index: 0, revision: 1, fill: 0xFFFF));
      await _settle(pipeline);
      pipeline.request(_job(index: 1, revision: 1));
      await _settle(pipeline);

      expect(published, <int>[1]);
    });

    test('disposal is idempotent and stops accepting work', () async {
      final pipeline = MeshPipeline(workers: 1);
      await pipeline.start();

      pipeline.dispose();
      pipeline.dispose();
      pipeline.request(_job(index: 0, revision: 1));

      expect(pipeline.pendingCount, 0);
      expect(pipeline.onMeshFailure, isNull);
    });
  });
}

/// Waits until the pipeline drains, so assertions see a settled queue.
Future<void> _settle(MeshPipeline pipeline) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (pipeline.pendingCount > 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  // Let queued result events reach their listeners.
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

MeshJob _job({
  required int index,
  required int revision,
  double priority = 0,
  int fill = 0,
}) {
  final blocks = Uint16List(ChunkSnapshot.volume);
  if (fill != 0) blocks.fillRange(0, blocks.length, fill);
  return MeshJob(
    snapshot: ChunkSnapshot(
      cx: index,
      cy: 0,
      cz: 0,
      revision: revision,
      blocks: blocks,
      skyHeight: Uint8List(ChunkSnapshot.skyArea),
    ),
    priority: priority,
  );
}
