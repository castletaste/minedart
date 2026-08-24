import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/player_input_mapper.dart';

void main() {
  test(
    'default camera maps forward to negative Z and strafe to positive X',
    () {
      final input = PlayerInputMapper.fromCameraAxes(
        yaw: 0,
        forward: 1,
        strafe: 1,
        jump: true,
        sprint: true,
      );

      expect(input.moveX, closeTo(1, 1e-12));
      expect(input.moveZ, closeTo(-1, 1e-12));
      expect(input.jump, isTrue);
      expect(input.sprint, isTrue);
    },
  );

  test('positive quarter-turn yaw rotates forward toward negative X', () {
    final input = PlayerInputMapper.fromCameraAxes(
      yaw: math.pi / 2,
      forward: 1,
      strafe: 0,
      jump: false,
      sprint: false,
    );

    expect(input.moveX, closeTo(-1, 1e-12));
    expect(input.moveZ, closeTo(0, 1e-12));
  });

  test('opposite movement keys cancel before mapping', () {
    final input = PlayerInputMapper.fromCameraAxes(
      yaw: 1.2,
      forward: 0,
      strafe: 0,
      jump: false,
      sprint: false,
    );

    expect(input.moveX, 0);
    expect(input.moveZ, 0);
  });
}
