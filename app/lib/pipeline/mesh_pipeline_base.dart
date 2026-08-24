/// Platform-agnostic remesh pipeline contract.
library;

import 'package:minedart_core/minedart_core.dart';

class MeshJob {
  MeshJob({required this.snapshot, required this.priority});

  final ChunkSnapshot snapshot;
  final double priority;

  int get chunkIndex =>
      VoxelWorld.chunkIndexOf(snapshot.cx, snapshot.cy, snapshot.cz);
}

abstract interface class MeshPipelineBase {
  Stream<ChunkMeshData> get results;
  int get pendingCount;
  Future<void> start();
  void request(MeshJob job);
  void dispose();
}
