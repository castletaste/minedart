import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:spike_s2_shader/voxel_material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GpuBackend.initialize();
  runApp(GameWidget.controlled(gameFactory: SpikeS2Game.new));
}

class SpikeS2Game extends FlameGame3D {
  SpikeS2Game()
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
      LightComponent.ambient(intensity: 1.0),
      MeshComponent(mesh: _buildAoCubeMesh()),
      // Reference cube with the stock material to compare side by side:
      MeshComponent(
        mesh: CuboidMesh(
          size: Vector3.all(1),
          material: UnlitMaterial(albedoColor: const Color(0xFF44AA44)),
        ),
        position: Vector3(2.0, 0, 0),
      ),
    ]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    camera.position = Vector3(
      6 * math.cos(_t * 0.4),
      3,
      6 * math.sin(_t * 0.4),
    );
  }
}

/// Cube where each face has its own 4 vertices; corner vertices are darkened
/// to imitate baked ambient occlusion. Face color: white -> texture shows,
/// dark corners -> AO.
Mesh _buildAoCubeMesh() {
  final mesh = Mesh();
  final material = VoxelMaterial();

  // AO per cube corner (0..7), simulating darker lower corners.
  // Corner index bits: x + y*2 + z*4 (0 = min, 1 = max).
  const cornerAo = [0.25, 0.55, 1.0, 0.85, 0.55, 0.25, 0.85, 1.0];

  Color aoColor(double ao) {
    final v = (ao * 255).round();
    return Color.fromARGB(255, v, v, v);
  }

  const h = 0.5;
  // 8 cube corners:
  final corners = [
    Vector3(-h, -h, -h), // 0
    Vector3(h, -h, -h), // 1
    Vector3(-h, h, -h), // 2
    Vector3(h, h, -h), // 3
    Vector3(-h, -h, h), // 4
    Vector3(h, -h, h), // 5
    Vector3(-h, h, h), // 6
    Vector3(h, h, h), // 7
  ];

  // Each face: 4 corner indices (CCW seen from outside) + normal.
  final faces = <(List<int>, Vector3)>[
    ([4, 5, 7, 6], Vector3(0, 0, 1)), // front (+z)
    ([1, 0, 2, 3], Vector3(0, 0, -1)), // back (-z)
    ([5, 1, 3, 7], Vector3(1, 0, 0)), // right (+x)
    ([0, 4, 6, 2], Vector3(-1, 0, 0)), // left (-x)
    ([6, 7, 3, 2], Vector3(0, 1, 0)), // top (+y)
    ([0, 1, 5, 4], Vector3(0, -1, 0)), // bottom (-y)
  ];

  final uv = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)];

  final vertices = <Vertex>[];
  final indices = <int>[];
  for (final (cornerIdx, normal) in faces) {
    final base = vertices.length;
    for (var i = 0; i < 4; i++) {
      final c = cornerIdx[i];
      vertices.add(
        Vertex(
          position: corners[c],
          texCoord: uv[i],
          normal: normal,
          color: aoColor(cornerAo[c]),
        ),
      );
    }
    indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  mesh.addSurface(
    Surface(
      vertices: vertices,
      indices: indices,
      material: material,
      calculateNormals: false,
    ),
  );
  return mesh;
}
