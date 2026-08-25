import 'dart:math' as math;

import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('PhysicsSim', () {
    test('falls onto a floor and becomes grounded', () {
      final world = VoxelWorld();
      _fillFloor(world);
      final body = PlayerBody(position: Vector3(8.5, 8, 8.5));
      final sim = PhysicsSim();

      _ticks(sim, world, body, 120);

      expect(body.position.y, closeTo(1.0001, 1e-4));
      expect(body.velocity.y, 0);
      expect(body.onGround, isTrue);
    });

    for (final axis in ['+x', '-x', '+z', '-z']) {
      test('stops at a wall on $axis', () {
        final world = VoxelWorld();
        _fillFloor(world);
        final body = PlayerBody(
          position: Vector3(8.5, 1.0001, 8.5),
          onGround: true,
        );
        final sim = PhysicsSim();
        switch (axis) {
          case '+x':
            _wallX(world, 10);
            _ticks(sim, world, body, 60, const PlayerInput(moveX: 1));
            expect(body.position.x, closeTo(9.6999, 2e-4));
          case '-x':
            _wallX(world, 6);
            _ticks(sim, world, body, 60, const PlayerInput(moveX: -1));
            expect(body.position.x, closeTo(7.3001, 2e-4));
          case '+z':
            _wallZ(world, 10);
            _ticks(sim, world, body, 60, const PlayerInput(moveZ: 1));
            expect(body.position.z, closeTo(9.6999, 2e-4));
          case '-z':
            _wallZ(world, 6);
            _ticks(sim, world, body, 60, const PlayerInput(moveZ: -1));
            expect(body.position.z, closeTo(7.3001, 2e-4));
        }
      });
    }

    test('jump rises over exactly one block', () {
      final world = VoxelWorld();
      _fillFloor(world);
      final body = PlayerBody(
        position: Vector3(8.5, 1.0001, 8.5),
        onGround: true,
      );
      final sim = PhysicsSim();
      var apex = body.position.y;

      sim.advance(
        world,
        body,
        const PlayerInput(jump: true),
        PhysicsSim.fixedDt,
      );
      for (var i = 0; i < 90; i++) {
        sim.advance(world, body, PlayerInput.idle, PhysicsSim.fixedDt);
        if (body.position.y > apex) apex = body.position.y;
      }

      expect(apex - 1.0001, greaterThan(1));
      expect(apex - 1.0001, lessThan(1.25));
      expect(body.onGround, isTrue);
    });

    test('slides into a two-wall corner without penetration', () {
      final world = VoxelWorld();
      _fillFloor(world);
      _wallX(world, 10);
      _wallZ(world, 10);
      final body = PlayerBody(
        position: Vector3(8.5, 1.0001, 8.5),
        onGround: true,
      );
      final sim = PhysicsSim();

      _ticks(sim, world, body, 90, const PlayerInput(moveX: 1, moveZ: 1));

      expect(body.position.x, closeTo(9.6999, 2e-4));
      expect(body.position.z, closeTo(9.6999, 2e-4));
      expect(body.velocity.x, 0);
      expect(body.velocity.z, 0);
    });

    test('keeps sliding along a wall when one movement axis is blocked', () {
      final world = VoxelWorld();
      _fillFloor(world);
      _wallX(world, 10);
      final body = PlayerBody(
        position: Vector3(8.5, 1.0001, 8.5),
        onGround: true,
      );
      final sim = PhysicsSim();

      _ticks(sim, world, body, 90, const PlayerInput(moveX: 1, moveZ: 1));

      expect(body.position.x, closeTo(9.6999, 2e-4));
      expect(body.position.z, greaterThan(11));
      expect(body.velocity.x, 0);
      expect(body.velocity.z, greaterThan(0));
    });

    test('upward movement stops at a ceiling', () {
      final world = VoxelWorld();
      _fillFloor(world);
      for (var x = 7; x <= 9; x++) {
        for (var z = 7; z <= 9; z++) {
          world.setBlock(x, 3, z, Blocks.stone);
        }
      }
      final body = PlayerBody(
        position: Vector3(8.5, 1.0001, 8.5),
        onGround: true,
      );
      final sim = PhysicsSim();

      sim.advance(
        world,
        body,
        const PlayerInput(jump: true),
        PhysicsSim.fixedDt,
      );
      _ticks(sim, world, body, 8);

      expect(body.position.y, lessThanOrEqualTo(1.1999 + 2e-4));
      expect(body.velocity.y, lessThanOrEqualTo(0));
    });

    test('0.5 second frame spike cannot tunnel through floor', () {
      final world = VoxelWorld();
      _fillFloor(world);
      final body = PlayerBody(
        position: Vector3(8.5, 3, 8.5),
        velocity: Vector3(0, -78, 0),
      );
      final sim = PhysicsSim();

      final steps = sim.advance(world, body, PlayerInput.idle, 0.5);

      expect(steps, 30);
      expect(body.position.y, closeTo(1.0001, 2e-4));
      expect(body.onGround, isTrue);
    });

    test('partial-height liquid activates only below its Alpha surface', () {
      final world = VoxelWorld();
      _fillFloor(world);
      _fillLiquidPool(world, Blocks.water, level: 7);
      const surfaceY = 1 + 1 / 9;
      final above = PlayerBody(position: Vector3(8.5, surfaceY + 0.001, 8.5));
      final immersed = PlayerBody(
        position: Vector3(8.5, surfaceY - 0.001, 8.5),
      );

      PhysicsSim().step(world, above, PlayerInput.idle, PhysicsSim.fixedDt);
      PhysicsSim().step(world, immersed, PlayerInput.idle, PhysicsSim.fixedDt);

      expect(
        above.velocity.y,
        closeTo(-PhysicsSim.gravity * PhysicsSim.fixedDt, 1e-6),
      );
      expect(immersed.velocity.y.abs(), lessThan(above.velocity.y.abs()));
    });

    test('world-border immersion counts outside columns as surface air', () {
      final world = VoxelWorld();
      _fillFloor(world);
      for (var x = 0; x <= 1; x++) {
        for (var z = 7; z <= 9; z++) {
          world.setBlock(x, 1, z, LiquidState.pack(Blocks.water, 0));
        }
      }

      // At x=0 the Alpha 2x2 corner average sees two source samples and two
      // outside-air samples: height = 1 - ((2*11/9 + 2) / 24) = 22/27.
      // The opposite corner is surrounded by source water at height 8/9.
      // A body centered at x=.3 reaches x=.6, so the bilinear footprint max is
      // 22/27 + (8/9 - 22/27) * .6 = 116/135.
      const footprintMaxHeight = 116 / 135;
      final above = PlayerBody(
        position: Vector3(0.3, 1 + footprintMaxHeight + 0.001, 8.5),
      );
      final immersed = PlayerBody(
        position: Vector3(0.3, 1 + footprintMaxHeight - 0.001, 8.5),
      );

      PhysicsSim().step(world, above, PlayerInput.idle, PhysicsSim.fixedDt);
      PhysicsSim().step(world, immersed, PlayerInput.idle, PhysicsSim.fixedDt);

      expect(
        above.velocity.y,
        closeTo(-PhysicsSim.gravity * PhysicsSim.fixedDt, 1e-6),
      );
      expect(immersed.velocity.y.abs(), lessThan(above.velocity.y.abs()));
    });

    for (final liquidId in [Blocks.water, Blocks.lava]) {
      final liquidName = liquidId == Blocks.water ? 'water' : 'lava';
      test('$liquidName current follows the neighbor-level gradient', () {
        final world = VoxelWorld();
        _fillFloor(world);
        for (var z = 7; z <= 9; z++) {
          for (var x = 7; x <= 9; x++) {
            world.setBlock(x, 1, z, LiquidState.pack(liquidId, x - 7));
          }
        }
        final body = PlayerBody(position: Vector3(8.5, 1.01, 8.5));

        PhysicsSim().step(world, body, PlayerInput.idle, PhysicsSim.fixedDt);

        expect(body.velocity.x, greaterThan(0));
        expect(body.velocity.z, closeTo(0, 1e-12));
      });
    }

    test('falling liquid contributes a downward waterfall current', () {
      final world = VoxelWorld();
      _fillFloor(world);
      _fillLiquidPool(world, Blocks.water, falling: true);
      final body = PlayerBody(position: Vector3(8.5, 1.01, 8.5));

      PhysicsSim().step(world, body, PlayerInput.idle, PhysicsSim.fixedDt);

      expect(body.velocity.y, lessThan(-0.1));
      expect(body.velocity.x, closeTo(0, 1e-12));
      expect(body.velocity.z, closeTo(0, 1e-12));
    });

    test('water and lava use cube-root Alpha drag conversions', () {
      final waterWorld = VoxelWorld();
      final lavaWorld = VoxelWorld();
      _fillFloor(waterWorld);
      _fillFloor(lavaWorld);
      _fillLiquidPool(waterWorld, Blocks.water, minX: 3, maxX: 12);
      _fillLiquidPool(lavaWorld, Blocks.lava, minX: 3, maxX: 12);
      final waterBody = PlayerBody(
        position: Vector3(8.5, 1.01, 8.5),
        velocity: Vector3(6, 0, 0),
      );
      final lavaBody = PlayerBody(
        position: Vector3(8.5, 1.01, 8.5),
        velocity: Vector3(6, 0, 0),
      );

      PhysicsSim().step(
        waterWorld,
        waterBody,
        PlayerInput.idle,
        PhysicsSim.fixedDt,
      );
      PhysicsSim().step(
        lavaWorld,
        lavaBody,
        PlayerInput.idle,
        PhysicsSim.fixedDt,
      );

      expect(
        waterBody.velocity.x,
        closeTo((6 - 0.3) * math.pow(0.8, 1 / 3), 1e-6),
      );
      expect(
        lavaBody.velocity.x,
        closeTo((6 - 0.3) * math.pow(0.5, 1 / 3), 1e-6),
      );
      expect(lavaBody.velocity.x, lessThan(waterBody.velocity.x));
    });

    test('water slows horizontal movement, floats, and jump swims upward', () {
      final world = VoxelWorld();
      _fillFloor(world);
      for (var y = 1; y <= 2; y++) {
        world.setBlock(8, y, 8, Blocks.water);
      }
      final body = PlayerBody(
        position: Vector3(8.5, 1.0001, 8.5),
        onGround: true,
      );
      final sim = PhysicsSim();

      sim.advance(
        world,
        body,
        const PlayerInput(moveX: 1, jump: true),
        PhysicsSim.fixedDt,
      );

      expect(body.velocity.x, lessThan(PhysicsSim.walkSpeed));
      expect(body.velocity.y, greaterThan(0));
      expect(body.position.y, greaterThan(1.0001));
      expect(body.onGround, isFalse);
    });

    test('lava applies buoyancy and supports swimming', () {
      final world = VoxelWorld();
      _fillFloor(world);
      _fillLiquidPool(world, Blocks.lava);
      final idleBody = PlayerBody(position: Vector3(8.5, 1.01, 8.5));
      final swimmingBody = PlayerBody(position: Vector3(8.5, 1.01, 8.5));

      PhysicsSim().step(world, idleBody, PlayerInput.idle, PhysicsSim.fixedDt);
      PhysicsSim().step(
        world,
        swimmingBody,
        const PlayerInput(jump: true),
        PhysicsSim.fixedDt,
      );

      expect(idleBody.velocity.y, lessThan(0));
      expect(idleBody.velocity.y, greaterThan(-0.1));
      expect(swimmingBody.velocity.y, greaterThan(0));
      expect(swimmingBody.position.y, greaterThan(1.01));
    });

    test('holding jump while pushing into a bank exits liquid onto land', () {
      for (final liquidId in <int>[Blocks.water, Blocks.lava]) {
        for (final level in <int>[0, 4]) {
          final world = VoxelWorld();
          _fillFloor(world);
          for (var x = 5; x <= 8; x++) {
            for (var z = 7; z <= 9; z++) {
              world.setBlock(x, 1, z, LiquidState.pack(liquidId, level));
            }
          }
          for (var x = 9; x < 16; x++) {
            for (var z = 7; z <= 9; z++) {
              world.setBlock(x, 1, z, Blocks.stone);
            }
          }
          final body = PlayerBody(position: Vector3(8.5, 1.0001, 8.5));
          final sim = PhysicsSim();

          var exited = false;
          for (var tick = 0; tick < 180; tick++) {
            sim.advance(
              world,
              body,
              const PlayerInput(moveX: 1, jump: true),
              PhysicsSim.fixedDt,
            );
            if (body.position.x > 9.3 && body.position.y >= 2) {
              exited = true;
              break;
            }
          }
          _ticks(sim, world, body, 120);

          final reason = 'liquid=$liquidId level=$level';
          expect(exited, isTrue, reason: reason);
          expect(body.position.x, greaterThan(9.3), reason: reason);
          expect(body.position.y, closeTo(2.0001, 2e-4));
          expect(body.onGround, isTrue);
        }
      }
    });

    test('a bank does not boost a swimmer who is not holding jump', () {
      final world = VoxelWorld();
      _fillFloor(world);
      for (var x = 5; x <= 8; x++) {
        for (var z = 7; z <= 9; z++) {
          world.setBlock(x, 1, z, LiquidState.pack(Blocks.water, 4));
        }
      }
      for (var x = 9; x < 16; x++) {
        for (var z = 7; z <= 9; z++) {
          world.setBlock(x, 1, z, Blocks.stone);
        }
      }
      final body = PlayerBody(position: Vector3(8.5, 1.0001, 8.5));

      _ticks(PhysicsSim(), world, body, 180, const PlayerInput(moveX: 1));

      expect(body.position.x, lessThan(9));
      expect(body.position.y, closeTo(1.0001, 2e-4));
      expect(body.onGround, isTrue);
    });

    test('sprint reaches 5.6 blocks per second versus 4.3 walking', () {
      final world = VoxelWorld();
      _fillFloor(world);
      final walkingBody = PlayerBody(
        position: Vector3(4.5, 1.0001, 8.5),
        onGround: true,
      );
      final sprintingBody = PlayerBody(
        position: Vector3(4.5, 1.0001, 4.5),
        onGround: true,
      );

      _ticks(PhysicsSim(), world, walkingBody, 30, const PlayerInput(moveX: 1));
      _ticks(
        PhysicsSim(),
        world,
        sprintingBody,
        30,
        const PlayerInput(moveX: 1, sprint: true),
      );

      expect(walkingBody.velocity.x, closeTo(PhysicsSim.walkSpeed, 1e-6));
      expect(sprintingBody.velocity.x, closeTo(PhysicsSim.sprintSpeed, 1e-6));
    });

    test('sprint does not increase movement speed in water', () {
      final world = VoxelWorld();
      _fillFloor(world);
      for (var x = 3; x <= 9; x++) {
        for (var y = 1; y <= 2; y++) {
          world.setBlock(x, y, 4, Blocks.water);
          world.setBlock(x, y, 8, Blocks.water);
        }
      }
      final walkingBody = PlayerBody(
        position: Vector3(4.5, 1.0001, 8.5),
        onGround: true,
      );
      final sprintingBody = PlayerBody(
        position: Vector3(4.5, 1.0001, 4.5),
        onGround: true,
      );

      _ticks(PhysicsSim(), world, walkingBody, 20, const PlayerInput(moveX: 1));
      _ticks(
        PhysicsSim(),
        world,
        sprintingBody,
        20,
        const PlayerInput(moveX: 1, sprint: true),
      );

      expect(sprintingBody.velocity.x, closeTo(walkingBody.velocity.x, 1e-12));
    });

    test('sprint does not increase movement speed in lava', () {
      final world = VoxelWorld();
      _fillFloor(world);
      for (var x = 3; x <= 9; x++) {
        for (var y = 1; y <= 2; y++) {
          world.setBlock(x, y, 4, Blocks.lava);
          world.setBlock(x, y, 8, Blocks.lava);
        }
      }
      final walkingBody = PlayerBody(position: Vector3(4.5, 1.0001, 8.5));
      final sprintingBody = PlayerBody(position: Vector3(4.5, 1.0001, 4.5));

      _ticks(PhysicsSim(), world, walkingBody, 20, const PlayerInput(moveX: 1));
      _ticks(
        PhysicsSim(),
        world,
        sprintingBody,
        20,
        const PlayerInput(moveX: 1, sprint: true),
      );

      expect(sprintingBody.velocity.x, closeTo(walkingBody.velocity.x, 1e-12));
    });

    test('sprint still resolves wall collisions in fixed steps', () {
      final world = VoxelWorld();
      _fillFloor(world);
      _wallX(world, 10);
      final body = PlayerBody(
        position: Vector3(8.5, 1.0001, 8.5),
        onGround: true,
      );
      final sim = PhysicsSim();

      final steps = sim.advance(
        world,
        body,
        const PlayerInput(moveX: 1, sprint: true),
        0.5,
      );

      expect(steps, 30);
      expect(body.position.x, closeTo(9.6999, 2e-4));
      expect(body.velocity.x, 0);
    });
  });
}

