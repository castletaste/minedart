import 'dart:typed_data';
import 'dart:ui' show Canvas, Size;

import 'package:vector_math/vector_math.dart';

import '../showcase/render/render_settings.dart';

/// Engine-neutral rendering port.
///
/// Gameplay, meshing and Render Lab code depend on these interfaces only. The
/// flame_3d implementation lives in `render/flame3d/`; nothing else in the app
/// imports `package:flame_3d` except the Flame host binding in `MinedartGame`.
abstract interface class VoxelRenderer {
  RenderCapabilities get capabilities;
  ChunkPassFactory get chunkPasses;
  VoxelMaterialControls get material;
  TargetOutlineControls get targetOutline;
  BlockParticleEffects get particles;
  RenderCameraControls get camera;

  /// Counters from the most recently completed frame.
  RenderFrameCounters get frameCounters;

  /// Advances renderer-side simulation (particles) once per game update.
  /// Renderers whose effects live in the host's component tree do nothing.
  void update(double dt);

  /// Draws the scene into the host canvas, after the host's own component
  /// tree, at the logical [size]. Renderers that draw through the host's
  /// components do nothing.
  void render(Canvas canvas, Size size);
}

/// The two mesh passes a chunk can have.
enum ChunkPassKind { opaque, translucent }

/// One renderer-owned mesh pass of a chunk.
abstract interface class ChunkPassHandle {
  /// Render-distance gate, applied on top of the renderer's frustum culling.
  set distanceVisible(bool visible);

  /// Removes the pass from the scene. The handle is not reused afterwards.
  void removeFromScene();
}

/// Creates renderer-owned chunk passes; `ChunkRenderManager` keeps the
/// revision, range and budget bookkeeping.
abstract interface class ChunkPassFactory {
  /// [vertices] and [indices] use the mesh ABI of `VertexLayout`; positions
  /// are local to the chunk at ([chunkX], [chunkY], [chunkZ]).
  ChunkPassHandle createPass({
    required ChunkPassKind kind,
    required int chunkX,
    required int chunkY,
    required int chunkZ,
    required Float32List vertices,
    required Uint16List indices,
  });
}

abstract interface class VoxelMaterialControls {
  void setFogRange(double start, double end);
  void setRenderStyle({
    required int debugView,
    required double fogDensity,
    required bool ambientOcclusion,
  });
}

/// Outline around the block under the crosshair.
abstract interface class TargetOutlineControls {
  bool get enabled;
  set enabled(bool value);
  bool get isShown;
  void showAt(int x, int y, int z);
  void hide();
  void setHighContrast(bool value);
}

/// Block break/place particles.
abstract interface class BlockParticleEffects {
  bool get enabled;
  set enabled(bool value);
  bool get reducedMotion;
  set reducedMotion(bool value);

  /// Emits up to [count] particles from the center of block ([x], [y], [z])
  /// and returns how many were emitted.
  int emitBlock({
    required int blockId,
    required int x,
    required int y,
    required int z,
    int count = 8,
  });
}

/// First-person camera controls. The eye position follows the player.
abstract interface class RenderCameraControls {
  /// Vertical field of view in degrees.
  double get fovY;
  set fovY(double degrees);

  void setOrientation(double yaw, double pitch);

  /// Writes the unit look direction into [out] and returns it.
  Vector3 lookDirectionInto(Vector3 out);
}

/// Per-frame renderer counters published through `FrameMetrics`.
abstract interface class RenderFrameCounters {
  int get drawCount;

  /// Bind-cache counters, or null when the backend has none.
  int? get uniformUploadHits;
  int? get uniformUploadMisses;
  int? get bindGroupHits;
  int? get bindGroupMisses;
}

/// The stage at which a renderer could not acquire its graphics API.
enum RendererInitializationFailureKind {
  /// The platform does not expose the graphics API (for example WebGPU).
  apiUnavailable,

  /// The API is present, but no compatible graphics adapter was acquired.
  adapterUnavailable,

  /// An adapter was acquired, but a graphics device could not be created.
  deviceUnavailable,
}

/// Renderer startup failure. Choose user-facing guidance from [kind]; [cause]
/// is retained for diagnostics only.
final class RendererInitializationException implements Exception {
  const RendererInitializationException(this.kind, {this.cause});

  final RendererInitializationFailureKind kind;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    return cause == null
        ? 'RendererInitializationException($kind)'
        : 'RendererInitializationException($kind, cause: $cause)';
  }
}
