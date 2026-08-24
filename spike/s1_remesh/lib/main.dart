import 'package:flame/game.dart' show GameWidget;
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/material.dart' as flutter;

import 'src/chunk_mesher.dart';
import 'src/flame_benchmark.dart';

Future<void> main() async {
  flutter.WidgetsFlutterBinding.ensureInitialized();
  await GpuBackend.initialize();
  final result = flameBenchmarkJson();
  print('S1_FLAME_BENCHMARK_BEGIN');
  print(result);
  print('S1_FLAME_BENCHMARK_END');
  flutter.runApp(BenchmarkResultApp(result: result));
}

class BenchmarkResultApp extends flutter.StatelessWidget {
  const BenchmarkResultApp({required this.result, super.key});

  final String result;

  @override
  flutter.Widget build(flutter.BuildContext context) => flutter.MaterialApp(
    theme: flutter.ThemeData.dark(),
    home: flutter.Scaffold(
      appBar: flutter.AppBar(
        title: const flutter.Text('S1 packed chunk: render + benchmark'),
      ),
      body: flutter.Row(
        children: [
          flutter.Expanded(
            child: GameWidget.controlled(gameFactory: PackedChunkGame.new),
          ),
          flutter.SizedBox(
            width: 460,
            child: flutter.SingleChildScrollView(
              padding: const flutter.EdgeInsets.all(16),
              child: flutter.SelectableText(result),
            ),
          ),
        ],
      ),
    ),
  );
}

class PackedChunkGame extends FlameGame3D {
  PackedChunkGame()
    : super(
        camera: CameraComponent3D(
          position: Vector3(25, 22, 28),
          target: Vector3(8, 8, 8),
        ),
      );

  @override
  Future<void> onLoad() async {
    final mesh = Mesh()
      ..addSurface(
        PackedSurface(
          meshChunk(makeBenchmarkChunk()),
          material: SpatialMaterial(
            albedoColor: const flutter.Color(0xff55aa55),
          ),
        ),
      );
    world.addAll([
      LightComponent.ambient(intensity: 0.9),
      MeshComponent(mesh: mesh),
    ]);
  }
}
