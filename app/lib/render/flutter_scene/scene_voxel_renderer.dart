import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:minedart_core/minedart_core.dart' show VertexLayout, WorldDims;
import 'package:vector_math/vector_math.dart';

import '../../showcase/render/render_settings.dart';
import '../block_particle_simulation.dart';
import '../packed_primitives.dart';
import '../voxel_renderer.dart';

/// Initializes flutter_scene (WebGL2 on web, Flutter GPU natively).
///
/// Startup failures surface as [RendererInitializationException].
Future<void> initializeFlutterSceneGpu() async {
  try {
    await Scene.initializeStaticResources();
  } catch (error, stack) {
    Error.throwWithStackTrace(
      RendererInitializationException(
        RendererInitializationFailureKind.apiUnavailable,
        cause: error,
      ),
      stack,
    );
  }
}

/// Experimental [VoxelRenderer] on flutter_scene, drawn into the host canvas.
///
/// flutter_scene is left-handed (view +Z into the screen) and the voxel world
/// is right-handed, so the whole world hangs under a Z-mirror root node and
/// the camera lives in that mirrored space. The engine reverses triangle
/// winding for the mirrored nodes.
final class SceneVoxelRenderer implements VoxelRenderer {
  SceneVoxelRenderer._({
    required this.camera,
    required PreprocessedMaterial opaque,
    required PreprocessedMaterial translucent,
    required PreprocessedMaterial outline,
    required PreprocessedMaterial particle,
  }) : _scene = Scene(),
       _worldRoot = Node(
         name: 'minedart world',
         localTransform: Matrix4.diagonal3Values(1, 1, -1),
       ),
       material = _SceneVoxelMaterialControls([opaque, translucent]) {
    _scene
      ..antiAliasingMode = AntiAliasingMode.none
      ..toneMapping = ToneMappingMode.linear
      ..exposure = 1
      ..fitNearPlane = false
      ..debugCheckCoplanarOverlaps = false
      ..add(_worldRoot);
    chunkPasses = SceneChunkPasses._(_worldRoot, opaque, translucent);
    _targetOutline = SceneTargetOutline._(_worldRoot, outline);
    _particles = SceneBlockParticles._(_worldRoot, particle);
    frameCounters = _SceneFrameCounters(_scene);
  }

  /// Loads the atlas and the compiled `.fmat` materials.
  static Future<SceneVoxelRenderer> load({
    required SceneCameraControls camera,
    required String atlasAssetPath,
  }) async {
    final atlas = await _loadAtlas(atlasAssetPath);
    final opaque = await loadFmatMaterial('assets/materials/voxel_opaque.fmat');
    final translucent = await loadFmatMaterial(
      'assets/materials/voxel_translucent.fmat',
    );
    for (final voxel in [opaque, translucent]) {
      voxel.parameters.setTexture(
        'albedo_texture',
        atlas.gpuTexture,
        sampler: gpu.SamplerOptions(),
      );
    }
    final outline = await loadFmatMaterial('assets/materials/solid_color.fmat');
    final particle = await loadFmatMaterial(
      'assets/materials/solid_color.fmat',
    );
    return SceneVoxelRenderer._(
      camera: camera,
      opaque: opaque,
      translucent: translucent,
      outline: outline,
      particle: particle,
    );
  }

  final Scene _scene;
  final Node _worldRoot;
  late final SceneTargetOutline _targetOutline;
  late final SceneBlockParticles _particles;

  @override
  RenderCapabilities get capabilities => RenderCapabilities.native;

  @override
  late final SceneChunkPasses chunkPasses;

  @override
  final VoxelMaterialControls material;

  @override
  TargetOutlineControls get targetOutline => _targetOutline;

  @override
  BlockParticleEffects get particles => _particles;

  @override
  final SceneCameraControls camera;

  @override
  late final RenderFrameCounters frameCounters;

  @override
  void update(double dt) => _particles.update(dt);

