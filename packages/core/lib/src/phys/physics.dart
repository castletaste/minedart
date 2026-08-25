/// Fixed-step player movement and voxel collision resolution.
library;

import 'dart:math' as math;

import '../block.dart';
import '../chunk.dart';
import '../liquid.dart';
import '../world.dart';
import 'aabb.dart';
import 'player_body.dart';

final class PlayerInput {
  const PlayerInput({
    this.moveX = 0,
    this.moveZ = 0,
    this.jump = false,
    this.sprint = false,
  });

  static const PlayerInput idle = PlayerInput();

  /// World-space movement axes. Values outside the unit circle are normalized.
  final double moveX;
  final double moveZ;
  final bool jump;
  final bool sprint;
}

final class PhysicsSim {
  static const double fixedDt = 1 / 60;
  static const double gravity = 32;
  static const double terminalVelocity = 78;
  static const double jumpVelocity = 8.4;
  static const double walkSpeed = 4.3;
  static const double sprintSpeed = 5.6;
  static const double collisionEpsilon = 1e-4;

  static const double _groundAcceleration = 52;
  static const double _airAcceleration = 9;
  static const double _liquidAcceleration = 18;
  static const double _liquidSpeed = 2.2;
  static const double _liquidVerticalSpeed = 3.4;
  static const double _liquidExitVelocity = 6;
  static const double _liquidBuoyancy = 6;
  static const double _liquidGravity = 8;

  // Alpha applies these once per 20 Hz game tick. Physics runs at 60 Hz, so
  // one fixed step uses the cube root and three steps reproduce one Alpha
  // tick exactly (up to floating-point rounding).
  static const double _waterDrag20Hz = 0.8;
  static const double _lavaDrag20Hz = 0.5;
  static const double _waterDrag60Hz = 0.9283177667225558;
  static const double _lavaDrag60Hz = 0.7937005259840998;

  // Alpha adds 0.014 motion units per 20 Hz tick. Player velocity here is in
  // blocks/second, so the equivalent acceleration is 0.014 * 20 * 20.
  static const double _liquidCurrentAcceleration = 5.6;
  static const List<int> _flowDx = [-1, 1, 0, 0];
  static const List<int> _flowDz = [0, 0, -1, 1];

  final Aabb _bodyBounds = Aabb();
  final _LiquidProbe _liquidProbe = _LiquidProbe();
  double _accumulator = 0;
  bool _jumpWasDown = false;

  double get accumulator => _accumulator;

  /// Advances by as many 1/60 s ticks as [frameDt] contains.
  ///
  /// The remainder is retained for the next frame. No time is discarded, so a
  /// temporary 0.5 s frame still receives full fixed-step collision handling.
  int advance(
    VoxelWorld world,
    PlayerBody body,
    PlayerInput input,
    double frameDt,
  ) {
    if (!frameDt.isFinite || frameDt <= 0) return 0;
    _accumulator += frameDt;
    var steps = 0;
    while (_accumulator + 1e-12 >= fixedDt) {
      step(world, body, input, fixedDt);
      _accumulator -= fixedDt;
      steps++;
    }
    if (_accumulator < 0) _accumulator = 0;
    return steps;
  }

