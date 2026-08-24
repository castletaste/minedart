/// Player collision body and kinematic state.
library;

import 'package:vector_math/vector_math.dart';

import 'aabb.dart';

final class PlayerBody {
  PlayerBody({Vector3? position, Vector3? velocity, this.onGround = false})
    : position = position ?? Vector3.zero(),
      velocity = velocity ?? Vector3.zero();

  static const double width = 0.6;
  static const double height = 1.8;
  static const double halfWidth = width / 2;
  static const double eyeHeight = 1.62;

  /// Feet position: horizontally centered at (x,z), with y at the sole.
  final Vector3 position;
  final Vector3 velocity;
  bool onGround;

  void writeAabb(Aabb out) {
    out.setValues(
      position.x - halfWidth,
      position.y,
      position.z - halfWidth,
      position.x + halfWidth,
      position.y + height,
      position.z + halfWidth,
    );
  }

  void writeEyePosition(Vector3 out) {
    out.setValues(position.x, position.y + eyeHeight, position.z);
  }
}
