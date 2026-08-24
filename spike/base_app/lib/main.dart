import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/material.dart' hide Material;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GpuBackend.initialize();
  runApp(GameWidget.controlled(gameFactory: SpikeGame.new));
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
