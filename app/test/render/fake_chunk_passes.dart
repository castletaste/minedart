import 'dart:typed_data';

import 'package:minedart/render/voxel_renderer.dart';

/// Engine-free [ChunkPassFactory] that records every pass it creates.
final class FakeChunkPasses implements ChunkPassFactory {
  final List<FakeChunkPass> created = [];

  /// Passes still in the scene.
  Iterable<FakeChunkPass> get live => created.where((pass) => !pass.removed);

  @override
  FakeChunkPass createPass({
    required ChunkPassKind kind,
    required int chunkX,
    required int chunkY,
    required int chunkZ,
    required Float32List vertices,
    required Uint16List indices,
  }) {
    final pass = FakeChunkPass(
      kind: kind,
      chunkX: chunkX,
      chunkY: chunkY,
      chunkZ: chunkZ,
      vertices: vertices,
      indices: indices,
    );
    created.add(pass);
    return pass;
  }
}

final class FakeChunkPass implements ChunkPassHandle {
  FakeChunkPass({
    required this.kind,
    required this.chunkX,
    required this.chunkY,
    required this.chunkZ,
    required this.vertices,
    required this.indices,
  });

  final ChunkPassKind kind;
  final int chunkX;
  final int chunkY;
  final int chunkZ;
  final Float32List vertices;
  final Uint16List indices;
  bool visible = true;
  bool removed = false;

  @override
  set distanceVisible(bool value) => visible = value;

  @override
  void removeFromScene() {
    if (removed) throw StateError('pass removed twice');
    removed = true;
  }
}
