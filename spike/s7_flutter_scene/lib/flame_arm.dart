// Control arm: the same static scene rendered through the production
// flame_3d path (PackedSurface + VoxelMaterial/WebVoxelMaterial), with the
// same FrameProbe output. Build with `-t lib/flame_arm.dart`.

import 'package:flame/game.dart';
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:minedart_core/minedart_core.dart';

import 'flame_arm/packed_surface.dart';
import 'flame_arm/voxel_material.dart';
import 'main.dart' show kRenderDistance, kSeed, kSkyColor, kWarmUpMs;
import 'src/frame_probe.dart';
import 'src/spawn.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GpuBackend.initialize();
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: kSkyColor,
        body: GameWidget(game: FlameArmGame()),
      ),
    ),
  );
}

final class FlameArmGame extends FlameGame3D<World3D, CameraComponent3D> {
  FlameArmGame() : super(camera: CameraComponent3D(fovY: 70));

  final FrameProbe probe = FrameProbe();
  final Stopwatch _renderWatch = Stopwatch();
  final Stopwatch _updateWatch = Stopwatch();
  double _lastRenderMs = 0;
  double _lastUpdateMs = 0;
  double _sinceStartMs = 0;
  bool _warm = false;
  bool _ready = false;

  @override
  Color backgroundColor() => kSkyColor;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final total = Stopwatch()..start();
    images.prefix = 'data/';
    final atlas = await images.loadTexture('atlas_alpha.png');
    final Material material;
    final fog = kRenderDistance >= 10 ? (96.0, 160.0) : (48.0, 96.0);
    if (kIsWeb) {
      material = WebVoxelMaterial(albedoTexture: atlas)
        ..setFogRange(fog.$1, fog.$2);
    } else {
      material = VoxelMaterial(albedoTexture: atlas)
        ..setFogRange(fog.$1, fog.$2);
    }
    final setupMs = total.elapsedMicroseconds / 1000;

    final voxelWorld = VoxelWorld();
    final genWatch = Stopwatch()..start();
    IslandsWorldGenerator(kSeed).generate(voxelWorld);
    final generateMs = genWatch.elapsedMicroseconds / 1000;
    final spawn = defaultSpawn(voxelWorld);
    final eye = Vector3(spawn.x, spawn.y + PlayerBody.eyeHeight, spawn.z);
    camera
      ..position.setFrom(eye)
      ..target.setFrom(eye + Vector3(0, 0, -1));

    const mesher = ChunkMesher();
    final meshWatch = Stopwatch();
    final uploadWatch = Stopwatch();
    final uploadSamples = SampleRing(4096);
    var passes = 0;
    var meshBytes = 0;
    final extent = WorldDims.chunkSize.toDouble();
    for (var cy = 0; cy < WorldDims.worldChunksY; cy++) {
      for (var cz = 0; cz < WorldDims.worldChunksZ; cz++) {
        for (var cx = 0; cx < WorldDims.worldChunksX; cx++) {
          meshWatch.start();
          final data = mesher.mesh(
            ChunkSnapshot.capture(voxelWorld, cx, cy, cz),
          );
          meshWatch.stop();
          for (final (vertices, indices) in [
            (data.opaqueVertices, data.opaqueIndices),
            (data.translucentVertices, data.translucentIndices),
          ]) {
            if (indices.isEmpty) continue;
            meshBytes += vertices.lengthInBytes + indices.lengthInBytes;
            final one = Stopwatch()..start();
            uploadWatch.start();
            final mesh = Mesh()
              ..addSurface(
                PackedSurface(
                  vertices: vertices,
                  indices: indices,
                  material: material,
                  aabb: Aabb3.minMax(Vector3.zero(), Vector3.all(extent)),
                ),
              );
            world.add(
              MeshComponent(
                mesh: mesh,
                position: Vector3(cx * extent, cy * extent, cz * extent),
              ),
            );
            uploadWatch.stop();
            uploadSamples.add(one.elapsedMicroseconds / 1000);
            passes++;
          }
        }
      }
    }
    final upload = uploadSamples.percentiles(const [0.5, 0.95, 0.99, 1]);
    logEvent('load', {
      'path': 'flame_3d',
      'renderDistance': kRenderDistance,
      'setupMs': setupMs,
      'generateMs': generateMs,
      'meshAllChunksMs': meshWatch.elapsedMicroseconds / 1000,
      // flame_3d creates GPU buffers lazily on the first draw, so this is
      // component construction only; the upload lands in the first frames.
      'uploadAllMs': uploadWatch.elapsedMicroseconds / 1000,
      'uploadPerPassMs p50/p95/p99/max': upload
          .map((v) => v.toStringAsFixed(3))
          .join('/'),
      'passes': passes,
      'meshBytes': meshBytes,
      'eye': [eye.x, eye.y, eye.z],
    });
    _ready = true;
  }

  @override
  void update(double dt) {
    _updateWatch
      ..reset()
      ..start();
    super.update(dt);
    _updateWatch.stop();
    _lastUpdateMs = _updateWatch.elapsedMicroseconds / 1000;
    if (!_ready) return;
    _sinceStartMs += dt * 1000;
    if (!_warm && _sinceStartMs >= kWarmUpMs) {
      _warm = true;
      probe
        ..wall.clear()
        ..cpuRender.clear()
        ..update.clear();
      logEvent('ready', {});
    }
    probe
      ..draws = world.context.drawCount
      ..record(
        wallMs: dt * 1000,
        cpuRenderMs: _lastRenderMs,
        updateMs: _lastUpdateMs,
      );
  }

  @override
  void render(Canvas canvas) {
    _renderWatch
      ..reset()
      ..start();
    super.render(canvas);
    _renderWatch.stop();
    _lastRenderMs = _renderWatch.elapsedMicroseconds / 1000;
  }
}