  @override
  void render(ui.Canvas canvas, ui.Size size) {
    camera.sync();
    _scene.render(camera.camera, canvas, viewport: ui.Offset.zero & size);
  }
}

/// First-person camera with flame_3d's yaw/pitch convention, mirrored into
/// flutter_scene's left-handed space each frame.
final class SceneCameraControls implements RenderCameraControls {
  /// `eye` is the player's live eye position; the camera follows it.
  SceneCameraControls({required this._eye, required this._fovY});

  final Vector3 _eye;
  final PerspectiveCamera camera = PerspectiveCamera(
    fovNear: 0.01,
    fovFar: 1000,
  );
  double _fovY;
  Quaternion _rotation = Quaternion.identity();
  final Vector3 _look = Vector3.zero();

  @override
  double get fovY => _fovY;

  @override
  set fovY(double degrees) => _fovY = degrees;

  /// Same composition as flame_3d's `resetRotation()..rotate(yaw, pitch)`.
  @override
  void setOrientation(double yaw, double pitch) {
    final yawRotation = Quaternion.axisAngle(Vector3(0, 1, 0), yaw);
    final pitchRotation = Quaternion.axisAngle(Vector3(1, 0, 0), pitch);
    _rotation = (yawRotation * Quaternion.identity() * pitchRotation)
      ..normalize();
  }

  @override
  Vector3 lookDirectionInto(Vector3 out) => out
    ..setValues(0, 0, -1)
    ..applyQuaternion(_rotation);

  /// Copies the eye, look direction and field of view into [camera].
  void sync() {
    final look = lookDirectionInto(_look);
    camera
      ..position.setValues(_eye.x, _eye.y, -_eye.z)
      ..target.setValues(_eye.x + look.x, _eye.y + look.y, -(_eye.z + look.z))
      ..fovRadiansY = _fovY * degrees2Radians;
  }
}

/// The mesher's interleaved 80-byte vertices bound as-is: position @0, uv
/// @12, color @20, normal @36. The 32 zero bytes left from flame_3d's
/// joint/weight slots feed `texture_coords_1` and `tangent`. The trailing
/// buffer mirrors the engine's 80-byte instance record, which every
/// caller-declared color-pass layout must end with.
final VertexLayoutDescriptor _meshAbiLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: VertexLayout.bytesPerVertex,
      attributes: [
        VertexAttributeDescriptor(
          name: 'position',
          format: gpu.VertexFormat.float32x3,
        ),
        VertexAttributeDescriptor(
          name: 'texture_coords',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 12,
        ),
        VertexAttributeDescriptor(
          name: 'color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 20,
        ),
        VertexAttributeDescriptor(
          name: 'normal',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 36,
        ),
        VertexAttributeDescriptor(
          name: 'texture_coords_1',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 48,
        ),
        VertexAttributeDescriptor(
          name: 'tangent',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 56,
        ),
      ],
    ),
    VertexBufferDescriptor(
      strideInBytes: 80,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        VertexAttributeDescriptor(
          name: 'model_transform_0',
          format: gpu.VertexFormat.float32x4,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_1',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 16,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_2',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 32,
        ),
        VertexAttributeDescriptor(
          name: 'model_transform_3',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 48,
        ),
        VertexAttributeDescriptor(
          name: 'instance_color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 64,
        ),
      ],
    ),
  ],
);

/// Uploads mesh-ABI buffers without repacking. Custom-layout geometry has no
/// CPU positions, so bounds are supplied explicitly for culling.
UnskinnedGeometry _meshAbiGeometry(
  Float32List vertices,
  Uint16List indices, {
  required Aabb3 bounds,
}) {
  final center = (bounds.min + bounds.max)..scale(0.5);
  final radius = (bounds.max - bounds.min).length / 2;
  return UnskinnedGeometry()
    ..uploadVertexStreams(
      [vertices],
      vertices.length ~/ VertexLayout.floatsPerVertex,
      indices: indices,
    )
    ..setVertexLayout(_meshAbiLayout)
    ..setLocalBounds(bounds, Sphere.centerRadius(center, radius));
}

