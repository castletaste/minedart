import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/diagnostics/resource_budget.dart';
import 'package:minedart/render/chunk_render_manager.dart';
import 'package:minedart/render/voxel_renderer.dart';
import 'package:minedart_core/minedart_core.dart';

import 'fake_chunk_passes.dart';

void main() {
  group('ChunkRenderManager', () {
    test('ignores stale revisions and creates one pass per non-empty mesh', () {
      const cx = 2;
      const cy = 1;
      const cz = 3;
      const size = WorldDims.chunkSize;
      final voxelWorld = VoxelWorld()
        ..setBlock(cx * size, cy * size, cz * size, Blocks.stone)
        ..setBlock(cx * size + size - 1, cy * size, cz * size, Blocks.water);
      final data = const ChunkMesher().mesh(
        ChunkSnapshot.capture(voxelWorld, cx, cy, cz),
      );
      final passes = FakeChunkPasses();
      final manager = ChunkRenderManager(passes: passes);

      manager.apply(data);
      expect(
        passes.live.map((pass) => pass.kind),
        unorderedEquals(ChunkPassKind.values),
      );
      expect(manager.retainedComponentCount, 2);
      expect(manager.retainedMeshBytes, _meshBytes(data));

      manager.apply(_copyWithRevision(data, data.revision - 1));
      expect(passes.created, hasLength(2));
      expect(manager.retainedComponentCount, 2);
    });

    test('keeps empty passes component-free and removes empty chunks', () {
      const cx = 1;
      const cy = 0;
      const cz = 1;
      final voxelWorld = VoxelWorld()
        ..setBlock(
          cx * WorldDims.chunkSize,
          cy * WorldDims.chunkSize,
          cz * WorldDims.chunkSize,
          Blocks.water,
        );
      final data = const ChunkMesher().mesh(
        ChunkSnapshot.capture(voxelWorld, cx, cy, cz),
      );
      final passes = FakeChunkPasses();
      final manager = ChunkRenderManager(passes: passes);

      expect(data.opaqueIndices, isEmpty);
      expect(data.translucentIndices, isNotEmpty);
      manager.apply(data);

      expect(manager.loadedChunkCount, 1);
      expect(manager.retainedComponentCount, 1);
      expect(manager.retainedMeshBytes, _meshBytes(data));
      final translucent = passes.live.single;
      expect(translucent.kind, ChunkPassKind.translucent);
      expect(
        (translucent.chunkX, translucent.chunkY, translucent.chunkZ),
        (cx, cy, cz),
      );
      expect(identical(translucent.indices, data.translucentIndices), isTrue);

      manager.apply(
        ChunkMeshData(
          chunkIndex: data.chunkIndex,
          revision: data.revision + 1,
          opaqueVertices: data.opaqueVertices,
          opaqueIndices: data.opaqueIndices,
          translucentVertices: data.translucentVertices,
          translucentIndices: data.translucentIndices,
        ),
      );
      expect(manager.retainedComponentCount, 1);
      expect(manager.retainedMeshBytes, _meshBytes(data));
      expect(translucent.removed, isTrue);
      expect(passes.live, hasLength(1));

      manager.apply(
        ChunkMeshData(
          chunkIndex: data.chunkIndex,
          revision: data.revision + 2,
          opaqueVertices: Float32List(0),
          opaqueIndices: Uint16List(0),
          translucentVertices: Float32List(0),
          translucentIndices: Uint16List(0),
        ),
      );

      expect(manager.loadedChunkCount, 0);
      expect(manager.retainedComponentCount, 0);
      expect(manager.retainedMeshBytes, 0);
      expect(passes.live, isEmpty);
    });

    test('evicts far retained meshes and accepts a fresh mesh on return', () {
      const farChunk = 10;
      final voxelWorld = VoxelWorld()
        ..setBlock(0, 0, 0, Blocks.stone)
        ..setBlock(
          farChunk * WorldDims.chunkSize,
          0,
          farChunk * WorldDims.chunkSize,
          Blocks.stone,
        );
      final nearData = const ChunkMesher().mesh(
        ChunkSnapshot.capture(voxelWorld, 0, 0, 0),
      );
      final farData = const ChunkMesher().mesh(
        ChunkSnapshot.capture(voxelWorld, farChunk, 0, farChunk),
      );
      final passes = FakeChunkPasses();
      final manager = ChunkRenderManager(passes: passes)
        ..apply(nearData)
        ..apply(farData);

      expect(manager.loadedChunkCount, 2);
      expect(manager.retainedComponentCount, 2);
      final evicted = <int>[];
      manager.updateVisibility(playerX: 0, playerZ: 0, renderDistanceChunks: 2);
      expect(
        passes.live.where((pass) => !pass.visible).map((pass) => pass.chunkX),
        [farChunk],
      );
      expect(manager.visibleChunkCount, 1);
      expect(manager.evictOutsideView(onEvicted: evicted.add), 1);
      expect(evicted, <int>[farData.chunkIndex]);
      expect(passes.live.map((pass) => pass.chunkX), [0]);
      expect(manager.loadedChunkCount, 1);
      expect(manager.retainedComponentCount, 1);
      expect(manager.retainedMeshBytes, _meshBytes(nearData));

      manager.apply(_copyWithRevision(farData, farData.revision + 1));
      expect(manager.loadedChunkCount, 1);

      manager.updateVisibility(
        playerX: farChunk * WorldDims.chunkSize.toDouble(),
        playerZ: farChunk * WorldDims.chunkSize.toDouble(),
        renderDistanceChunks: 2,
      );
      expect(manager.evictOutsideView(onEvicted: evicted.add), 1);
      expect(evicted.last, nearData.chunkIndex);
      expect(manager.loadedChunkCount, 0);

      final refreshed = _copyWithRevision(farData, farData.revision + 2);
      manager.apply(refreshed);
      expect(manager.loadedChunkCount, 1);
      expect(manager.retainedComponentCount, 1);
      expect(manager.retainedMeshBytes, _meshBytes(refreshed));
    });

    test('retains a mesh over the budget and exposes the threshold', () {
      final voxelWorld = VoxelWorld()..setBlock(0, 0, 0, Blocks.stone);
      final data = const ChunkMesher().mesh(
        ChunkSnapshot.capture(voxelWorld, 0, 0, 0),
      );
      final manager = ChunkRenderManager(
        passes: FakeChunkPasses(),
        resourceBudget: ResourceBudget(
          maxRetainedMeshBytes: _meshBytes(data) - 1,
          maxRetainedComponents: 2,
        ),
      );

      manager.apply(data);

      expect(manager.loadedChunkCount, 1);
      expect(manager.retainedMeshBytes, _meshBytes(data));
      expect(manager.budgetStatus.exceeded, isTrue);
    });
  });
}

int _meshBytes(ChunkMeshData data) =>
    data.opaqueVertices.lengthInBytes +
    data.opaqueIndices.lengthInBytes +
    data.translucentVertices.lengthInBytes +
    data.translucentIndices.lengthInBytes;

ChunkMeshData _copyWithRevision(ChunkMeshData data, int revision) =>
    ChunkMeshData(
      chunkIndex: data.chunkIndex,
      revision: revision,
      opaqueVertices: data.opaqueVertices,
      opaqueIndices: data.opaqueIndices,
      translucentVertices: data.translucentVertices,
      translucentIndices: data.translucentIndices,
    );