  /// Performs one simulation tick. [advance] is the normal frame-facing API.
  void step(VoxelWorld world, PlayerBody body, PlayerInput input, double dt) {
    if (!dt.isFinite || dt <= 0) return;

    body.writeAabb(_bodyBounds);
    _sampleLiquids(world, _bodyBounds, _liquidProbe);
    final liquidId = _liquidProbe.inWater
        ? Blocks.water
        : (_liquidProbe.inLava ? Blocks.lava : Blocks.air);
    final inLiquid = liquidId != Blocks.air;

    var inputX = input.moveX;
    var inputZ = input.moveZ;
    final inputLengthSquared = inputX * inputX + inputZ * inputZ;
    if (inputLengthSquared > 1) {
      final inverseLength = 1 / math.sqrt(inputLengthSquared);
      inputX *= inverseLength;
      inputZ *= inverseLength;
    }

    final targetSpeed = inLiquid
        ? _liquidSpeed
        : (input.sprint ? sprintSpeed : walkSpeed);
    final acceleration = inLiquid
        ? _liquidAcceleration
        : (body.onGround ? _groundAcceleration : _airAcceleration);
    body.velocity.x = _approach(
      body.velocity.x,
      inputX * targetSpeed,
      acceleration * dt,
    );
    body.velocity.z = _approach(
      body.velocity.z,
      inputZ * targetSpeed,
      acceleration * dt,
    );

    final pressedJump = input.jump && !_jumpWasDown;
    if (inLiquid) {
      final drag = _liquidDrag(liquidId, dt);
      body.velocity.x *= drag;
      body.velocity.z *= drag;
      body.velocity.y *= drag;
      // Mild sink when idle; holding jump swims up.
      body.velocity.y -= (_liquidGravity - _liquidBuoyancy) * dt;
      if (input.jump) {
        body.velocity.y = _approach(
          body.velocity.y,
          _liquidVerticalSpeed,
          _liquidAcceleration * dt,
        );
      }
      _applyLiquidCurrent(body, liquidId, _liquidProbe, dt);
    } else {
      body.velocity.y = math.max(
        body.velocity.y - gravity * dt,
        -terminalVelocity,
      );
      if (pressedJump && body.onGround) {
        body.velocity.y = jumpVelocity;
        body.onGround = false;
      }
    }
    _jumpWasDown = input.jump;

    body.onGround = false;
    final collidedX = _moveX(world, body, body.velocity.x * dt);
    final collidedZ = _moveZ(world, body, body.velocity.z * dt);
    if (inLiquid && input.jump && (collidedX || collidedZ)) {
      // Alpha gives swimmers a short upward boost while they push into a
      // bank. Without it, leaving the 8/9-high surface does not retain enough
      // vertical speed to clear the neighboring one-block ledge.
      body.velocity.y = math.max(body.velocity.y, _liquidExitVelocity);
    }
    _moveY(world, body, body.velocity.y * dt);
  }

  static double _liquidDrag(int liquidId, double dt) {
    if ((dt - fixedDt).abs() <= 1e-12) {
      return liquidId == Blocks.water ? _waterDrag60Hz : _lavaDrag60Hz;
    }
    final drag20Hz = liquidId == Blocks.water ? _waterDrag20Hz : _lavaDrag20Hz;
    return math.pow(drag20Hz, dt * 20).toDouble();
  }

  static void _applyLiquidCurrent(
    PlayerBody body,
    int liquidId,
    _LiquidProbe probe,
    double dt,
  ) {
    var flowX = liquidId == Blocks.water ? probe.waterFlowX : probe.lavaFlowX;
    var flowY = liquidId == Blocks.water ? probe.waterFlowY : probe.lavaFlowY;
    var flowZ = liquidId == Blocks.water ? probe.waterFlowZ : probe.lavaFlowZ;
    final lengthSquared = flowX * flowX + flowY * flowY + flowZ * flowZ;
    if (lengthSquared <= 1e-12) return;

    final scale = _liquidCurrentAcceleration * dt / math.sqrt(lengthSquared);
    flowX *= scale;
    flowY *= scale;
    flowZ *= scale;
    body.velocity.x += flowX;
    body.velocity.y += flowY;
    body.velocity.z += flowZ;
  }

  static double _approach(double current, double target, double amount) {
    if (current < target) return math.min(current + amount, target);
    if (current > target) return math.max(current - amount, target);
    return current;
  }

  bool _moveX(VoxelWorld world, PlayerBody body, double delta) {
    if (delta == 0) return false;
    body.writeAabb(_bodyBounds);
    var allowed = delta;
    final minY = (_bodyBounds.minY + collisionEpsilon).floor();
    final maxY = (_bodyBounds.maxY - collisionEpsilon).floor();
    final minZ = (_bodyBounds.minZ + collisionEpsilon).floor();
    final maxZ = (_bodyBounds.maxZ - collisionEpsilon).floor();

    if (delta > 0) {
      final firstX = _bodyBounds.maxX.floor();
      final lastX = (_bodyBounds.maxX + delta).floor();
      for (var x = firstX; x <= lastX; x++) {
        for (var y = minY; y <= maxY; y++) {
          for (var z = minZ; z <= maxZ; z++) {
            if (!_isSolid(world, x, y, z)) continue;
            final candidate = x - _bodyBounds.maxX - collisionEpsilon;
            if (candidate >= -collisionEpsilon && candidate < allowed) {
              allowed = math.max(0, candidate);
            }
          }
        }
      }
    } else {
      final firstX = (_bodyBounds.minX - collisionEpsilon).floor();
      final lastX = (_bodyBounds.minX + delta).floor();
      for (var x = firstX; x >= lastX; x--) {
        for (var y = minY; y <= maxY; y++) {
          for (var z = minZ; z <= maxZ; z++) {
            if (!_isSolid(world, x, y, z)) continue;
            final candidate = x + 1 - _bodyBounds.minX + collisionEpsilon;
            if (candidate <= collisionEpsilon && candidate > allowed) {
              allowed = math.min(0, candidate);
            }
          }
        }
      }
    }

    body.position.x += allowed;
    final collided = allowed != delta;
    if (collided) body.velocity.x = 0;
    return collided;
  }