/// Chunk passes as nodes under the mirrored world root.
final class SceneChunkPasses implements ChunkPassFactory {
  SceneChunkPasses._(this._root, this._opaque, this._translucent);

  final Node _root;
  final Material _opaque;
  final Material _translucent;

  /// ChunkMesher writes chunk-local coordinates within 0..chunkSize.
  static final Aabb3 _chunkBounds = Aabb3.minMax(
    Vector3.zero(),
    Vector3.all(WorldDims.chunkSize.toDouble()),
  );

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
    final node = Node(
      name: 'chunk $chunkX,$chunkY,$chunkZ ${kind.name}',
      localTransform: Matrix4.translationValues(
        chunkX * extent,
        chunkY * extent,
        chunkZ * extent,
      ),
      mesh: Mesh(
        _meshAbiGeometry(vertices, indices, bounds: _chunkBounds),
        kind == ChunkPassKind.opaque ? _opaque : _translucent,
      ),
    );
    _root.add(node);
    return _SceneChunkPass(_root, node);
  }
}

final class _SceneChunkPass implements ChunkPassHandle {
  _SceneChunkPass(this._root, this._node);

  final Node _root;
  final Node _node;

  @override
  set distanceVisible(bool visible) => _node.visible = visible;

  /// Releases the node; flutter_scene frees GPU buffers only on GC.
  @override
  void removeFromScene() => _root.remove(_node);
}

final class _SceneVoxelMaterialControls implements VoxelMaterialControls {
  _SceneVoxelMaterialControls(this._materials);

  final List<PreprocessedMaterial> _materials;

  @override
  void setFogRange(double start, double end) {
    for (final material in _materials) {
      material.parameters
        ..setFloat('fog_start', start)
        ..setFloat('fog_end', end);
    }
  }

  @override
  void setRenderStyle({
    required int debugView,
    required double fogDensity,
    required bool ambientOcclusion,
  }) {
    for (final material in _materials) {
      material.parameters
        ..setInt('debug_view', debugView.clamp(0, 6))
        ..setFloat('fog_density', fogDensity.clamp(0, 1))
        ..setFloat('baked_light_strength', ambientOcclusion ? 1 : 0);
    }
  }
}

/// Block outline built from the same packed edge cuboids as flame_3d's.
final class SceneTargetOutline implements TargetOutlineControls {
  SceneTargetOutline._(Node root, this._material) {
    final geometry = targetOutlineGeometry();
    _node = Node(
      name: 'target outline',
      mesh: Mesh(
        _meshAbiGeometry(
          geometry.vertices,
          geometry.indices,
          bounds: Aabb3.minMax(Vector3.all(-0.05), Vector3.all(1.05)),
        ),
        _material,
      ),
    )..visible = false;
    root.add(_node);
    _applyColor();
  }

  static const ui.Color _color = ui.Color(0xFF111111);
  static const ui.Color _highContrastColor = ui.Color(0xFFFFFF00);

  final PreprocessedMaterial _material;
  late final Node _node;
  bool _enabled = true;
  bool _hasTarget = false;
  bool _highContrast = false;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    _node.visible = isShown;
  }

  @override
  bool get isShown => _enabled && _hasTarget;

  @override
  void showAt(int x, int y, int z) {
    _node.localTransform = Matrix4.translationValues(
      x.toDouble(),
      y.toDouble(),
      z.toDouble(),
    );
    _hasTarget = true;
    _node.visible = isShown;
  }

  @override
  void hide() {
    _hasTarget = false;
    _node.visible = false;
  }

  @override
  void setHighContrast(bool value) {
    if (_highContrast == value) return;
    _highContrast = value;
    _applyColor();
  }

  void _applyColor() {
    _material.parameters.setColor(
      'color',
      _highContrast ? _highContrastColor : _color,
    );
  }
}

