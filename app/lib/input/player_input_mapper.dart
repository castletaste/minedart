import 'dart:math' as math;

import 'package:minedart_core/minedart_core.dart';

/// Maps camera-local WASD axes to the world-space axes used by [PhysicsSim].
abstract final class PlayerInputMapper {
  static PlayerInput fromCameraAxes({
    required double yaw,
    required double forward,
    required double strafe,
    required bool jump,
    required bool sprint,
  }) {
    final sinYaw = math.sin(yaw);
    final cosYaw = math.cos(yaw);
    return PlayerInput(
      moveX: -forward * sinYaw + strafe * cosYaw,
      moveZ: -forward * cosYaw - strafe * sinYaw,
      jump: jump,
      sprint: sprint,
    );
  }
}
