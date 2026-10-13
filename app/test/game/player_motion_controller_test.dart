import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/game/player_motion_controller.dart';
import 'package:minedart/input/game_bindings.dart';
import 'package:minedart/input/touch_input_state.dart';
import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('camera look consumes mouse deltas and clamps pitch', () {
    final player = PlayerMotionController(
      world: VoxelWorld(),
      initialFeet: Vector3(8.5, 4, 8.5),
    );

    player.addMouseDelta(10, -20);

    expect(player.updateLook(0, TouchInputFrame.zero), isTrue);
    expect(player.yaw, closeTo(math.pi * 2 - 0.04, 1e-10));
    expect(player.pitch, closeTo(0.08, 1e-10));
    expect(player.updateLook(0, TouchInputFrame.zero), isFalse);
  });

  test('noclip movement follows the camera and saved spawn restores feet', () {
    final player = PlayerMotionController(
      world: VoxelWorld(),
      initialFeet: Vector3(8.5, 4, 8.5),
    )..toggleNoclip();
    final initialEye = player.eyePosition.clone();

    player.keys.add(GameBindings.defaults[GameControl.moveForward]!);
    player.updateMovement(0.25, TouchInputFrame.zero);
    expect(player.eyePosition.z, lessThan(initialEye.z));

    player.setSpawnAtPlayer();
    final savedFeet = player.spawnFeet.clone();
    player.updateMovement(0.25, TouchInputFrame.zero);
    player.respawnAtSavedPoint();

    expect(player.body.position.x, closeTo(savedFeet.x, 1e-6));
    expect(player.body.position.y, closeTo(savedFeet.y, 1e-6));
    expect(player.body.position.z, closeTo(savedFeet.z, 1e-6));
    expect(player.eyePosition.x, closeTo(savedFeet.x, 1e-6));
    expect(
      player.eyePosition.y,
      closeTo(savedFeet.y + PlayerBody.eyeHeight, 1e-6),
    );
    expect(player.eyePosition.z, closeTo(savedFeet.z, 1e-6));
  });
}
