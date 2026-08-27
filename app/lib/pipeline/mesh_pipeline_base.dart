/// Platform-agnostic remesh pipeline contract.
library;

import 'package:minedart_core/minedart_core.dart';

/// Main-thread load signal used by the web implementation to select a slice
/// budget. Native isolate workers retain the value for API parity only.
enum MeshPipelineActivity {
  interactive(1000),
  moving(3000),
  loading(6000),
  idle(6000);

  const MeshPipelineActivity(this.budgetMicroseconds);

  final int budgetMicroseconds;
}

typedef MainThreadMeshTimeObserver = void Function(double milliseconds);

/// Reports a chunk the pipeline stopped trying to mesh.
///
/// A pipeline owns only the snapshot it was given. Snapshot buffers move
/// one-way into the worker on native, so a failed attempt cannot be replayed
/// from inside the pipeline. Consumers hold the authoritative voxel world and
/// therefore own recovery: they must release any bookkeeping that would
/// otherwise stop the chunk from ever being requested again.
typedef MeshFailureObserver =
    void Function(int chunkIndex, Object error, StackTrace stackTrace);

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
  MeshPipelineActivity get activity;
  set activity(MeshPipelineActivity value);
  MainThreadMeshTimeObserver? get onMainThreadMeshTime;
  set onMainThreadMeshTime(MainThreadMeshTimeObserver? observer);

  /// Invoked when a chunk is abandoned after its retries are exhausted.
  MeshFailureObserver? get onMeshFailure;
  set onMeshFailure(MeshFailureObserver? observer);
  Future<void> start();
  void request(MeshJob job);
  void dispose();
}
