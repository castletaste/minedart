import 'dart:typed_data';

import 'package:flame/cache.dart' show Images;
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:minedart_core/minedart_core.dart' show WorldDims;

import '../../showcase/render/render_settings.dart';
import '../voxel_renderer.dart';
import 'block_particle_pool.dart';
import 'packed_surface.dart';
import 'target_outline.dart';
import 'voxel_material.dart';

/// Initializes the flame_3d GPU backend (WebGPU on web, FlutterGPU natively).
///
/// Backend startup failures surface as [RendererInitializationException].
Future<void> initializeFlame3dGpu() async {
  try {
    await GpuBackend.initialize();
  } on GpuInitializationException catch (error, stack) {
    Error.throwWithStackTrace(rendererInitializationFailure(error), stack);
  }
}

/// Maps a flame_3d startup failure onto the engine-neutral port type.
@visibleForTesting
RendererInitializationException rendererInitializationFailure(
  GpuInitializationException error,
) => RendererInitializationException(switch (error.kind) {
  GpuInitializationFailureKind.apiUnavailable =>
    RendererInitializationFailureKind.apiUnavailable,
  GpuInitializationFailureKind.adapterUnavailable =>
    RendererInitializationFailureKind.adapterUnavailable,
  GpuInitializationFailureKind.deviceUnavailable =>
    RendererInitializationFailureKind.deviceUnavailable,
}, cause: error.cause);

/// [VoxelRenderer] on flame_3d components inside a Flame `FlameGame3D`.
final class Flame3dVoxelRenderer implements VoxelRenderer {
  Flame3dVoxelRenderer._({
    required World3D world,
    required this.camera,
    required Material material,
    required VoxelMaterialControls materialControls,
  }) : _world = world,
       material = materialControls,
       chunkPasses = Flame3dChunkPasses(world: world, material: material),
       frameCounters = _Flame3dFrameCounters(world);

  /// Loads the atlas and builds the voxel material, outline and particles.
  ///
  /// Nothing is added to [world] until [attach], so a host torn down while
  /// the atlas loads can drop the result without touching its scene.
  static Future<Flame3dVoxelRenderer> load({
    required World3D world,
    required Flame3dCameraControls camera,
    required Images images,
    required String atlasAssetPath,
  }) async {
    final atlas = await images.loadTexture(atlasAssetPath);
    // Web uses a compact WGSL cutout material; macOS keeps fog support.
    final Material material;
    final VoxelMaterialControls controls;
    if (kIsWeb) {
      final webMaterial = WebVoxelMaterial(albedoTexture: atlas);
      material = webMaterial;
      controls = webMaterial;
    } else {
      final nativeMaterial = VoxelMaterial(albedoTexture: atlas);
      material = nativeMaterial;
      controls = nativeMaterial;
    }
    return Flame3dVoxelRenderer._(
      world: world,
      camera: camera,
      material: material,
      materialControls: controls,
    );
  }

  final World3D _world;
  final TargetOutline _targetOutline = TargetOutline()..hide();
  final BlockParticlePool _particles = BlockParticlePool();

  @override
  RenderCapabilities get capabilities =>
      kIsWeb ? RenderCapabilities.web : RenderCapabilities.native;

  @override
  final Flame3dChunkPasses chunkPasses;

  @override
  final VoxelMaterialControls material;

  @override
  TargetOutlineControls get targetOutline => _targetOutline;

  @override
  BlockParticleEffects get particles => _particles;

  @override
  final Flame3dCameraControls camera;

  @override
  final RenderFrameCounters frameCounters;

  /// Adds the ambient light, outline and particle pool to the scene.
  void attach() {
    _world.addAll([
      LightComponent.ambient(intensity: 1.0),
      _targetOutline,
      _particles,
    ]);
  }
}

/// Wraps the host's [CameraComponent3D].
final class Flame3dCameraControls implements RenderCameraControls {
  Flame3dCameraControls(this._camera);

  final CameraComponent3D _camera;

  @override
  double get fovY => _camera.fovY;

  @override
  set fovY(double degrees) => _camera.fovY = degrees;

  @override
  void setOrientation(double yaw, double pitch) {
    _camera
      ..resetRotation()
      ..rotate(yaw, pitch);
  }

  @override
  Vector3 lookDirectionInto(Vector3 out) => out
    ..setValues(0, 0, -1)
    ..applyQuaternion(_camera.rotation);
}

/// Chunk passes as distance-gated [MeshComponent]s backed by [PackedSurface].
final class Flame3dChunkPasses implements ChunkPassFactory {
  Flame3dChunkPasses({required World3D world, required Material material})
    // The public constructor intentionally exposes readable argument names.
    // ignore: prefer_initializing_formals
    : _world = world,
      // ignore: prefer_initializing_formals
      _material = material;

  final World3D _world;
  final Material _material;

  @override
  ChunkPassHandle createPass({
    required ChunkPassKind kind,
    required int chunkX,
    required int chunkY,
    required int chunkZ,
    required Float32List vertices,
    required Uint16List indices,
  }) {
    final extent = WorldDims.chunkSize.toDouble();
    final mesh = Mesh()
      ..addSurface(
        PackedSurface(
          vertices: vertices,
          indices: indices,
          material: _material,
          aabb: _chunkLocalAabb(),
        ),
      );
    final component = Flame3dChunkPass(
      kind: kind,
      mesh: mesh,
      position: Vector3(chunkX * extent, chunkY * extent, chunkZ * extent),
    );
    _world.add(component);
    return component;
  }

  /// ChunkMesher writes local block coordinates: cube and crossed-quad
  /// corners stay in 0..chunkSize, while lowered fluid tops only shrink that
  /// range. This is the tightest content-independent bound shared by both
  /// passes and avoids scanning/copying packed positions during every remesh.
  static Aabb3 _chunkLocalAabb() {
    final extent = WorldDims.chunkSize.toDouble();
    return Aabb3.minMax(Vector3.zero(), Vector3.all(extent));
  }
}

/// One chunk pass in the flame_3d scene.
final class Flame3dChunkPass extends MeshComponent implements ChunkPassHandle {
  Flame3dChunkPass({
    required this.kind,
    required super.mesh,
    required super.position,
  });

  final ChunkPassKind kind;

  bool _distanceVisible = true;
  bool get distanceVisible => _distanceVisible;

  @override
  set distanceVisible(bool visible) => _distanceVisible = visible;

  @override
  void removeFromScene() => removeFromParent();

  @override
  bool isVisible(CameraComponent3D camera) =>
      _distanceVisible && super.isVisible(camera);
}

final class _Flame3dFrameCounters implements RenderFrameCounters {
  _Flame3dFrameCounters(this._world);

  final World3D _world;

  @override
  int get drawCount => _world.context.drawCount;

  @override
  int? get uniformUploadHits =>
      _world.context.device.lastBindCacheCounters?.uniformUploadHits;

  @override
  int? get uniformUploadMisses =>
      _world.context.device.lastBindCacheCounters?.uniformUploadMisses;

  @override
  int? get bindGroupHits =>
      _world.context.device.lastBindCacheCounters?.bindGroupHits;

  @override
  int? get bindGroupMisses =>
      _world.context.device.lastBindCacheCounters?.bindGroupMisses;
}