  bool _moveZ(VoxelWorld world, PlayerBody body, double delta) {
    if (delta == 0) return false;
    body.writeAabb(_bodyBounds);
    var allowed = delta;
    final minX = (_bodyBounds.minX + collisionEpsilon).floor();
    final maxX = (_bodyBounds.maxX - collisionEpsilon).floor();
    final minY = (_bodyBounds.minY + collisionEpsilon).floor();
    final maxY = (_bodyBounds.maxY - collisionEpsilon).floor();

    if (delta > 0) {
      final firstZ = _bodyBounds.maxZ.floor();
      final lastZ = (_bodyBounds.maxZ + delta).floor();
      for (var z = firstZ; z <= lastZ; z++) {
        for (var y = minY; y <= maxY; y++) {
          for (var x = minX; x <= maxX; x++) {
            if (!_isSolid(world, x, y, z)) continue;
            final candidate = z - _bodyBounds.maxZ - collisionEpsilon;
            if (candidate >= -collisionEpsilon && candidate < allowed) {
              allowed = math.max(0, candidate);
            }
          }
        }
      }
    } else {
      final firstZ = (_bodyBounds.minZ - collisionEpsilon).floor();
      final lastZ = (_bodyBounds.minZ + delta).floor();
      for (var z = firstZ; z >= lastZ; z--) {
        for (var y = minY; y <= maxY; y++) {
          for (var x = minX; x <= maxX; x++) {
            if (!_isSolid(world, x, y, z)) continue;
            final candidate = z + 1 - _bodyBounds.minZ + collisionEpsilon;
            if (candidate <= collisionEpsilon && candidate > allowed) {
              allowed = math.min(0, candidate);
            }
          }
        }
      }
    }

    body.position.z += allowed;
    final collided = allowed != delta;
    if (collided) body.velocity.z = 0;
    return collided;
  }

  void _moveY(VoxelWorld world, PlayerBody body, double delta) {
    if (delta == 0) return;
    body.writeAabb(_bodyBounds);
    var allowed = delta;
    final minX = (_bodyBounds.minX + collisionEpsilon).floor();
    final maxX = (_bodyBounds.maxX - collisionEpsilon).floor();
    final minZ = (_bodyBounds.minZ + collisionEpsilon).floor();
    final maxZ = (_bodyBounds.maxZ - collisionEpsilon).floor();

    if (delta > 0) {
      final firstY = _bodyBounds.maxY.floor();
      final lastY = (_bodyBounds.maxY + delta).floor();
      for (var y = firstY; y <= lastY; y++) {
        for (var z = minZ; z <= maxZ; z++) {
          for (var x = minX; x <= maxX; x++) {
            if (!_isSolid(world, x, y, z)) continue;
            final candidate = y - _bodyBounds.maxY - collisionEpsilon;
            if (candidate >= -collisionEpsilon && candidate < allowed) {
              allowed = math.max(0, candidate);
            }
          }
        }
      }
    } else {
      final firstY = (_bodyBounds.minY - collisionEpsilon).floor();
      final lastY = (_bodyBounds.minY + delta).floor();
      for (var y = firstY; y >= lastY; y--) {
        for (var z = minZ; z <= maxZ; z++) {
          for (var x = minX; x <= maxX; x++) {
            if (!_isSolid(world, x, y, z)) continue;
            final candidate = y + 1 - _bodyBounds.minY + collisionEpsilon;
            if (candidate <= collisionEpsilon && candidate > allowed) {
              allowed = math.min(0, candidate);
            }
          }
        }
      }
    }

    body.position.y += allowed;
    if (allowed != delta) {
      if (delta < 0) body.onGround = true;
      body.velocity.y = 0;
    }
  }

