// S5 spike: web / WebGPU reality check for flame_3d 0.3.0.
//
// Scene copied from spike/base_app/lib/main.dart (rotating camera + cube),
// plus a Flutter HUD layer stacked over the GameWidget to check whether
// Flutter widgets composite over the 3D output on the web.
import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Material;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On web this performs async WebGPU adapter/device acquisition and loads
  // every *.wgslbundle asset. It throws UnsupportedError when the browser has
  // no navigator.gpu, so we surface that on screen instead of a blank canvas.
  String? initError;
  try {
    await GpuBackend.initialize();
  } catch (e) {
    initError = '$e';
  }

  runApp(S5App(initError: initError));
}

class S5App extends StatelessWidget {
  const S5App({super.key, this.initError});

  final String? initError;

  @override
  Widget build(BuildContext context) {
    final error = initError;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: error != null
            ? _InitFailure(message: error)
            : const _GameWithHud(),
      ),
    );
  }
}

class _InitFailure extends StatelessWidget {
  const _InitFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'GpuBackend.initialize() failed:\n\n$message',
          style: const TextStyle(color: Colors.redAccent, fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// GameWidget with a Flutter widget HUD stacked on top of it.
///
/// If the HUD renders above the cube, Flutter widgets and the 3D output share
/// one composited scene.
class _GameWithHud extends StatefulWidget {
  const _GameWithHud();

  @override
  State<_GameWithHud> createState() => _GameWithHudState();
}

class _GameWithHudState extends State<_GameWithHud> {
  late final SpikeGame _game = SpikeGame();
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GameWidget(game: _game)),
        // Pure Flutter widgets layered over the 3D scene.
        Positioned(
          left: 16,
          top: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'S5 HUD (Flutter widget layer)',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  'kIsWeb = $kIsWeb',
                  style: const TextStyle(color: Colors.greenAccent),
                ),
                Text(
                  'HUD button taps: $_taps',
                  style: const TextStyle(color: Colors.amberAccent),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ElevatedButton(
            onPressed: () => setState(() => _taps++),
            child: const Text('HUD button (hit-test check)'),
          ),
        ),
      ],
    );
  }
}

class SpikeGame extends FlameGame3D {
  SpikeGame()
    : super(
        camera: CameraComponent3D(
          position: Vector3(3, 3, 6),
          target: Vector3(0, 0, 0),
        ),
      );

  double _t = 0;

  @override
  Future<void> onLoad() async {
    world.addAll([
      LightComponent.ambient(intensity: 0.8),
      MeshComponent(
        mesh: CuboidMesh(
          size: Vector3.all(1),
          material: SpatialMaterial(albedoColor: const Color(0xFF44AA44)),
        ),
      ),
    ]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    camera.position = Vector3(6 * math.cos(_t * 0.5), 3, 6 * math.sin(_t * 0.5));
  }
}
