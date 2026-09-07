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

enum MeshPipelineFailureKind {
  meshing,
  workerUnavailable,
  deadlineExceeded,
  transport,
}

/// A terminal failure for the latest accepted generation of one chunk.
///
/// Successful values remain [ChunkMeshData] events on [MeshPipelineBase.results].
/// Failures are delivered as typed error events on the same stream.
final class MeshPipelineFailure implements Exception {
  const MeshPipelineFailure({
    required this.chunkIndex,
    required this.generation,
    required this.kind,
    required this.cause,
  });

  final int chunkIndex;
  final int generation;
  final MeshPipelineFailureKind kind;
  final Object cause;

  @override
  String toString() =>
      'MeshPipelineFailure(chunk: $chunkIndex, generation: $generation, '
      'kind: $kind, cause: $cause)';
}

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
  Future<void> start();
  void request(MeshJob job);

  /// Pauses watchdog time while the application is not active.
  void pauseDeadlines();

  /// Resumes watchdog time without charging suspended wall-clock duration.
  void resumeDeadlines();

  /// Cancels outstanding work and completes after owned resources are closed.
  Future<void> close();

  /// Compatibility trigger for owners that cannot await from synchronous code.
  void dispose();
}
