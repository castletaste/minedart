import 'dart:typed_data';

import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/render/chunk_render_manager.dart';
import 'package:minedart/render/flame3d/flame3d_voxel_renderer.dart';
import 'package:minedart/render/flame3d/packed_surface.dart';
import 'package:minedart/render/voxel_renderer.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('Flame3dChunkPasses', () {
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
          passes: Flame3dChunkPasses(
            world: renderWorld,
            material: Material.defaultMaterial,
          ),
        );

        expect(data.opaqueIndices, isNotEmpty);
        expect(data.translucentIndices, isNotEmpty);
        manager.apply(data);

        final components = renderWorld.children
            .whereType<MeshComponent>()
            .toList();
        expect(components, hasLength(2));
        expect(manager.retainedComponentCount, 2);
        expect(manager.retainedMeshBytes, _meshBytes(data));
        manager.apply(
          ChunkMeshData(
            chunkIndex: data.chunkIndex,
            revision: data.revision - 1,
            opaqueVertices: Float32List(0),
            opaqueIndices: Uint16List(0),
            translucentVertices: Float32List(0),
            translucentIndices: Uint16List(0),
          ),
        );
        expect(manager.retainedComponentCount, 2);
        expect(manager.retainedMeshBytes, _meshBytes(data));
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

    test('gates distance visibility and removes passes from the world', () {
      final renderWorld = World3D();
      final passes = Flame3dChunkPasses(
        world: renderWorld,
        material: Material.defaultMaterial,
      );
      final pass =
          passes.createPass(
                kind: ChunkPassKind.translucent,
                chunkX: 1,
                chunkY: 2,
                chunkZ: 3,
                vertices: Float32List(VertexLayout.floatsPerVertex * 3),
                indices: Uint16List.fromList(const [0, 1, 2]),
              )
              as Flame3dChunkPass;

      expect(renderWorld.children.whereType<MeshComponent>(), [pass]);
      expect(pass.kind, ChunkPassKind.translucent);
      expect(pass.position.x, WorldDims.chunkSize.toDouble());
      expect(pass.position.y, 2.0 * WorldDims.chunkSize);
      expect(pass.position.z, 3.0 * WorldDims.chunkSize);
      expect(pass.distanceVisible, isTrue);
      final camera = CameraComponent3D();
      pass.distanceVisible = false;
      expect(pass.isVisible(camera), isFalse);

      pass.removeFromScene();
      expect(renderWorld.children.whereType<MeshComponent>(), isEmpty);
    });
  });
}

int _meshBytes(ChunkMeshData data) =>
    data.opaqueVertices.lengthInBytes +
    data.opaqueIndices.lengthInBytes +
    data.translucentVertices.lengthInBytes +
    data.translucentIndices.lengthInBytes;

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
