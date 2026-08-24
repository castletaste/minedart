import 'dart:typed_data';
import 'dart:ui' show Canvas;

import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/resources.dart';
import 'package:minedart_core/minedart_core.dart';

import 'packed_surface.dart';

/// Owns up to two render components for every voxel chunk.
final class ChunkRenderManager {
  ChunkRenderManager({required World3D world, required Material material})
    // The public constructor intentionally exposes readable argument names.
    // ignore: prefer_initializing_formals
    : _world = world,
      // ignore: prefer_initializing_formals
      _material = material;

  final World3D _world;
  final Material _material;
  final Map<int, _ChunkComponents> _components = {};
  final Map<int, int> _revisions = {};
  int _retainedComponentCount = 0;
  int _retainedMeshBytes = 0;
  int _viewChunkX = 0;
  int _viewChunkZ = 0;
  int _renderDistanceChunks = WorldDims.worldChunksX;
  int _visibleChunkCount = 0;

  int get loadedChunkCount => _components.length;
  int get visibleChunkCount => _visibleChunkCount;
  int get retainedComponentCount => _retainedComponentCount;
  int get retainedMeshBytes => _retainedMeshBytes;
  bool isChunkInView(int chunkIndex) => _isInRange(chunkIndex);

  /// Applies a cheap chunk-distance gate in addition to flame_3d's frustum
  /// culling. Mesh/material instances stay retained when the preset changes.
  void updateVisibility({
    required double playerX,
    required double playerZ,
    required int renderDistanceChunks,
  }) {
    final nextX = (playerX ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksX - 1,
    );
    final nextZ = (playerZ ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksZ - 1,
    );
    final nextDistance = renderDistanceChunks.clamp(2, WorldDims.worldChunksX);
    if (_viewChunkX == nextX &&
        _viewChunkZ == nextZ &&
        _renderDistanceChunks == nextDistance) {
      return;
    }
    _viewChunkX = nextX;
    _viewChunkZ = nextZ;
    _renderDistanceChunks = nextDistance;
    var visible = 0;
    for (final entry in _components.entries) {
      final inRange = _isInRange(entry.key);
      entry.value.setDistanceVisible(inRange);
      if (inRange) visible++;
    }
    _visibleChunkCount = visible;
  }

  /// Installs the latest mesh for a chunk. Empty passes have no component.
  void apply(ChunkMeshData data) {
    if (!_isInRange(data.chunkIndex)) return;
    final previousRevision = _revisions[data.chunkIndex];
    if (previousRevision != null && data.revision < previousRevision) {
      return;
    }
    _revisions[data.chunkIndex] = data.revision;

    final previous = _components[data.chunkIndex];
    if (previous?.distanceVisible ?? false) _visibleChunkCount--;
    if (previous != null) {
      _retainedComponentCount -= previous.componentCount;
      _retainedMeshBytes -= previous.meshBytes;
    }
    previous?.remove();

    if (data.isEmpty) {
      _components.remove(data.chunkIndex);
      return;
    }

    final (cx, cy, cz) = _coordinates(data.chunkIndex);
    final position = Vector3(
      cx * WorldDims.chunkSize.toDouble(),
      cy * WorldDims.chunkSize.toDouble(),
      cz * WorldDims.chunkSize.toDouble(),
    );
    final components = _ChunkComponents(
      opaque: _componentFor(
        vertices: data.opaqueVertices,
        indices: data.opaqueIndices,
        position: position,
        opaquePass: true,
      ),
      translucent: _componentFor(
        vertices: data.translucentVertices,
        indices: data.translucentIndices,
        position: position,
        opaquePass: false,
      ),
      meshBytes:
          data.opaqueVertices.lengthInBytes +
          data.opaqueIndices.lengthInBytes +
          data.translucentVertices.lengthInBytes +
          data.translucentIndices.lengthInBytes,
    );
    _components[data.chunkIndex] = components;
    _retainedComponentCount += components.componentCount;
    _retainedMeshBytes += components.meshBytes;
    final inRange = _isInRange(data.chunkIndex);
    components.setDistanceVisible(inRange);
    if (inRange) _visibleChunkCount++;
    components.addTo(_world);
  }

