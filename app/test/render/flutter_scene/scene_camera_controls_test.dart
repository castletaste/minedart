import 'package:flame_3d/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/render/flame3d/flame3d_voxel_renderer.dart';
import 'package:minedart/render/flutter_scene/scene_voxel_renderer.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('look direction matches flame_3d for every yaw and pitch', () {
    final flame = Flame3dCameraControls(CameraComponent3D());
    final scene = SceneCameraControls(eye: Vector3.zero(), fovY: 70);
    final expected = Vector3.zero();
    final actual = Vector3.zero();
    for (final yaw in [0.0, 0.4, 1.7, 3.1, 5.9]) {
      for (final pitch in [-1.5, -0.3, 0.0, 0.8, 1.5]) {
        flame.setOrientation(yaw, pitch);
        scene.setOrientation(yaw, pitch);
        flame.lookDirectionInto(expected);
        scene.lookDirectionInto(actual);
        expect(
          actual.distanceTo(expected),
          lessThan(1e-6),
          reason: 'yaw $yaw pitch $pitch',
        );
      }
    }
  });

  test('sync mirrors the followed eye and look target across Z', () {
    final eye = Vector3(10, 40, 20);
    final controls = SceneCameraControls(eye: eye, fovY: 70)
      ..setOrientation(0, 0)
      ..sync();
    expect(controls.camera.position, Vector3(10, 40, -20));
    expect(controls.camera.target, Vector3(10, 40, -19));
    expect(controls.camera.fovRadiansY, closeTo(70 * degrees2Radians, 1e-6));

    eye.setValues(1, 2, 3);
    controls
      ..fovY = 88
      ..sync();
    expect(controls.camera.position, Vector3(1, 2, -3));
    expect(controls.camera.fovRadiansY, closeTo(88 * degrees2Radians, 1e-6));
  });
}
