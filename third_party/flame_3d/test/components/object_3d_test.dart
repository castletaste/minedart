import 'dart:ui';

import 'package:flame/extensions.dart';
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/graphics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('child exception restores ancestor culling state', () {
    final camera = CameraComponent3D(
      position: Vector3.zero(),
      target: Vector3(0, 0, -1),
      viewport: FixedResolutionViewport(resolution: Vector2(1920, 1080)),
    );
    final canvas = Canvas(PictureRecorder());
    final inside = _BoundsObject(
      Aabb3.minMax(Vector3(-0.1, -0.1, -5.1), Vector3(0.1, 0.1, -5)),
      children: [_ThrowingComponent()],
    );
    final outside = _BoundsObject(
      Aabb3.minMax(Vector3(100, 100, -5), Vector3(101, 101, -4)),
    );

    CameraComponent.currentCameras.add(camera);
    try {
      expect(() => inside.renderTree(canvas), throwsStateError);
      expect(() => outside.renderTree(canvas), returnsNormally);
    } finally {
      CameraComponent.currentCameras.removeLast();
    }
  });
}

final class _BoundsObject extends Object3D {
  _BoundsObject(this.bounds, {super.children});

  final Aabb3 bounds;

  @override
  Aabb3 computeLocalAabb() => bounds;

  @override
  void draw(RenderContext context) {}
}

final class _ThrowingComponent extends Component3D {
  @override
  void renderTree(Canvas canvas) {
    throw StateError('synthetic child render failure');
  }
}
