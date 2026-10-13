import 'dart:typed_data';

import 'package:minedart_core/minedart_core.dart';

import '../diagnostics/resource_budget.dart';
import 'voxel_renderer.dart';

/// Owns up to two renderer passes for every voxel chunk.
///
/// The bookkeeping (revisions, render-distance range, retained counts and
/// bytes) is engine-neutral; [ChunkPassFactory] creates the renderer objects.
final class ChunkRenderManager {
  ChunkRenderManager({
    required ChunkPassFactory passes,
    this.resourceBudget = const ResourceBudget(),
  })
    // The public constructor intentionally exposes readable argument names.
    // ignore: prefer_initializing_formals
    : _passes = passes;

  final ResourceBudget resourceBudget;

  final ChunkPassFactory _passes;
  final Map<int, _ChunkPasses> _components = {};
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
  ResourceBudgetStatus get budgetStatus => resourceBudget.evaluate(
    pendingMeshJobs: 0,
    retainedMeshBytes: _retainedMeshBytes,
    retainedComponents: _retainedComponentCount,
  );
  bool isChunkInView(int chunkIndex) => _isInRange(chunkIndex);

  /// Applies a cheap chunk-distance gate in addition to the renderer's
  /// frustum culling. Mesh/material instances stay retained when the preset
  /// changes.
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
    final nextMeshBytes =
        data.opaqueVertices.lengthInBytes +
        data.opaqueIndices.lengthInBytes +
        data.translucentVertices.lengthInBytes +
        data.translucentIndices.lengthInBytes;
    final previous = _components[data.chunkIndex];
    // Budgets are observability thresholds. Retaining a valid mesh is safer
    // than silently dropping a visible chunk and leaving the scheduler with
    // no way to retry it after memory becomes available.
    _revisions[data.chunkIndex] = data.revision;

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
    final components = _ChunkPasses(
      opaque: _passFor(
        ChunkPassKind.opaque,
        cx,
        cy,
        cz,
        vertices: data.opaqueVertices,
        indices: data.opaqueIndices,
      ),
      translucent: _passFor(
        ChunkPassKind.translucent,
        cx,
        cy,
        cz,
        vertices: data.translucentVertices,
        indices: data.translucentIndices,
      ),
      meshBytes: nextMeshBytes,
    );
    _components[data.chunkIndex] = components;
    _retainedComponentCount += components.componentCount;
    _retainedMeshBytes += components.meshBytes;
    final inRange = _isInRange(data.chunkIndex);
    components.setDistanceVisible(inRange);
    if (inRange) _visibleChunkCount++;
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

  ChunkPassHandle? _passFor(
    ChunkPassKind kind,
    int cx,
    int cy,
    int cz, {
    required Float32List vertices,
    required Uint16List indices,
  }) {
    if (indices.isEmpty) return null;
    return _passes.createPass(
      kind: kind,
      chunkX: cx,
      chunkY: cy,
      chunkZ: cz,
      vertices: vertices,
      indices: indices,
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
}

final class _ChunkPasses {
  _ChunkPasses({this.opaque, this.translucent, required this.meshBytes});

  final ChunkPassHandle? opaque;
  final ChunkPassHandle? translucent;
  final int meshBytes;
  bool distanceVisible = false;
  int get componentCount =>
      (opaque == null ? 0 : 1) + (translucent == null ? 0 : 1);

  void setDistanceVisible(bool visible) {
    distanceVisible = visible;
    opaque?.distanceVisible = visible;
    translucent?.distanceVisible = visible;
  }

  void remove() {
    opaque?.removeFromScene();
    translucent?.removeFromScene();
  }
}
