import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/material.dart' hide Material;

/// Compile-time scene size. Supported profiles are 100, 400, 800 and 1350.
///
/// Example: `flutter run -d macos --release --dart-define=MESH_COUNT=800`.
const meshCount = int.fromEnvironment('MESH_COUNT', defaultValue: 1350);

const _supportedMeshCounts = {100, 400, 800, 1350};
const _quadsPerSurface = 1000;
const _quadsAcross = 40;
const _quadsDeep = _quadsPerSurface ~/ _quadsAcross;
const _quadSize = 0.25;
const _chunkSizeX = _quadsAcross * _quadSize;
const _chunkSizeZ = _quadsDeep * _quadSize;
const _chunkGap = 1.0;
const _statsOverlay = 'stats';

Future<void> main() async {
  if (!_supportedMeshCounts.contains(meshCount)) {
    throw ArgumentError.value(
      meshCount,
      'MESH_COUNT',
      'Supported values: ${_supportedMeshCounts.join(', ')}',
    );
  }

  WidgetsFlutterBinding.ensureInitialized();
  await GpuBackend.initialize();
  runApp(
    GameWidget<ManyMeshesGame>.controlled(
      gameFactory: ManyMeshesGame.new,
      overlayBuilderMap: {
        _statsOverlay: (context, game) => _StatsOverlay(game: game),
      },
    ),
  );
}

class ManyMeshesGame extends FlameGame3D {
  ManyMeshesGame()
    : super(
        camera: CameraComponent3D(
          fovY: 55,
          position: Vector3(0, 120, 180),
          target: Vector3.zero(),
        ),
      );

  final stats = ValueNotifier(const FrameStats.initial());

  late final int _columns;
  late final double _sceneWidth;
  late final double _sceneDepth;
  late final Vector3 _sceneCenter;
  double _elapsed = 0;
  double _lastLogAt = 0;
  double _lastOverlayAt = 0;
  double _emaFps = 0;

  @override
  Future<void> onLoad() async {
    _columns = math.sqrt(meshCount).ceil();
    final rows = (meshCount / _columns).ceil();
    _sceneWidth = _columns * (_chunkSizeX + _chunkGap) - _chunkGap;
    _sceneDepth = rows * (_chunkSizeZ + _chunkGap) - _chunkGap;
    _sceneCenter = Vector3(_sceneWidth / 2, 0, _sceneDepth / 2);

    final material = SpatialMaterial(
      albedoColor: const Color(0xFF4FAE61),
      metallic: 0,
      roughness: 1,
    );

    world.add(LightComponent.ambient(intensity: 0.9));
    for (var index = 0; index < meshCount; index++) {
      final column = index % _columns;
      final row = index ~/ _columns;
      // Each component owns an independent Mesh and Surface. Geometry is made
      // unique by its deterministic height pattern, not merely copied.
      final mesh = Mesh()
        ..addSurface(_buildChunkSurface(index: index, material: material));
      world.add(
        MeshComponent(
          mesh: mesh,
          position: Vector3(
            column * (_chunkSizeX + _chunkGap),
            0,
            row * (_chunkSizeZ + _chunkGap),
          ),
        ),
      );
    }

    overlays.add(_statsOverlay);
    _publishStats();
    // ignore: avoid_print
    print(
      'S3 ready: meshes=$meshCount, surfaces=$meshCount, '
      'quads/surface=$_quadsPerSurface, vertices/surface=${_quadsPerSurface * 4}, '
      'indices/surface=${_quadsPerSurface * 6}',
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dt <= 0) {
      return;
    }

    _elapsed += dt;
    final instantFps = 1 / dt;
    final alpha = 1 - math.exp(-dt / 1.0); // One-second EMA time constant.
    _emaFps = _emaFps == 0
        ? instantFps
        : _emaFps + alpha * (instantFps - _emaFps);

    _updateCamera();

    if (_elapsed - _lastOverlayAt >= 0.25) {
      _lastOverlayAt = _elapsed;
      _publishStats();
    }
    if (_elapsed - _lastLogAt >= 2) {
      _lastLogAt = _elapsed;
      final frame = stats.value;
      // ignore: avoid_print
      print(
        'S3 fps=${frame.emaFps.toStringAsFixed(1)} '
        'components=${frame.components} visible_draws=${frame.visibleDraws}',
      );
    }
  }

  void _updateCamera() {
    final radius = math.max(_sceneWidth, _sceneDepth) * 0.72 + 45;
    final angle = _elapsed * 0.10;
    camera.position = Vector3(
      _sceneCenter.x + math.cos(angle) * radius,
      radius * 0.52 + 28,
      _sceneCenter.z + math.sin(angle) * radius,
    );
    camera.target = _sceneCenter;
  }

  void _publishStats() {
    // drawCount is the previous render's submitted Object3D count. Every
    // component has exactly one Surface, therefore it is also draw-call count.
    // ignore: invalid_use_of_internal_member
    final visibleDraws = context.drawCount;
    stats.value = FrameStats(
      emaFps: _emaFps,
      components: meshCount,
      visibleDraws: visibleDraws,
    );
  }
}

Surface _buildChunkSurface({required int index, required Material material}) {
  final vertices = <Vertex>[];
  final indices = <int>[];
  final normal = Vector3(0, 1, 0);
  // This index-dependent offset is baked into every vertex list, so no two
  // surfaces share either a GPU buffer or identical geometry.
  final heightBias = (index + 1) * 0.0007;

  for (var z = 0; z < _quadsDeep; z++) {
    for (var x = 0; x < _quadsAcross; x++) {
      final base = vertices.length;
      final x0 = x * _quadSize;
      final z0 = z * _quadSize;
      final x1 = x0 + _quadSize;
      final z1 = z0 + _quadSize;
      final h00 = _heightAt(x, z, heightBias);
      final h10 = _heightAt(x + 1, z, heightBias);
      final h11 = _heightAt(x + 1, z + 1, heightBias);
      final h01 = _heightAt(x, z + 1, heightBias);

      vertices.addAll([
        Vertex(
          position: Vector3(x0, h00, z0),
          texCoord: Vector2(0, 0),
          normal: normal,
        ),
        Vertex(
          position: Vector3(x1, h10, z0),
          texCoord: Vector2(1, 0),
          normal: normal,
        ),
        Vertex(
          position: Vector3(x1, h11, z1),
          texCoord: Vector2(1, 1),
          normal: normal,
        ),
        Vertex(
          position: Vector3(x0, h01, z1),
          texCoord: Vector2(0, 1),
          normal: normal,
        ),
      ]);
      indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }
  }

  return Surface(
    vertices: vertices,
    indices: indices,
    material: material,
    calculateNormals: false,
  );
}

double _heightAt(int x, int z, double bias) =>
    math.sin((x + bias * 100) * 0.55) *
    math.cos((z + bias * 100) * 0.45) *
    0.035;

class FrameStats {
  const FrameStats({
    required this.emaFps,
    required this.components,
    required this.visibleDraws,
  });

  const FrameStats.initial()
    : this(emaFps: 0, components: meshCount, visibleDraws: 0);

  final double emaFps;
  final int components;
  final int visibleDraws;
}

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay({required this.game});

  final ManyMeshesGame game;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<FrameStats>(
              valueListenable: game.stats,
              builder: (context, frame, child) => DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'S3 many meshes\n'
                    'EMA FPS: ${frame.emaFps.toStringAsFixed(1)}\n'
                    'Components: ${frame.components}\n'
                    'Visible / draws: ${frame.visibleDraws}\n'
                    '1 surface x $_quadsPerSurface quads each',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