  static bool _isSolid(VoxelWorld world, int x, int y, int z) {
    // The finite world is fenced: anything beyond the X/Z border acts as a
    // solid wall so the player cannot walk off the map and liquid currents do
    // not pull toward unreachable outside-world drops. Vertical out-of-range
    // stays non-solid (bedrock already seals the bottom). Surface geometry
    // must not use this helper: the mesher samples out-of-world as air.
    if (x < 0 ||
        z < 0 ||
        x >= WorldDims.worldBlocksX ||
        z >= WorldDims.worldBlocksZ) {
      return y >= 0 && y < WorldDims.worldBlocksY;
    }
    final id = Blocks.id(world.blockAt(x, y, z));
    if (id <= Blocks.air || id >= blockDefs.length) return false;
    return blockDefs[id]!.solid;
  }

  static bool _isSurfaceSolid(int raw) {
    final id = Blocks.id(raw);
    if (id <= Blocks.air || id >= blockDefs.length) return false;
    return blockDefs[id]!.solid;
  }

  static void _sampleLiquids(
    VoxelWorld world,
    Aabb bounds,
    _LiquidProbe probe,
  ) {
    probe.reset();
    final minX = (bounds.minX + collisionEpsilon).floor();
    final maxX = (bounds.maxX - collisionEpsilon).floor();
    final minY = (bounds.minY + collisionEpsilon).floor();
    final maxY = (bounds.maxY - collisionEpsilon).floor();
    final minZ = (bounds.minZ + collisionEpsilon).floor();
    final maxZ = (bounds.maxZ - collisionEpsilon).floor();
    for (var y = minY; y <= maxY; y++) {
      for (var z = minZ; z <= maxZ; z++) {
        for (var x = minX; x <= maxX; x++) {
          final raw = world.blockAt(x, y, z);
          final liquidId = Blocks.id(raw);
          if (!LiquidState.isLiquidId(liquidId) ||
              !_intersectsLiquidSurface(world, bounds, x, y, z, liquidId)) {
            continue;
          }
          if (liquidId == Blocks.water) {
            probe.inWater = true;
          } else {
            probe.inLava = true;
          }
          _accumulateFlow(world, x, y, z, raw, liquidId, probe);
        }
      }
    }
  }

  static bool _intersectsLiquidSurface(
    VoxelWorld world,
    Aabb bounds,
    int x,
    int y,
    int z,
    int liquidId,
  ) {
    if (bounds.maxY <= y + collisionEpsilon ||
        bounds.minY + collisionEpsilon >= y + 1) {
      return false;
    }

    final minX = math.max(bounds.minX, x.toDouble());
    final maxX = math.min(bounds.maxX, x + 1.0);
    final minZ = math.max(bounds.minZ, z.toDouble());
    final maxZ = math.min(bounds.maxZ, z + 1.0);
    if (minX >= maxX || minZ >= maxZ) return false;

    // A bilinear patch reaches its maximum over a rectangle at one of that
    // rectangle's corners. Sampling the clipped AABB corners therefore gives
    // an exact volume-intersection result without allocating geometry.
    final h00 = _cornerLiquidHeight(world, liquidId, x, y, z);
    final h10 = _cornerLiquidHeight(world, liquidId, x + 1, y, z);
    final h01 = _cornerLiquidHeight(world, liquidId, x, y, z + 1);
    final h11 = _cornerLiquidHeight(world, liquidId, x + 1, y, z + 1);
    final localMinX = minX - x;
    final localMaxX = maxX - x;
    final localMinZ = minZ - z;
    final localMaxZ = maxZ - z;
    var maxHeight = _bilinearHeight(h00, h10, h01, h11, localMinX, localMinZ);
    maxHeight = math.max(
      maxHeight,
      _bilinearHeight(h00, h10, h01, h11, localMaxX, localMinZ),
    );
    maxHeight = math.max(
      maxHeight,
      _bilinearHeight(h00, h10, h01, h11, localMinX, localMaxZ),
    );
    maxHeight = math.max(
      maxHeight,
      _bilinearHeight(h00, h10, h01, h11, localMaxX, localMaxZ),
    );
    return bounds.minY + collisionEpsilon < y + maxHeight;
  }