/// Block particles: [BlockParticleSimulation] slots drawn as retained cube
/// nodes, one per slot, hidden while inactive.
final class SceneBlockParticles implements BlockParticleEffects {
  SceneBlockParticles._(Node root, PreprocessedMaterial material)
    : _simulation = BlockParticleSimulation() {
    material.parameters.setColor('color', const ui.Color(0xFFD8C2A2));
    // One geometry per slot: nodes sharing a caller-layout geometry and
    // material are merged into an instanced draw, which did not render
    // particles. The cube is 8 vertices, so the copies are cheap.
    final cube = unitCubeGeometry;
    _nodes = List<Node>.generate(
      _simulation.capacity,
      (index) => Node(
        name: 'particle $index',
        mesh: Mesh(
          _meshAbiGeometry(
            cube.vertices,
            cube.indices,
            bounds: Aabb3.minMax(Vector3.all(-0.5), Vector3.all(0.5)),
          ),
          material,
        ),
      )..visible = false,
      growable: false,
    );
    for (final node in _nodes) {
      root.add(node);
    }
  }

  final BlockParticleSimulation _simulation;
  late final List<Node> _nodes;
  final Vector3 _translation = Vector3.zero();
  final Vector3 _scale = Vector3.zero();
  final Quaternion _rotation = Quaternion.identity();

  @override
  bool get enabled => _simulation.enabled;

  @override
  set enabled(bool value) {
    _simulation.enabled = value;
    _sync();
  }

  @override
  bool get reducedMotion => _simulation.reducedMotion;

  @override
  set reducedMotion(bool value) {
    _simulation.reducedMotion = value;
    _sync();
  }

  @override
  int emitBlock({
    required int blockId,
    required int x,
    required int y,
    required int z,
    int count = 8,
  }) {
    final emitted = _simulation.emit(
      blockId: blockId,
      x: x + 0.5,
      y: y + 0.5,
      z: z + 0.5,
      count: count,
    );
    if (emitted > 0) _sync();
    return emitted;
  }

  void update(double dt) {
    if (dt <= 0 || _simulation.activeCount == 0) return;
    _simulation.update(dt);
    _sync();
  }

  void _sync() {
    for (var i = 0; i < _nodes.length; i++) {
      final state = _simulation.particles[i];
      final node = _nodes[i];
      node.visible = state.active;
      if (!state.active) continue;
      final angle = state.spinAngle;
      _translation.setValues(state.x, state.y, state.z);
      _scale.setValues(state.scale, state.scale, state.scale);
      _rotation.setEuler(angle, angle * 0.7, angle * 0.4);
      node.mutateLocalTransform(
        (transform) => transform.setFromTranslationRotationScale(
          _translation,
          _rotation,
          _scale,
        ),
      );
    }
  }
}

final class _SceneFrameCounters implements RenderFrameCounters {
  _SceneFrameCounters(this._scene);

  final Scene _scene;

  @override
  int get drawCount => _scene.renderStats.latest?.counters.draws ?? 0;

  @override
  int? get uniformUploadHits => null;

  @override
  int? get uniformUploadMisses => null;

  @override
  int? get bindGroupHits => null;

  @override
  int? get bindGroupMisses => null;
}

/// Decodes the atlas into an unfiltered, mip-free texture; the mesher's UVs
/// rely on nearest sampling.
Future<Texture2D> _loadAtlas(String assetPath) async {
  final bytes = await rootBundle.load('assets/$assetPath');
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final image = (await codec.getNextFrame()).image;
  try {
    final rgba = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (rgba == null) throw StateError('Could not decode $assetPath');
    return Texture2D.fromPixels(
      rgba.buffer.asUint8List(),
      image.width,
      image.height,
      sampling: const TextureSampling(
        mipmaps: false,
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
        mipFilter: gpu.MipFilter.nearest,
      ),
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}
