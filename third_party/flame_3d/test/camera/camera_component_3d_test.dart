import 'package:flame/extensions.dart';
import 'package:flame_3d/camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraComponent3D frustum cache', () {
    test('refreshes outside render scope after camera changes', () {
      final camera = _CountingCamera();

      camera.frustum;
      camera.position.x = 4;
      camera.frustum;

      expect(camera.frustumUpdates, 2);
    });

    test('reuses one value per render scope and refreshes between frames', () {
      final camera = _CountingCamera();

      camera.withFrustumCacheForRender(() {
        camera
          ..frustum
          ..frustum;
      });
      expect(camera.frustumUpdates, 1);

      camera.position.x = 4;
      camera.withFrustumCacheForRender(() {
        camera
          ..frustum
          ..frustum;
      });
      expect(camera.frustumUpdates, 2);
    });

    test('render exception resets cache scope', () {
      final camera = _CountingCamera();

      expect(
        () => camera.withFrustumCacheForRender(() {
          camera.frustum;
          throw StateError('synthetic render failure');
        }),
        throwsStateError,
      );
      expect(camera.frustumUpdates, 1);

      camera.position.x = 4;
      camera.frustum;
      camera.withFrustumCacheForRender(() => camera.frustum);

      expect(camera.frustumUpdates, 3);
    });
  });
}

final class _CountingCamera extends CameraComponent3D {
  _CountingCamera()
    : super(
        position: Vector3.zero(),
        target: Vector3(0, 0, -1),
        viewport: FixedResolutionViewport(resolution: Vector2(1920, 1080)),
      );

  int frustumUpdates = 0;

  @override
  Matrix4 get viewProjectionMatrix {
    frustumUpdates++;
    return super.viewProjectionMatrix;
  }
}
