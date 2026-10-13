import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart';

import '../audio/footstep_cadence.dart';
import '../input/double_tap_sprint_detector.dart';
import '../input/game_bindings.dart';
import '../input/player_input_mapper.dart';
import '../input/touch_input_state.dart';

typedef PlayerFootstepObserver = void Function(int blockId, int seed);

/// Owns player input state, camera angles, and first-person movement.
///
/// Flame remains responsible for the camera component and frame scheduling;
/// this controller keeps movement rules independent from rendering and HUD
/// wiring.
final class PlayerMotionController {
  PlayerMotionController({
    required VoxelWorld world,
    required Vector3 initialFeet,
    this.onFootstep,
    double initialYaw = 0,
    double initialPitch = 0,
  }) : voxelWorld = world,
       body = PlayerBody(position: initialFeet.clone()),
       eyePosition = Vector3.zero(),
       spawnFeet = initialFeet.clone(),
       _yaw = initialYaw,
       _pitch = initialPitch {
    body.writeEyePosition(eyePosition);
  }

  static const noclipSpeed = 24.0;
  static const keyboardLookSpeed = 1.35;
  static const defaultMouseSensitivity = 0.004;
  static const pitchLimit = 89 * math.pi / 180;

  final VoxelWorld voxelWorld;
  final PlayerBody body;
  final Vector3 eyePosition;
  final Vector3 spawnFeet;
  final PhysicsSim physics = PhysicsSim();
  final DoubleTapSprintDetector sprintDetector = DoubleTapSprintDetector();
  final FootstepCadence footstepCadence = FootstepCadence();
  final TouchInputState touchInput = TouchInputState();
  PlayerFootstepObserver? onFootstep;

  final Set<LogicalKeyboardKey> keys = <LogicalKeyboardKey>{};
  GameBindings _bindings = GameBindings();
  double _mouseSensitivity = defaultMouseSensitivity;
  bool _invertMouseY = false;
  int _footstepSerial = 0;
  double _pendingMouseDx = 0;
  double _pendingMouseDy = 0;
  double _yaw;
  double _pitch;
  bool _noclip = false;

  double get yaw => _yaw;
  double get pitch => _pitch;
  bool get noclip => _noclip;
  bool get isSprinting => sprintDetector.isSprinting || touchInput.sprintHeld;
  bool get hasPendingLook => _pendingMouseDx != 0 || _pendingMouseDy != 0;
  bool get hasInteractiveKeyInput =>
      keys.contains(_bindings[GameControl.moveForward]) ||
      keys.contains(_bindings[GameControl.moveBackward]) ||
      keys.contains(_bindings[GameControl.strafeLeft]) ||
      keys.contains(_bindings[GameControl.strafeRight]) ||
      keys.contains(_bindings[GameControl.jump]) ||
      keys.contains(LogicalKeyboardKey.arrowLeft) ||
      keys.contains(LogicalKeyboardKey.arrowRight) ||
      keys.contains(LogicalKeyboardKey.arrowUp) ||
      keys.contains(LogicalKeyboardKey.arrowDown);

  LogicalKeyboardKey binding(GameControl control) => _bindings[control];

  void setBindings(GameBindings value) {
    _bindings = value.copy();
    keys.clear();
    sprintDetector.reset();
  }

  void setMouseOptions({required double sensitivity, required bool invertY}) {
    _mouseSensitivity = sensitivity.clamp(0.0005, 0.02);
    _invertMouseY = invertY;
  }

  void clearInput() {
    keys.clear();
    _pendingMouseDx = 0;
    _pendingMouseDy = 0;
    touchInput.reset();
    sprintDetector.reset();
  }

  bool isMovementKey(LogicalKeyboardKey key) =>
      key == _bindings[GameControl.moveForward] ||
      key == _bindings[GameControl.moveBackward] ||
      key == _bindings[GameControl.strafeLeft] ||
      key == _bindings[GameControl.strafeRight] ||
      key == _bindings[GameControl.jump];