  static double _cornerLiquidHeight(
    VoxelWorld world,
    int liquidId,
    int cornerX,
    int y,
    int cornerZ,
  ) {
    // Alpha's rendered corner height averages the surrounding 2x2 columns.
    // Source and falling samples count eleven times, keeping broad pools flat
    // while allowing banks and metadata gradients to slope smoothly.
    for (var dz = -1; dz <= 0; dz++) {
      for (var dx = -1; dx <= 0; dx++) {
        if (Blocks.id(world.blockAt(cornerX + dx, y + 1, cornerZ + dz)) ==
            liquidId) {
          return 1;
        }
      }
    }

    var airSum = 0.0;
    var weightSum = 0.0;
    for (var dz = -1; dz <= 0; dz++) {
      for (var dx = -1; dx <= 0; dx++) {
        final sampleX = cornerX + dx;
        final sampleZ = cornerZ + dz;
        final sampleRaw = world.blockAt(sampleX, y, sampleZ);
        if (Blocks.id(sampleRaw) == liquidId) {
          final heavy =
              LiquidState.isFalling(sampleRaw) ||
              LiquidState.level(sampleRaw) == 0;
          final weight = heavy ? 11.0 : 1.0;
          airSum += (1 - LiquidState.surfaceHeight(sampleRaw)) * weight;
          weightSum += weight;
        } else if (!_isSurfaceSolid(sampleRaw)) {
          airSum += 1;
          weightSum += 1;
        }
      }
    }
    if (weightSum == 0) return 0;
    return 1 - airSum / weightSum;
  }

  static double _bilinearHeight(
    double h00,
    double h10,
    double h01,
    double h11,
    double x,
    double z,
  ) {
    final near = h00 + (h10 - h00) * x;
    final far = h01 + (h11 - h01) * x;
    return near + (far - near) * z;
  }

  static void _accumulateFlow(
    VoxelWorld world,
    int x,
    int y,
    int z,
    int raw,
    int liquidId,
    _LiquidProbe probe,
  ) {
    final ownLevel = LiquidState.isFalling(raw) ? 0 : LiquidState.level(raw);
    var flowX = 0.0;
    var flowZ = 0.0;
    for (var direction = 0; direction < 4; direction++) {
      final dx = _flowDx[direction];
      final dz = _flowDz[direction];
      final neighborX = x + dx;
      final neighborZ = z + dz;
      final neighborRaw = world.blockAt(neighborX, y, neighborZ);
      var neighborLevel = _effectiveLiquidLevel(neighborRaw, liquidId);
      if (neighborLevel < 0 && !_isSolid(world, neighborX, y, neighborZ)) {
        neighborLevel = _effectiveLiquidLevel(
          world.blockAt(neighborX, y - 1, neighborZ),
          liquidId,
        );
        if (neighborLevel >= 0) {
          final difference = neighborLevel - (ownLevel - 8);
          flowX += dx * difference;
          flowZ += dz * difference;
        }
      } else if (neighborLevel >= 0) {
        final difference = neighborLevel - ownLevel;
        flowX += dx * difference;
        flowZ += dz * difference;
      }
    }

    var flowY = 0.0;
    if (LiquidState.isFalling(raw)) {
      final horizontalLengthSquared = flowX * flowX + flowZ * flowZ;
      if (horizontalLengthSquared > 1e-12) {
        final inverseLength = 1 / math.sqrt(horizontalLengthSquared);
        flowX *= inverseLength;
        flowZ *= inverseLength;
      }
      // Alpha biases falling flow sharply downward after normalizing its
      // horizontal gradient. Applying it to every falling column gives both
      // water and lava deterministic waterfall pull in Minedart's profile.
      flowY = -6;
    }

    final lengthSquared = flowX * flowX + flowY * flowY + flowZ * flowZ;
    if (lengthSquared <= 1e-12) return;
    final inverseLength = 1 / math.sqrt(lengthSquared);
    probe.addFlow(
      liquidId,
      flowX * inverseLength,
      flowY * inverseLength,
      flowZ * inverseLength,
    );
  }

  static int _effectiveLiquidLevel(int raw, int liquidId) {
    if (Blocks.id(raw) != liquidId) return -1;
    return LiquidState.isFalling(raw) ? 0 : LiquidState.level(raw);
  }
}

final class _LiquidProbe {
  bool inWater = false;
  bool inLava = false;
  double waterFlowX = 0;
  double waterFlowY = 0;
  double waterFlowZ = 0;
  double lavaFlowX = 0;
  double lavaFlowY = 0;
  double lavaFlowZ = 0;

  void reset() {
    inWater = false;
    inLava = false;
    waterFlowX = 0;
    waterFlowY = 0;
    waterFlowZ = 0;
    lavaFlowX = 0;
    lavaFlowY = 0;
    lavaFlowZ = 0;
  }

  void addFlow(int liquidId, double x, double y, double z) {
    if (liquidId == Blocks.water) {
      waterFlowX += x;
      waterFlowY += y;
      waterFlowZ += z;
    } else {
      lavaFlowX += x;
      lavaFlowY += y;
      lavaFlowZ += z;
    }
  }
}
