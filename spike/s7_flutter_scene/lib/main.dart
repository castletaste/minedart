import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/chunk_upload.dart';
import 'src/frame_probe.dart';
import 'src/spawn.dart';

// Scenario knobs come from the URL query (web) so one build covers every
// run; native runs use --dart-define with the same names in upper case.
String? _query(String name) => Uri.base.queryParameters[name];

/// Render distance in chunks (minedart presets: 6 = Normal, 10 = Far).
final int kRenderDistance =
    int.tryParse(_query('rd') ?? '') ??
    const int.fromEnvironment('S7_RD', defaultValue: 10);

/// `streams` (zero-repack) or `arrays` (de-interleave + fromArrays).
final String kUploadPath =
    _query('upload') ??
    const String.fromEnvironment('S7_UPLOAD', defaultValue: 'streams');

/// Chunk passes re-uploaded per frame to model edit/remesh churn.
final int kChurnPerFrame =
    int.tryParse(_query('churn') ?? '') ??
    const int.fromEnvironment('S7_CHURN', defaultValue: 0);

/// Wall time excluded from percentiles after the first frame.
const double kWarmUpMs = 8000;

const Color kSkyColor = Color(0xFF82C8FF);
const int kSeed = 0x5eed;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SpikeHome()));
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});

  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  VoxelSpikeScene? _spike;
  Object? _error;

  @override
  void initState() {
    super.initState();
    VoxelSpikeScene.load().then(
      (spike) {
        if (mounted) setState(() => _spike = spike);
      },
      onError: (Object error, StackTrace stack) {
        logEvent('error', {'error': '$error', 'stack': '$stack'});
        if (mounted) setState(() => _error = error);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final spike = _spike;
    return Scaffold(
      backgroundColor: kSkyColor,
      body: spike == null
          ? Center(child: Text(_error == null ? 'Loading…' : 'Error: $_error'))
          : Stack(
              children: [
                Positioned.fill(
                  child: SceneView(
                    spike.scene,
                    camera: spike.camera,
                    onTick: spike.tick,
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: ValueListenableBuilder<String>(
                    valueListenable: spike.hudText,
                    builder: (context, text, _) => DecoratedBox(
                      decoration: const BoxDecoration(color: Color(0xAA000000)),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: ElevatedButton(
                    key: const ValueKey('debug-view'),
                    onPressed: spike.cycleDebugView,
                    child: const Text('Debug view'),
                  ),
                ),
              ],
            ),
    );
  }
}

final class _ChunkPass {
  _ChunkPass(this.node, this.geometry, this.vertices, this.indices);

  final Node node;
  Geometry geometry;
  final Float32List vertices;
  final Uint16List indices;
}

/// The minedart islands world (seed 0x5eed) meshed by the production mesher
/// and rendered through flutter_scene.
final class VoxelSpikeScene {
  VoxelSpikeScene._(this.scene, this.camera, this._materials, this._passes);

  final Scene scene;
  final PerspectiveCamera camera;
  final List<PreprocessedMaterial> _materials;
  final List<_ChunkPass> _passes;
  final FrameProbe probe = FrameProbe();
  final ValueNotifier<String> hudText = ValueNotifier('');
  final Stopwatch _updateWatch = Stopwatch();
  int _debugView = 0;
  int _churnCursor = 0;
  int _ticks = 0;
  double _sinceStartMs = 0;
  bool _warm = false;

  static Future<VoxelSpikeScene> load() async {
    final path = UploadPath.values.byName(kUploadPath);
    final total = Stopwatch()..start();
    await Scene.initializeStaticResources();
    final opaque = await loadFmatMaterial('assets/materials/voxel_opaque.fmat');
    final translucent = await loadFmatMaterial(
      'assets/materials/voxel_translucent.fmat',
    );
    final atlas = await _loadAtlas('data/atlas_alpha.png');
    final fog = kRenderDistance >= 10 ? (96.0, 160.0) : (48.0, 96.0);
    for (final material in [opaque, translucent]) {
      material.parameters
        ..setTexture(
          'albedo_texture',
          atlas.gpuTexture,
          sampler: gpu.SamplerOptions(),
        )
        ..setFloat('fog_start', fog.$1)
        ..setFloat('fog_end', fog.$2);
    }
    final setupMs = total.elapsedMicroseconds / 1000;

    final world = VoxelWorld();
    final genWatch = Stopwatch()..start();
    IslandsWorldGenerator(kSeed).generate(world);
    final generateMs = genWatch.elapsedMicroseconds / 1000;

    final spawn = defaultSpawn(world);
    final eye = vm.Vector3(spawn.x, spawn.y + PlayerBody.eyeHeight, spawn.z);
    // flutter_scene is left-handed (view +Z into the screen) while the
    // minedart world is right-handed, so the world hangs under a Z mirror.
    // The engine reverses winding for negative-determinant nodes. The camera
    // lives in engine space: mirror the eye and look along +Z instead of -Z.
    final engineEye = vm.Vector3(eye.x, eye.y, -eye.z);
    final camera = PerspectiveCamera(
      fovRadiansY: 70 * vm.degrees2Radians,
      position: engineEye,
      target: engineEye + vm.Vector3(0, 0, 1),
      fovNear: 0.01,
      fovFar: 1000,
    );

    final scene = Scene()
      ..antiAliasingMode = AntiAliasingMode.none
      ..toneMapping = ToneMappingMode.linear
      ..exposure = 1
      ..fitNearPlane = false
      ..debugCheckCoplanarOverlaps = false;
    final worldRoot = Node(
      name: 'minedart world',
      localTransform: vm.Matrix4.diagonal3Values(1, 1, -1),
    );
    scene.add(worldRoot);

    const mesher = ChunkMesher();
    final meshWatch = Stopwatch();
    final uploadWatch = Stopwatch();
    final uploadSamples = SampleRing(4096);
    final passes = <_ChunkPass>[];
    var meshBytes = 0;
    final viewCx = (eye.x ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksX - 1,
    );
    final viewCz = (eye.z ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksZ - 1,
    );
    var visibleChunks = 0;
    for (var cy = 0; cy < WorldDims.worldChunksY; cy++) {
      for (var cz = 0; cz < WorldDims.worldChunksZ; cz++) {
        for (var cx = 0; cx < WorldDims.worldChunksX; cx++) {
          meshWatch.start();
          final data = mesher.mesh(ChunkSnapshot.capture(world, cx, cy, cz));
          meshWatch.stop();
          final inRange =
              (cx - viewCx).abs() <= kRenderDistance &&
              (cz - viewCz).abs() <= kRenderDistance;
          if (inRange) visibleChunks++;
          for (final (vertices, indices, material) in [
            (data.opaqueVertices, data.opaqueIndices, opaque),
            (data.translucentVertices, data.translucentIndices, translucent),
          ]) {
            if (indices.isEmpty) continue;
            meshBytes += vertices.lengthInBytes + indices.lengthInBytes;
            final one = Stopwatch()..start();
            uploadWatch.start();
            final geometry = createChunkGeometry(path, vertices, indices);
            final node = Node(
              name: 'chunk $cx,$cy,$cz',
              localTransform: vm.Matrix4.translationValues(
                cx * WorldDims.chunkSize.toDouble(),
                cy * WorldDims.chunkSize.toDouble(),
                cz * WorldDims.chunkSize.toDouble(),
              ),
              mesh: Mesh(geometry, material),
            )..visible = inRange;
            worldRoot.add(node);
            uploadWatch.stop();
            uploadSamples.add(one.elapsedMicroseconds / 1000);
            passes.add(_ChunkPass(node, geometry, vertices, indices));
          }
        }
      }
    }
    final upload = uploadSamples.percentiles(const [0.5, 0.95, 0.99, 1]);
    logEvent('load', {
      'path': path.name,
      'renderDistance': kRenderDistance,
      'setupMs': setupMs,
      'generateMs': generateMs,
      'meshAllChunksMs': meshWatch.elapsedMicroseconds / 1000,
      'uploadAllMs': uploadWatch.elapsedMicroseconds / 1000,
      'uploadPerPassMs p50/p95/p99/max': upload
          .map((v) => v.toStringAsFixed(3))
          .join('/'),
      'passes': passes.length,
      'visibleChunks': visibleChunks,
      'meshBytes': meshBytes,
      'eye': [eye.x, eye.y, eye.z],
    });
    return VoxelSpikeScene._(scene, camera, [opaque, translucent], passes);
  }

  void tick(Duration elapsed, double deltaSeconds) {
    _updateWatch
      ..reset()
      ..start();
    if (kChurnPerFrame > 0 && _warm) _churn();
    _updateWatch.stop();
    final stats = scene.renderStats.latest;
    if (stats != null) {
      probe
        ..draws = stats.counters.draws
        ..culled = stats.counters.culled
        ..submitted = stats.counters.submitted
        ..paced = scene.pacedFrameCount;
    }
    // The first seconds compile pipelines and build the BVH; keep them out of
    // the steady-state percentiles.
    _ticks++;
    _sinceStartMs += deltaSeconds * 1000;
    if (!_warm && _sinceStartMs >= kWarmUpMs) {
      _warm = true;
      probe
        ..wall.clear()
        ..cpuRender.clear()
        ..update.clear();
      logEvent('ready', {'ticks': _ticks});
    }
    probe.record(
      wallMs: deltaSeconds * 1000,
      cpuRenderMs: (stats?.cpuMicros ?? 0) / 1000,
      updateMs: _updateWatch.elapsedMicroseconds / 1000,
    );
    if (_ticks % 30 == 0) {
      hudText.value =
          'flutter_scene $kUploadPath RD $kRenderDistance\n'
          'frame ${(deltaSeconds * 1000).toStringAsFixed(1)} ms\n'
          'cpu render ${((stats?.cpuMicros ?? 0) / 1000).toStringAsFixed(2)} ms\n'
          'draws ${probe.draws} culled ${probe.culled}\n'
          'debug view $_debugView';
    }
  }

  void _churn() {
    for (var i = 0; i < kChurnPerFrame; i++) {
      final pass = _passes[_churnCursor];
      _churnCursor = (_churnCursor + 1) % _passes.length;
      final geometry = pass.geometry;
      if (geometry is UnskinnedGeometry && geometry is! MeshGeometry) {
        uploadChunkStreams(geometry, pass.vertices, pass.indices);
      } else {
        final material = pass.node.mesh!.primitives.first.material;
        pass.geometry = createChunkGeometry(
          UploadPath.arrays,
          pass.vertices,
          pass.indices,
        );
        pass.node.mesh = Mesh(pass.geometry, material);
      }
    }
  }

  void cycleDebugView() {
    _debugView = (_debugView + 1) % 7;
    for (final material in _materials) {
      material.parameters.setInt('debug_view', _debugView);
    }
    logEvent('hud_tap', {'debugView': _debugView});
  }
}

Future<Texture2D> _loadAtlas(String asset) async {
  final bytes = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final image = (await codec.getNextFrame()).image;
  final rgba = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final texture = Texture2D.fromPixels(
    rgba!.buffer.asUint8List(),
    image.width,
    image.height,
    sampling: const TextureSampling(
      mipmaps: false,
      minFilter: gpu.MinMagFilter.nearest,
      magFilter: gpu.MinMagFilter.nearest,
      mipFilter: gpu.MipFilter.nearest,
    ),
  );
  image.dispose();
  return texture;
}