  /// Releases retained CPU/GPU mesh lifetimes outside the active chunk view.
  ///
  /// Callers remove the returned indices from their requested set so revisiting
  /// an evicted area schedules a fresh mesh from the authoritative voxel world.
  int evictOutsideView({void Function(int chunkIndex)? onEvicted}) {
    var evicted = 0;
    _components.removeWhere((chunkIndex, components) {
      if (_isInRange(chunkIndex)) return false;
      if (components.distanceVisible) _visibleChunkCount--;
      _retainedComponentCount -= components.componentCount;
      _retainedMeshBytes -= components.meshBytes;
      _revisions.remove(chunkIndex);
      components.remove();
      onEvicted?.call(chunkIndex);
      evicted++;
      return true;
    });
    return evicted;
  }

  _DistanceCulledMeshComponent? _componentFor({
    required Float32List vertices,
    required Uint16List indices,
    required Vector3 position,
    required bool opaquePass,
  }) {
    if (indices.isEmpty) return null;
    final mesh = Mesh()
      ..addSurface(
        PackedSurface(
          vertices: vertices,
          indices: indices,
          material: _material,
          aabb: _newChunkLocalAabb(),
        ),
      );
    return _DistanceCulledMeshComponent(
      mesh: mesh,
      position: position.clone(),
      opaquePass: opaquePass,
    );
  }

  bool _isInRange(int chunkIndex) {
    final (cx, _, cz) = _coordinates(chunkIndex);
    return (cx - _viewChunkX).abs() <= _renderDistanceChunks &&
        (cz - _viewChunkZ).abs() <= _renderDistanceChunks;
  }

  (int, int, int) _coordinates(int chunkIndex) {
    final cx = chunkIndex % WorldDims.worldChunksX;
    final cz = (chunkIndex ~/ WorldDims.worldChunksX) % WorldDims.worldChunksZ;
    final cy = chunkIndex ~/ (WorldDims.worldChunksX * WorldDims.worldChunksZ);
    return (cx, cy, cz);
  }

  /// ChunkMesher writes local block coordinates: cube and crossed-quad
  /// corners stay in 0..chunkSize, while lowered fluid tops only shrink that
  /// range. This is the tightest content-independent bound shared by both
  /// passes and avoids scanning/copying packed positions during every remesh.
  static Aabb3 _newChunkLocalAabb() {
    final extent = WorldDims.chunkSize.toDouble();
    return Aabb3.minMax(Vector3.zero(), Vector3.all(extent));
  }
}

final class _ChunkComponents {
  const _ChunkComponents({
    this.opaque,
    this.translucent,
    required this.meshBytes,
  });

  final _DistanceCulledMeshComponent? opaque;
  final _DistanceCulledMeshComponent? translucent;
  final int meshBytes;
  int get componentCount =>
      (opaque == null ? 0 : 1) + (translucent == null ? 0 : 1);
  bool get distanceVisible =>
      opaque?.distanceVisible ?? translucent?.distanceVisible ?? false;

  void setDistanceVisible(bool visible) {
    if (opaque != null) opaque!.distanceVisible = visible;
    if (translucent != null) translucent!.distanceVisible = visible;
  }

  void addTo(World3D world) {
    if (opaque != null) world.add(opaque!);
    if (translucent != null) world.add(translucent!);
  }

  void remove() {
    opaque?.removeFromParent();
    translucent?.removeFromParent();
  }
}

final class _DistanceCulledMeshComponent extends MeshComponent {
  _DistanceCulledMeshComponent({
    required super.mesh,
    required super.position,
    required this.opaquePass,
  });

  final bool opaquePass;
  bool distanceVisible = true;
  final Matrix4 _opaqueSortTransform = Matrix4.identity()
    ..setTranslationRaw(1000000, 1000000, 1000000);

  /// flame_3d 0.3 sorts every object back-to-front in one alpha/depth pass.
  /// Giving opaque chunk draws a stable large sort distance ensures the full
  /// terrain depth/color buffer exists before water/glass are blended. The
  /// actual draw still uses [worldTransformMatrix], so geometry is unchanged.
  @override
  void renderTree(Canvas canvas) {
    final camera = CameraComponent3D.currentCamera;
    if (camera == null || !isVisible(camera)) return;
    world.context.submitDraw(
      this,
      opaquePass ? _opaqueSortTransform : worldTransformMatrix,
    );
  }

  @override
  bool isVisible(CameraComponent3D camera) =>
      distanceVisible && super.isVisible(camera);
}