void _ticks(
  PhysicsSim sim,
  VoxelWorld world,
  PlayerBody body,
  int count, [
  PlayerInput input = PlayerInput.idle,
]) {
  for (var i = 0; i < count; i++) {
    sim.advance(world, body, input, PhysicsSim.fixedDt);
  }
}

void _fillFloor(VoxelWorld world) {
  for (var x = 0; x < 16; x++) {
    for (var z = 0; z < 16; z++) {
      world.setBlock(x, 0, z, Blocks.stone);
    }
  }
}

void _fillLiquidPool(
  VoxelWorld world,
  int liquidId, {
  int level = 0,
  bool falling = false,
  int minX = 7,
  int maxX = 9,
  int minZ = 7,
  int maxZ = 9,
}) {
  final raw = LiquidState.pack(liquidId, level, falling: falling);
  for (var x = minX; x <= maxX; x++) {
    for (var z = minZ; z <= maxZ; z++) {
      world.setBlock(x, 1, z, raw);
    }
  }
}

void _wallX(VoxelWorld world, int x) {
  for (var y = 1; y <= 3; y++) {
    for (var z = 0; z < 16; z++) {
      world.setBlock(x, y, z, Blocks.stone);
    }
  }
}

void _wallZ(VoxelWorld world, int z) {
  for (var y = 1; y <= 3; y++) {
    for (var x = 0; x < 16; x++) {
      world.setBlock(x, y, z, Blocks.stone);
    }
  }
}
