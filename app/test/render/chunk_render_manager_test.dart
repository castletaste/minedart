import 'dart:typed_data';

import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/render/chunk_render_manager.dart';
import 'package:minedart/render/packed_surface.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('ChunkRenderManager', () {
    test(
      'uses lazy known chunk bounds for opaque and translucent surfaces',
      () {
        const cx = 2;
        const cy = 1;
        const cz = 3;
        const size = WorldDims.chunkSize;
        final originX = cx * size;
        final originY = cy * size;
        final originZ = cz * size;
        final voxelWorld = VoxelWorld()
          ..setBlock(originX, originY, originZ, Blocks.stone)
          ..setBlock(
            originX + size - 1,
            originY + size - 1,
            originZ + size - 1,
            Blocks.flowerDandelion,
          )
          ..setBlock(
            originX + size - 1,
            originY + size - 1,
            originZ,
            Blocks.water,
          )
          ..setBlock(originX, originY, originZ + size - 1, Blocks.lava);
        final data = const ChunkMesher().mesh(
          ChunkSnapshot.capture(voxelWorld, cx, cy, cz),
        );
        final renderWorld = World3D();
        final manager = ChunkRenderManager(
          world: renderWorld,
          material: Material.defaultMaterial,
        );

        expect(data.opaqueIndices, isNotEmpty);
        expect(data.translucentIndices, isNotEmpty);
        manager.apply(data);

        final components = renderWorld.children
            .whereType<MeshComponent>()
            .toList();
        expect(components, hasLength(2));
        final surfaces = components
            .map((component) => component.mesh.surfaces.single as PackedSurface)
            .toList();
        final opaqueSurface = surfaces.singleWhere(
          (surface) => identical(surface.indices, data.opaqueIndices),
        );
        final translucentSurface = surfaces.singleWhere(
          (surface) => identical(surface.indices, data.translucentIndices),
        );

        for (final surface in <PackedSurface>[
          opaqueSurface,
          translucentSurface,
        ]) {
          expect(surface.hasMaterializedPositions, isFalse);
          _expectAabb(
            surface.aabb,
            minX: 0,
            minY: 0,
            minZ: 0,
            maxX: size.toDouble(),
            maxY: size.toDouble(),
            maxZ: size.toDouble(),
          );
          expect(surface.hasMaterializedPositions, isFalse);
        }

        _expectBoundsContainPackedVertices(
          opaqueSurface.aabb,
          data.opaqueVertices,
        );
        _expectBoundsContainPackedVertices(
          translucentSurface.aabb,
          data.translucentVertices,
        );

        for (final component in components) {
          _expectAabb(
            component.aabb,
            minX: originX.toDouble(),
            minY: originY.toDouble(),
            minZ: originZ.toDouble(),
            maxX: (originX + size).toDouble(),
            maxY: (originY + size).toDouble(),
            maxZ: (originZ + size).toDouble(),
          );
        }
        expect(opaqueSurface.hasMaterializedPositions, isFalse);
        expect(translucentSurface.hasMaterializedPositions, isFalse);
      },
    );

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
      final renderWorld = World3D();
      final manager = ChunkRenderManager(
        world: renderWorld,
        material: Material.defaultMaterial,
      );

      expect(data.opaqueIndices, isEmpty);
      expect(data.translucentIndices, isNotEmpty);
      manager.apply(data);

      expect(manager.loadedChunkCount, 1);
      expect(renderWorld.children.whereType<MeshComponent>(), hasLength(1));

      manager.apply(
        ChunkMeshData(
          chunkIndex: data.chunkIndex,
          revision: data.revision + 1,
          opaqueVertices: Float32List(0),
          opaqueIndices: Uint16List(0),
          translucentVertices: Float32List(0),
          translucentIndices: Uint16List(0),
        ),
      );

      expect(manager.loadedChunkCount, 0);
      expect(renderWorld.children.whereType<MeshComponent>(), isEmpty);
    });
  });
}

void _expectBoundsContainPackedVertices(Aabb3 bounds, Float32List vertices) {
  for (
    var offset = 0;
    offset < vertices.length;
    offset += VertexLayout.floatsPerVertex
  ) {
    expect(vertices[offset], inInclusiveRange(bounds.min.x, bounds.max.x));
    expect(vertices[offset + 1], inInclusiveRange(bounds.min.y, bounds.max.y));
    expect(vertices[offset + 2], inInclusiveRange(bounds.min.z, bounds.max.z));
  }
}

void _expectAabb(
  Aabb3 actual, {
  required double minX,
  required double minY,
  required double minZ,
  required double maxX,
  required double maxY,
  required double maxZ,
}) {
  expect(actual.min.x, minX);
  expect(actual.min.y, minY);
  expect(actual.min.z, minZ);
  expect(actual.max.x, maxX);
  expect(actual.max.y, maxY);
  expect(actual.max.z, maxZ);
}