  void updateKeyState(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event.logicalKey == _bindings[GameControl.moveForward]) {
      if (event is KeyRepeatEvent) {
        sprintDetector.forwardDown(event.timeStamp, isRepeat: true);
      } else if (event is KeyDownEvent) {
        sprintDetector.forwardDown(
          event.timeStamp,
          isRepeat: event.synthesized,
        );
      } else if (event is KeyUpEvent) {
        sprintDetector.forwardUp();
      }
    }
    keys
      ..clear()
      ..addAll(keysPressed);
  }

  void addMouseDelta(double dx, double dy) {
    _pendingMouseDx += dx;
    _pendingMouseDy += dy;
  }

  TouchInputFrame consumeTouchFrame() => touchInput.consumeFrame();

  /// Updates the camera angles and returns whether the camera changed.
  bool updateLook(double dt, TouchInputFrame touch) {
    var yawDelta = -(_pendingMouseDx + touch.lookDx) * _mouseSensitivity;
    var pitchDelta =
        (_invertMouseY ? 1 : -1) *
        (_pendingMouseDy + touch.lookDy) *
        _mouseSensitivity;
    _pendingMouseDx = 0;
    _pendingMouseDy = 0;

    if (keys.contains(LogicalKeyboardKey.arrowLeft)) {
      yawDelta += keyboardLookSpeed * dt;
    }
    if (keys.contains(LogicalKeyboardKey.arrowRight)) {
      yawDelta -= keyboardLookSpeed * dt;
    }
    if (keys.contains(LogicalKeyboardKey.arrowUp)) {
      pitchDelta += keyboardLookSpeed * dt;
    }
    if (keys.contains(LogicalKeyboardKey.arrowDown)) {
      pitchDelta -= keyboardLookSpeed * dt;
    }
    if (yawDelta == 0 && pitchDelta == 0) return false;

    _yaw = (_yaw + yawDelta) % (math.pi * 2);
    _pitch = (_pitch + pitchDelta).clamp(-pitchLimit, pitchLimit);
    return true;
  }

  void updateMovement(double dt, TouchInputFrame touch) {
    if (_noclip) {
      _updateNoclip(dt, touch);
    } else {
      _updatePhysics(dt, touch);
    }
  }

  void toggleNoclip() {
    _noclip = !_noclip;
    footstepCadence.reset();
    body.velocity.setZero();
    body.onGround = false;
    if (_noclip) {
      body.writeEyePosition(eyePosition);
    } else {
      body.position.setValues(
        eyePosition.x,
        eyePosition.y - PlayerBody.eyeHeight,
        eyePosition.z,
      );
    }
  }

  void setSpawnAtPlayer() {
    if (_noclip) {
      spawnFeet.setValues(
        eyePosition.x,
        eyePosition.y - PlayerBody.eyeHeight,
        eyePosition.z,
      );
    } else {
      spawnFeet.setFrom(body.position);
    }
  }

  void respawnAtSavedPoint() {
    footstepCadence.reset();
    body.position.setFrom(spawnFeet);
    body.velocity.setZero();
    body.onGround = false;
    body.writeEyePosition(eyePosition);
  }

  double axis(LogicalKeyboardKey positive, LogicalKeyboardKey negative) =>
      (keys.contains(positive) ? 1.0 : 0.0) -
      (keys.contains(negative) ? 1.0 : 0.0);

  void _updatePhysics(double dt, TouchInputFrame touch) {
    final input = PlayerInputMapper.fromCameraAxes(
      yaw: _yaw,
      forward:
          (axis(
                    _bindings[GameControl.moveForward],
                    _bindings[GameControl.moveBackward],
                  ) +
                  touch.forward)
              .clamp(-1.0, 1.0),
      strafe:
          (axis(
                    _bindings[GameControl.strafeRight],
                    _bindings[GameControl.strafeLeft],
                  ) +
                  touch.strafe)
              .clamp(-1.0, 1.0),
      jump:
          keys.contains(_bindings[GameControl.jump]) ||
          touch.jumpHeld ||
          touch.jumpRequested,
      sprint: sprintDetector.isSprinting || touch.sprintHeld,
    );
    final previousX = body.position.x;
    final previousZ = body.position.z;
    final physicsSteps = physics.advance(voxelWorld, body, input, dt);
    if (physicsSteps > 0) touchInput.acknowledgeJumpRequest();

    final movedX = body.position.x - previousX;
    final movedZ = body.position.z - previousZ;
    if (footstepCadence.update(
      horizontalDistance: math.sqrt(movedX * movedX + movedZ * movedZ),
      grounded: body.onGround,
      sprinting: isSprinting,
    )) {
      _emitFootstep();
    }
    body.writeEyePosition(eyePosition);
  }

  void _updateNoclip(double dt, TouchInputFrame touch) {
    touchInput.acknowledgeJumpRequest();
    final forwardAxis =
        (axis(
                  _bindings[GameControl.moveForward],
                  _bindings[GameControl.moveBackward],
                ) +
                touch.forward)
            .clamp(-1.0, 1.0);
    final strafeAxis =
        (axis(
                  _bindings[GameControl.strafeRight],
                  _bindings[GameControl.strafeLeft],
                ) +
                touch.strafe)
            .clamp(-1.0, 1.0);
    if (forwardAxis == 0 && strafeAxis == 0) return;

    final sinYaw = math.sin(_yaw);
    final cosYaw = math.cos(_yaw);
    final sinPitch = math.sin(_pitch);
    final cosPitch = math.cos(_pitch);
    var moveX = forwardAxis * -sinYaw * cosPitch + strafeAxis * cosYaw;
    var moveY = forwardAxis * sinPitch;
    var moveZ = forwardAxis * -cosYaw * cosPitch - strafeAxis * sinYaw;
    final length = math.sqrt(moveX * moveX + moveY * moveY + moveZ * moveZ);
    if (length > 1) {
      moveX /= length;
      moveY /= length;
      moveZ /= length;
    }
    final distance = noclipSpeed * dt;
    eyePosition
      ..x += moveX * distance
      ..y += moveY * distance
      ..z += moveZ * distance;
    eyePosition.y = eyePosition.y
        .clamp(1, WorldDims.worldBlocksY - 1)
        .toDouble();
  }

  void _emitFootstep() {
    final blockX = body.position.x.floor();
    final blockY = (body.position.y - PhysicsSim.collisionEpsilon * 2).floor();
    final blockZ = body.position.z.floor();
    final blockId = Blocks.id(voxelWorld.blockAt(blockX, blockY, blockZ));
    if (blockId == Blocks.air) return;

    final seed =
        _editAudioSeed(blockX, blockY, blockZ) ^
        (_footstepSerial++ * 0x1F123BB5);
    onFootstep?.call(blockId, seed);
  }
}

int _editAudioSeed(int x, int y, int z) =>
    x * 73856093 ^ y * 19349663 ^ z * 83492791;
