import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('falling blocks do not move before the default cooldown', () {
    final world = VoxelWorld()
      ..setBlock(8, 0, 8, Blocks.stone)
      ..setBlock(8, 3, 8, Blocks.sand);
    final engine = WorldTickEngine()..enqueue(8, 3, 8);

    for (var tick = 0; tick < 3; tick++) {
      final changes = engine.tick(world, 1);

      expect(changes.isEmpty, isTrue);
      expect(world.blockAt(8, 3, 8), Blocks.sand);
      expect(world.blockAt(8, 2, 8), Blocks.air);
      expect(engine.pendingCount, 1);
    }
  });

  test('falling blocks eventually move and keep moving until supported', () {
    final world = VoxelWorld()
      ..setBlock(8, 0, 8, Blocks.stone)
      ..setBlock(8, 3, 8, Blocks.sand);
    final engine = WorldTickEngine()..enqueue(8, 3, 8);

    for (var tick = 0; tick < 3; tick++) {
      expect(engine.tick(world, 64).isEmpty, isTrue);
    }
    final firstMove = engine.tick(world, 64);

    expect(world.blockAt(8, 3, 8), Blocks.air);
    expect(world.blockAt(8, 2, 8), Blocks.sand);
    expect(firstMove.changes, hasLength(2));

    for (var tick = 0; tick < 4; tick++) {
      engine.tick(world, 64);
    }
    expect(world.blockAt(8, 2, 8), Blocks.air);
    expect(world.blockAt(8, 1, 8), Blocks.sand);

    _drain(engine, world, budget: 64);
    expect(engine.isIdle, isTrue);
  });

  test('falling across y chunk boundary dirties both chunks', () {
    final world = VoxelWorld()..setBlock(8, 16, 8, Blocks.gravel);
    final engine = WorldTickEngine()..enqueue(8, 16, 8);

    for (var tick = 0; tick < 3; tick++) {
      expect(engine.tick(world, 1).isEmpty, isTrue);
    }
    final changes = engine.tick(world, 1);

    expect(
      changes.dirtyChunks,
      containsAll([
        VoxelWorld.chunkIndexOf(0, 0, 0),
        VoxelWorld.chunkIndexOf(0, 1, 0),
      ]),
    );
  });

  test('falling cooldown is deterministic and remains queue-bounded', () {
    final a = VoxelWorld()
      ..setBlock(4, 0, 4, Blocks.stone)
      ..setBlock(4, 4, 4, Blocks.sand)
      ..setBlock(5, 0, 4, Blocks.stone)
      ..setBlock(5, 3, 4, Blocks.gravel);
    final b = VoxelWorld()
      ..setBlock(4, 0, 4, Blocks.stone)
      ..setBlock(4, 4, 4, Blocks.sand)
      ..setBlock(5, 0, 4, Blocks.stone)
      ..setBlock(5, 3, 4, Blocks.gravel);
    final engineA = WorldTickEngine(maxQueue: 2)
      ..enqueue(4, 4, 4)
      ..enqueue(5, 3, 4);
    final engineB = WorldTickEngine(maxQueue: 2)
      ..enqueue(4, 4, 4)
      ..enqueue(5, 3, 4);
    const budgets = [1, 2, 1, 1, 2, 2, 1, 2, 1, 2, 2, 2];

    for (final budget in budgets) {
      final changesA = engineA.tick(a, budget);
      final changesB = engineB.tick(b, budget);

      expect(_changeSignature(changesA), _changeSignature(changesB));
      expect(_worldSignature(a), _worldSignature(b));
      expect(engineA.pendingCount, engineB.pendingCount);
      expect(engineA.pendingCount, lessThanOrEqualTo(engineA.maxQueue));
      expect(engineB.pendingCount, lessThanOrEqualTo(engineB.maxQueue));
    }
  });

  test('falling keeps progressing with a one-entry queue', () {
    final world = VoxelWorld()
      ..setBlock(8, 0, 8, Blocks.stone)
      ..setBlock(8, 3, 8, Blocks.gravel);
    final engine = WorldTickEngine(maxQueue: 1)..enqueue(8, 3, 8);

    for (var tick = 0; tick < 20 && !engine.isIdle; tick++) {
      engine.tick(world, 1);
      expect(engine.pendingCount, lessThanOrEqualTo(engine.maxQueue));
    }

    expect(world.blockAt(8, 1, 8), Blocks.gravel);
    expect(engine.isIdle, isTrue);
    expect(engine.droppedUpdates, greaterThan(0));
  });

  test('supported falling blocks drain without visible idle work', () {
    final world = VoxelWorld()
      ..setBlock(8, 0, 8, Blocks.stone)
      ..setBlock(8, 1, 8, Blocks.sand);
    final engine = WorldTickEngine()..enqueue(8, 1, 8);

    expect(engine.tick(world, 1).isEmpty, isTrue);
    expect(engine.isIdle, isTrue);
    expect(engine.pendingCount, 0);
    expect(engine.tick(world, 128).isEmpty, isTrue);
    expect(world.blockAt(8, 1, 8), Blocks.sand);
  });

  test('clear resets a partially elapsed falling cooldown', () {
    final world = VoxelWorld()..setBlock(8, 3, 8, Blocks.sand);
    final engine = WorldTickEngine()..enqueue(8, 3, 8);

    engine.tick(world, 1);
    engine.tick(world, 1);
    engine.clear();

    expect(engine.isIdle, isTrue);
    expect(engine.pendingCount, 0);
    expect(engine.droppedUpdates, 0);

    engine.enqueue(8, 3, 8);
    for (var tick = 0; tick < 3; tick++) {
      expect(engine.tick(world, 1).isEmpty, isTrue);
      expect(world.blockAt(8, 3, 8), Blocks.sand);
    }
    expect(engine.tick(world, 1).changes, hasLength(2));
    expect(world.blockAt(8, 2, 8), Blocks.sand);
  });

  test('water waits five ticks and new flow cannot execute in that tick', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 20, centerZ: 20, radius: 4);
    world.setBlock(20, 1, 20, Blocks.water);
    final engine = WorldTickEngine()..enqueue(20, 1, 20);

    for (var tick = 1; tick < 5; tick++) {
      expect(engine.tick(world, 256).isEmpty, isTrue, reason: 'tick $tick');
      expect(world.blockAt(21, 1, 20), Blocks.air);
    }

    final changes = engine.tick(world, 256);

    expect(changes.changes, hasLength(4));
    for (final (dx, dz) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      expect(world.blockAt(20 + dx, 1, 20 + dz), Blocks.pack(Blocks.water, 1));
    }
    expect(world.blockAt(22, 1, 20), Blocks.air);
    expect(engine.currentTick, 5);
  });

  test('lava waits thirty ticks and has flat levels 2, 4, and 6', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 20, centerZ: 20, radius: 5);
    world.setBlock(20, 1, 20, Blocks.lava);
    final engine = WorldTickEngine()..enqueue(20, 1, 20);

    for (var tick = 1; tick < 30; tick++) {
      expect(engine.tick(world, 256).isEmpty, isTrue, reason: 'tick $tick');
      expect(world.blockAt(21, 1, 20), Blocks.air);
    }
    engine.tick(world, 256);
    expect(world.blockAt(21, 1, 20), Blocks.pack(Blocks.lava, 2));

    _drain(engine, world, budget: 256, maxTicks: 500);

    var lavaCount = 0;
    for (var z = 15; z <= 25; z++) {
      for (var x = 15; x <= 25; x++) {
        final raw = world.blockAt(x, 1, z);
        if (Blocks.id(raw) != Blocks.lava) continue;
        lavaCount++;
        final distance = (x - 20).abs() + (z - 20).abs();
        expect(distance, lessThanOrEqualTo(3));
        expect(Blocks.meta(raw), distance * 2);
      }
    }
    expect(lavaCount, 25);
    expect(engine.isIdle, isTrue);
  });

  test('blocked falling lava lands as levels 1, 3, 5, and 7', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 20, centerZ: 20, radius: 6);
    world
      ..setBlock(20, 2, 20, LiquidState.pack(Blocks.lava, 0, falling: true))
      ..setBlock(20, 1, 20, LiquidState.pack(Blocks.lava, 0, falling: true));
    final engine = WorldTickEngine()..enqueue(20, 1, 20);

    _advance(engine, world, 29);
    expect(world.blockAt(21, 1, 20), Blocks.air);
    engine.tick(world, 256);
    expect(world.blockAt(21, 1, 20), Blocks.pack(Blocks.lava, 1));
    _drain(engine, world, budget: 256, maxTicks: 500);

    for (var z = 14; z <= 26; z++) {
      for (var x = 14; x <= 26; x++) {
        final raw = world.blockAt(x, 1, z);
        if (Blocks.id(raw) != Blocks.lava) continue;
        final distance = (x - 20).abs() + (z - 20).abs();
        if (distance == 0) {
          expect(Blocks.meta(raw), LiquidState.fallingBit);
        } else {
          expect(distance, lessThanOrEqualTo(4));
          expect(Blocks.meta(raw), distance * 2 - 1);
        }
      }
    }
  });

  test('falling metadata is written, preserved, and lands as level one', () {
    final waterfall = VoxelWorld();
    _fillFloor(waterfall, centerX: 20, centerZ: 20, radius: 3);
    waterfall.setBlock(20, 3, 20, Blocks.water);
    final waterfallEngine = WorldTickEngine()..enqueue(20, 3, 20);

    _advance(waterfallEngine, waterfall, 5);
    expect(
      waterfall.blockAt(20, 2, 20),
      LiquidState.pack(Blocks.water, 0, falling: true),
    );
    _advance(waterfallEngine, waterfall, 5);
    expect(
      waterfall.blockAt(20, 1, 20),
      LiquidState.pack(Blocks.water, 0, falling: true),
    );
    _advance(waterfallEngine, waterfall, 5);
    expect(waterfall.blockAt(21, 1, 20), Blocks.pack(Blocks.water, 1));

    final landing = VoxelWorld()
      ..setBlock(30, 0, 30, Blocks.stone)
      ..setBlock(29, 1, 30, Blocks.water)
      ..setBlock(30, 1, 30, LiquidState.pack(Blocks.water, 0, falling: true));
    final landingEngine = WorldTickEngine()..enqueue(30, 1, 30);
    _advance(landingEngine, landing, 5);
    expect(landing.blockAt(30, 1, 30), Blocks.pack(Blocks.water, 1));

    final preserved = VoxelWorld()
      ..setBlock(40, 3, 40, LiquidState.pack(Blocks.water, 5, falling: true))
      ..setBlock(40, 2, 40, LiquidState.pack(Blocks.water, 5, falling: true));
    final preservedEngine = WorldTickEngine()..enqueue(40, 2, 40);
    _advance(preservedEngine, preserved, 5);
    expect(
      preserved.blockAt(40, 1, 40),
      LiquidState.pack(Blocks.water, 5, falling: true),
    );
  });

  test(
    'contact matrix uses obsidian, cobblestone, and unchanged high flow',
    () {
      for (var metadata = 0; metadata < 16; metadata++) {
        final world = VoxelWorld()
          ..setBlock(10, 1, 10, Blocks.water)
          ..setBlock(11, 1, 10, Blocks.pack(Blocks.lava, metadata));
        final engine = WorldTickEngine()..enqueue(11, 1, 10);

        engine.tick(world, 1);

        final expected = switch (metadata) {
          0 => Blocks.obsidian,
          >= 1 && <= 4 => Blocks.cobblestone,
          _ => Blocks.pack(Blocks.lava, metadata),
        };
        expect(
          world.blockAt(11, 1, 10),
          expected,
          reason: 'metadata $metadata',
        );
        expect(world.blockAt(10, 1, 10), Blocks.water);
      }
    },
  );

  test('lava reacts to water above but never to water below', () {
    final above = VoxelWorld()
      ..setBlock(10, 2, 10, Blocks.water)
      ..setBlock(10, 1, 10, Blocks.lava);
    final aboveEngine = WorldTickEngine()..enqueue(10, 2, 10);
    aboveEngine.tick(above, 1);
    expect(above.blockAt(10, 1, 10), Blocks.obsidian);

    final below = VoxelWorld()
      ..setBlock(10, 2, 10, Blocks.lava)
      ..setBlock(10, 1, 10, Blocks.water);
    final belowEngine = WorldTickEngine()..enqueue(10, 1, 10);
    belowEngine.tick(below, 1);
    expect(below.blockAt(10, 2, 10), Blocks.lava);
    expect(below.blockAt(10, 1, 10), Blocks.water);
  });

  test('contact result is independent of water/lava enqueue order', () {
    final a = VoxelWorld()
      ..setBlock(10, 1, 10, Blocks.water)
      ..setBlock(11, 1, 10, Blocks.pack(Blocks.lava, 3));
    final b = VoxelWorld()
      ..setBlock(10, 1, 10, Blocks.water)
      ..setBlock(11, 1, 10, Blocks.pack(Blocks.lava, 3));
    final engineA = WorldTickEngine()
      ..enqueue(10, 1, 10)
      ..enqueue(11, 1, 10);
    final engineB = WorldTickEngine()
      ..enqueue(11, 1, 10)
      ..enqueue(10, 1, 10);

    engineA.tick(a, 2);
    engineB.tick(b, 2);

    expect(
      _localSignature(a, 8, 12, 0, 2, 8, 12),
      _localSignature(b, 8, 12, 0, 2, 8, 12),
    );
    expect(a.blockAt(11, 1, 10), Blocks.cobblestone);
  });

  test('removing a source retracts the complete unsupported flow', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 20, centerZ: 20, radius: 4);
    world.setBlock(20, 1, 20, Blocks.water);
    final engine = WorldTickEngine(maxFluidLevel: 3)..enqueue(20, 1, 20);
    _drain(engine, world, budget: 256, maxTicks: 300);
    expect(
      _liquidCount(world, Blocks.water, 16, 24, 1, 16, 24),
      greaterThan(1),
    );

    world.setBlock(20, 1, 20, Blocks.air);
    engine.enqueueAround(20, 1, 20);
    _drain(engine, world, budget: 256, maxTicks: 500);

    expect(_liquidCount(world, Blocks.water, 16, 24, 1, 16, 24), 0);
  });

  test('depth-four drop search chooses the nearest path and every tie', () {
    final nearest = _dropSearchFixture(centerX: 30, centerZ: 30);
    nearest.setBlock(35, 1, 30, Blocks.air);
    final nearestEngine = WorldTickEngine(maxFluidLevel: 1)..enqueue(30, 2, 30);
    _advance(nearestEngine, nearest, 5);
    expect(Blocks.id(nearest.blockAt(31, 2, 30)), Blocks.water);
    expect(nearest.blockAt(29, 2, 30), Blocks.air);
    expect(nearest.blockAt(30, 2, 29), Blocks.air);
    expect(nearest.blockAt(30, 2, 31), Blocks.air);

    final tied = _dropSearchFixture(centerX: 50, centerZ: 50)
      ..setBlock(55, 1, 50, Blocks.air)
      ..setBlock(45, 1, 50, Blocks.air);
    final tiedEngine = WorldTickEngine(maxFluidLevel: 1)..enqueue(50, 2, 50);
    _advance(tiedEngine, tied, 5);
    expect(Blocks.id(tied.blockAt(51, 2, 50)), Blocks.water);
    expect(Blocks.id(tied.blockAt(49, 2, 50)), Blocks.water);
    expect(tied.blockAt(50, 2, 49), Blocks.air);
    expect(tied.blockAt(50, 2, 51), Blocks.air);
  });

  test('an obstruction schedules deterministic reflow around the blockage', () {
    final world = _dropSearchFixture(centerX: 70, centerZ: 70)
      ..setBlock(75, 1, 70, Blocks.air);
    final engine = WorldTickEngine(maxFluidLevel: 2)..enqueue(70, 2, 70);
    _advance(engine, world, 5);
    expect(Blocks.id(world.blockAt(71, 2, 70)), Blocks.water);

    world.setBlock(71, 2, 70, Blocks.stone);
    engine.enqueueAround(71, 2, 70);
    _drain(engine, world, budget: 256, maxTicks: 300);

    expect(world.blockAt(71, 2, 70), Blocks.stone);
    expect(
      [
        world.blockAt(69, 2, 70),
        world.blockAt(70, 2, 69),
        world.blockAt(70, 2, 71),
      ].where((raw) => Blocks.id(raw) == Blocks.water),
      isNotEmpty,
    );
  });

  test('a finite basin fills and reaches stable scheduler idle', () {
    final world = VoxelWorld();
    for (var z = 28; z <= 32; z++) {
      for (var x = 28; x <= 32; x++) {
        world.setBlock(x, 0, z, Blocks.stone);
        if (x == 28 || x == 32 || z == 28 || z == 32) {
          world.setBlock(x, 1, z, Blocks.stone);
        }
      }
    }
    world.setBlock(30, 1, 30, Blocks.water);
    final engine = WorldTickEngine()..enqueue(30, 1, 30);

    _drain(engine, world, budget: 256, maxTicks: 300);

    for (var z = 29; z <= 31; z++) {
      for (var x = 29; x <= 31; x++) {
        expect(Blocks.id(world.blockAt(x, 1, z)), Blocks.water);
      }
    }
    expect(engine.isIdle, isTrue);
  });

  test('two supported water sources form a source', () {
    final world = VoxelWorld()
      ..setBlock(30, 0, 30, Blocks.stone)
      ..setBlock(29, 1, 30, Blocks.water)
      ..setBlock(31, 1, 30, Blocks.water)
      ..setBlock(30, 1, 30, Blocks.pack(Blocks.water, 7));
    final engine = WorldTickEngine()..enqueue(30, 1, 30);

    _advance(engine, world, 5);

    expect(world.blockAt(30, 1, 30), Blocks.water);
  });

  test('infinite water requires opaque support or source water below', () {
    final unsupported = VoxelWorld()
      ..setBlock(30, 0, 30, Blocks.glass)
      ..setBlock(29, 1, 30, Blocks.water)
      ..setBlock(31, 1, 30, Blocks.water)
      ..setBlock(30, 1, 30, Blocks.pack(Blocks.water, 7));
    final unsupportedEngine = WorldTickEngine()..enqueue(30, 1, 30);
    _advance(unsupportedEngine, unsupported, 5);
    expect(unsupported.blockAt(30, 1, 30), Blocks.pack(Blocks.water, 1));

    final waterSupported = VoxelWorld()
      ..setBlock(30, 1, 30, Blocks.water)
      ..setBlock(29, 2, 30, Blocks.water)
      ..setBlock(31, 2, 30, Blocks.water)
      ..setBlock(30, 2, 30, Blocks.pack(Blocks.water, 7));
    final waterSupportedEngine = WorldTickEngine()..enqueue(30, 2, 30);
    _advance(waterSupportedEngine, waterSupported, 5);
    expect(waterSupported.blockAt(30, 2, 30), Blocks.water);
  });

  test('lava never creates an infinite source', () {
    final world = VoxelWorld()
      ..setBlock(30, 0, 30, Blocks.stone)
      ..setBlock(29, 1, 30, Blocks.lava)
      ..setBlock(31, 1, 30, Blocks.lava)
      ..setBlock(30, 1, 30, Blocks.pack(Blocks.lava, 6));
    final engine = WorldTickEngine()..enqueue(30, 1, 30);

    _advance(engine, world, 30);

    expect(world.blockAt(30, 1, 30), Blocks.pack(Blocks.lava, 2));
  });

  test('fluid displaces plants but solid blocks remain dams', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 30, centerZ: 30, radius: 2);
    world
      ..setBlock(30, 1, 30, Blocks.water)
      ..setBlock(31, 1, 30, Blocks.flowerRose)
      ..setBlock(29, 1, 30, Blocks.stone);
    final engine = WorldTickEngine()..enqueue(30, 1, 30);

    _advance(engine, world, 5);

    expect(world.blockAt(31, 1, 30), Blocks.pack(Blocks.water, 1));
    expect(world.blockAt(29, 1, 30), Blocks.stone);
  });

  test('sponge absorbs water in a radius-two cube and blocks refill', () {
    final world = VoxelWorld()
      ..setBlock(10, 10, 10, Blocks.sponge)
      ..setBlock(12, 12, 12, Blocks.water)
      ..setBlock(13, 10, 10, Blocks.water);
    final engine = WorldTickEngine()..enqueue(10, 10, 10);

    final changes = engine.tick(world, 1);

    expect(world.blockAt(12, 12, 12), Blocks.air);
    expect(world.blockAt(13, 10, 10), Blocks.water);
    expect(changes.changes, hasLength(1));

    engine.enqueue(13, 10, 10);
    _drain(engine, world, budget: 128);
    expect(world.blockAt(12, 10, 10), isNot(Blocks.water));

    world.setBlock(10, 10, 10, Blocks.air);
    engine.enqueueAround(10, 10, 10);
    _drain(engine, world, budget: 128, maxTicks: 300);
    expect(Blocks.id(world.blockAt(12, 10, 10)), Blocks.water);
  });

  test('equal due ticks use insertion sequence', () {
    final world = VoxelWorld()
      ..setBlock(10, 5, 10, Blocks.sponge)
      ..setBlock(11, 5, 10, Blocks.water)
      ..setBlock(30, 5, 30, Blocks.sponge)
      ..setBlock(31, 5, 30, Blocks.water);
    final engine = WorldTickEngine()
      ..enqueue(10, 5, 10)
      ..enqueue(30, 5, 30);

    engine.tick(world, 1);
    expect(world.blockAt(11, 5, 10), Blocks.air);
    expect(world.blockAt(31, 5, 30), Blocks.water);

    engine.tick(world, 1);
    expect(world.blockAt(31, 5, 30), Blocks.air);
  });

  test('loaded dry sponge removal wakes a source at radius three', () {
    final world = VoxelWorld();
    for (var x = 10; x <= 14; x++) {
      world.setBlock(x, 9, 10, Blocks.stone);
    }
    world
      ..setBlock(10, 10, 10, Blocks.sponge)
      ..setBlock(13, 10, 10, Blocks.water)
      ..setBlock(14, 10, 10, Blocks.stone)
      ..setBlock(13, 10, 9, Blocks.stone)
      ..setBlock(13, 10, 11, Blocks.stone);
    final before = _localSignature(world, 9, 15, 8, 11, 8, 12);
    final engine = WorldTickEngine();

    expect(engine.prime(world), 0, reason: 'loaded topology is stable');
    expect(_localSignature(world, 9, 15, 8, 11, 8, 12), before);

    world.setBlock(10, 10, 10, Blocks.air);
    engine.enqueueAround(10, 10, 10);
    _drain(engine, world, budget: 256, maxTicks: 300);

    expect(Blocks.id(world.blockAt(12, 10, 10)), Blocks.water);
  });

  test('internal TNT removal reconciles sponge state and wakes refill', () {
    final world = VoxelWorld();
    for (var x = 19; x <= 24; x++) {
      world.setBlock(x, 9, 20, Blocks.bedrock);
    }
    world
      ..setBlock(19, 10, 20, Blocks.tnt)
      ..setBlock(20, 10, 20, Blocks.sponge)
      ..setBlock(23, 10, 20, Blocks.water)
      ..setBlock(21, 10, 20, Blocks.bedrock)
      ..setBlock(22, 10, 19, Blocks.bedrock)
      ..setBlock(22, 10, 21, Blocks.bedrock)
      ..setBlock(24, 10, 20, Blocks.bedrock)
      ..setBlock(23, 10, 19, Blocks.bedrock)
      ..setBlock(23, 10, 21, Blocks.bedrock);
    final engine = WorldTickEngine(tntFuseTicks: 1);

    expect(engine.prime(world), 0, reason: 'sponge-blocked source is stable');
    expect(engine.activateTnt(world, 19, 10, 20), isTrue);
    engine.tick(world, 256);

    expect(world.blockAt(20, 10, 20), Blocks.air);
    expect(world.blockAt(22, 10, 20), Blocks.air);
    _drain(engine, world, budget: 256, maxTicks: 300);
    expect(Blocks.id(world.blockAt(22, 10, 20)), Blocks.water);
  });

  test('capacity pressure preserves external sponge place/remove state', () {
    final world = VoxelWorld();
    for (var x = 40; x <= 44; x++) {
      world.setBlock(x, 9, 40, Blocks.bedrock);
    }
    world
      ..setBlock(43, 10, 40, Blocks.water)
      ..setBlock(41, 10, 40, Blocks.bedrock)
      ..setBlock(42, 10, 39, Blocks.bedrock)
      ..setBlock(42, 10, 41, Blocks.bedrock)
      ..setBlock(44, 10, 40, Blocks.bedrock)
      ..setBlock(43, 10, 39, Blocks.bedrock)
      ..setBlock(43, 10, 41, Blocks.bedrock);
    final engine = WorldTickEngine(maxQueue: 1);

    expect(engine.enqueue(1, 1, 1), isTrue);
    world.setBlock(40, 10, 40, Blocks.sponge);
    expect(engine.enqueue(40, 10, 40), isFalse);
    engine.tick(world, 1);
    expect(engine.isIdle, isTrue, reason: 'dry sponge needs no active work');
    expect(world.blockAt(42, 10, 40), Blocks.air);

    expect(engine.enqueue(1, 1, 1), isTrue);
    world.setBlock(40, 10, 40, Blocks.air);
    expect(engine.enqueue(40, 10, 40), isFalse);
    engine.tick(world, 1);
    expect(engine.isIdle, isFalse, reason: 'retry scan must wake radius three');

    _drain(engine, world, budget: 1, maxTicks: 1000);
    expect(Blocks.id(world.blockAt(42, 10, 40)), Blocks.water);
    expect(engine.retryChunkCount, 0);
    expect(engine.droppedUpdates, greaterThanOrEqualTo(2));
  });

  test('TNT fuse is grouped and radius-three explosion preserves specials', () {
    final world = VoxelWorld()
      ..setBlock(30, 10, 30, Blocks.tnt)
      ..setBlock(31, 10, 30, Blocks.stone)
      ..setBlock(33, 10, 30, Blocks.stone)
      ..setBlock(34, 10, 30, Blocks.stone)
      ..setBlock(29, 10, 30, Blocks.bedrock);
    final engine = WorldTickEngine(tntFuseTicks: 3)
      ..activateTnt(world, 30, 10, 30);

    final firstFuse = engine.tick(world, 1);
    expect(Blocks.id(world.blockAt(30, 10, 30)), Blocks.tnt);
    expect(Blocks.meta(world.blockAt(30, 10, 30)), 1);
    expect(firstFuse.changes, hasLength(1));

    _drain(engine, world, budget: 128);

    expect(world.blockAt(30, 10, 30), Blocks.air);
    expect(world.blockAt(31, 10, 30), Blocks.air);
    expect(world.blockAt(33, 10, 30), Blocks.air);
    expect(world.blockAt(34, 10, 30), Blocks.stone);
    expect(world.blockAt(29, 10, 30), Blocks.bedrock);
  });

  test('restored TNT at the first fuse frame stays scheduled and explodes', () {
    final world = VoxelWorld()
      ..setBlock(30, 10, 30, Blocks.pack(Blocks.tnt, 1));
    final engine = WorldTickEngine(maxQueue: 7, tntFuseTicks: 3);

    expect(engine.activateTnt(world, 30, 10, 30), isTrue);

    final firstFuse = engine.tick(world, 1);

    expect(firstFuse.isEmpty, isTrue, reason: 'restored metadata is already 1');
    expect(engine.pendingCount, 1, reason: 'the active fuse must be requeued');
    expect(engine.primedTntCount, 1);
    expect(engine.pendingCount, lessThanOrEqualTo(engine.maxQueue));

    _drain(engine, world, budget: 1);

    expect(world.blockAt(30, 10, 30), Blocks.air);
    expect(engine.primedTntCount, 0);
    expect(engine.isIdle, isTrue);
    expect(engine.droppedUpdates, 0);
  });

  test('ordinary queued TNT stays inert until explicitly activated', () {
    final world = VoxelWorld()..setBlock(30, 10, 30, Blocks.tnt);
    final engine = WorldTickEngine()..enqueue(30, 10, 30);

    expect(engine.tick(world, 1).isEmpty, isTrue);
    expect(world.blockAt(30, 10, 30), Blocks.tnt);
    expect(engine.primedTntCount, 0);
  });

  test('same input and budget produce identical deterministic ticks', () {
    final a = _fluidFixture();
    final b = _fluidFixture();
    final engineA = WorldTickEngine(maxFluidLevel: 2)..enqueue(40, 1, 40);
    final engineB = WorldTickEngine(maxFluidLevel: 2)..enqueue(40, 1, 40);

    for (var tick = 0; tick < 20; tick++) {
      final changesA = engineA.tick(a, 5);
      final changesB = engineB.tick(b, 5);
      expect(_changeSignature(changesA), _changeSignature(changesB));
      expect(engineA.pendingCount, engineB.pendingCount);
      if (engineA.pendingCount == 0) break;
    }
    expect(_worldSignature(a), _worldSignature(b));
  });

  test('one liquid user edit and all consequences form one undo group', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 90, centerZ: 90, radius: 4);
    final before = _localSignature(world, 86, 94, 0, 2, 86, 94);
    final history = EditHistory()..beginGroup();
    final engine = WorldTickEngine(maxFluidLevel: 2);
    final userEdit = WorldChangeSetBuilder(world)..set(90, 1, 90, Blocks.water);
    final userChanges = userEdit.build();
    history.record(userChanges);
    for (final change in userChanges.changes) {
      engine.enqueueAround(change.x, change.y, change.z);
    }

    for (var tick = 0; tick < 500 && !engine.isIdle; tick++) {
      history.record(engine.tick(world, 256));
    }

    expect(engine.isIdle, isTrue);
    expect(history.isGroupOpen, isTrue);
    expect(history.undoLength, 0);
    expect(_liquidCount(world, Blocks.water, 86, 94, 1, 86, 94), 13);

    history.endGroup();
    expect(history.undoLength, 1);
    final undone = history.undo(world);

    expect(undone.changes, hasLength(13));
    expect(_localSignature(world, 86, 94, 0, 2, 86, 94), before);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isTrue);
  });

  test('opposite enqueue order converges to the same topology', () {
    final a = _twoSourceFixture();
    final b = _twoSourceFixture();
    final engineA = WorldTickEngine(maxFluidLevel: 3)
      ..enqueue(39, 1, 40)
      ..enqueue(41, 1, 40);
    final engineB = WorldTickEngine(maxFluidLevel: 3)
      ..enqueue(41, 1, 40)
      ..enqueue(39, 1, 40);

    _drain(engineA, a, budget: 256, maxTicks: 500);
    _drain(engineB, b, budget: 256, maxTicks: 500);

    expect(
      _localSignature(a, 35, 45, 0, 2, 35, 45),
      _localSignature(b, 35, 45, 0, 2, 35, 45),
    );
  });

  test('prime is read-only and schedules only reconvergence work', () {
    final world = VoxelWorld()
      ..setBlock(50, 0, 50, Blocks.stone)
      ..setBlock(49, 1, 50, Blocks.water)
      ..setBlock(50, 1, 50, Blocks.pack(Blocks.water, 7));
    final before = _localSignature(world, 47, 52, 0, 2, 47, 52);
    final revisions = [for (final chunk in world.chunks) chunk.revision];
    final engine = WorldTickEngine();

    final scheduled = engine.prime(world);

    expect(scheduled, greaterThan(0));
    expect(engine.currentTick, 0);
    expect(_localSignature(world, 47, 52, 0, 2, 47, 52), before);
    expect([for (final chunk in world.chunks) chunk.revision], revisions);
    expect(engine.prime(world), 0, reason: 'prime must deduplicate identities');

    _drain(engine, world, budget: 256, maxTicks: 300);
    expect(world.blockAt(50, 1, 50), Blocks.pack(Blocks.water, 1));

    final stable = VoxelWorld()
      ..setBlock(60, 0, 60, Blocks.stone)
      ..setBlock(60, 1, 60, Blocks.water)
      ..setBlock(59, 1, 60, Blocks.stone)
      ..setBlock(61, 1, 60, Blocks.stone)
      ..setBlock(60, 1, 59, Blocks.stone)
      ..setBlock(60, 1, 61, Blocks.stone);
    expect(WorldTickEngine().prime(stable), 0);
  });

  test('capacity one and two converge to the unbounded final topology', () {
    final reference = _boundedFluidFixture();
    final referenceEngine = WorldTickEngine(maxFluidLevel: 2)
      ..enqueueAround(70, 1, 70);
    _drain(referenceEngine, reference, budget: 256, maxTicks: 1000);
    final expected = _localSignature(reference, 66, 74, 0, 2, 66, 74);

    for (final capacity in const [1, 2]) {
      final world = _boundedFluidFixture();
      final engine = WorldTickEngine(maxQueue: capacity, maxFluidLevel: 2)
        ..enqueueAround(70, 1, 70);

      _drain(engine, world, budget: 256, maxTicks: 3000);

      expect(
        _localSignature(world, 66, 74, 0, 2, 66, 74),
        expected,
        reason: 'capacity $capacity',
      );
      expect(engine.pendingCount, lessThanOrEqualTo(capacity));
      expect(engine.retryChunkCount, 0);
      expect(engine.droppedUpdates, greaterThan(0));
    }
  });

  test('keyed lava defer is deterministic and load prime reconverges', () {
    int? delayedSeed;
    final probe = _lavaIncreaseFixture(seed: 0);
    for (var seed = 0; seed < 16; seed++) {
      probe.seed = seed;
      probe.setBlock(80, 1, 80, Blocks.pack(Blocks.lava, 1));
      final engine = WorldTickEngine()..enqueue(80, 1, 80);
      _advance(engine, probe, 30);
      if (Blocks.meta(probe.blockAt(80, 1, 80)) == 1) {
        delayedSeed = seed;
        break;
      }
    }
    expect(delayedSeed, isNotNull);

    final a = _lavaIncreaseFixture(seed: delayedSeed!);
    final same = _lavaIncreaseFixture(seed: delayedSeed);
    final engineA = WorldTickEngine()..enqueue(80, 1, 80);
    final engineSame = WorldTickEngine()..enqueue(80, 1, 80);
    _advance(engineA, a, 30);
    _advance(engineSame, same, 30);
    expect(a.blockAt(80, 1, 80), Blocks.pack(Blocks.lava, 1));
    expect(same.blockAt(80, 1, 80), a.blockAt(80, 1, 80));
    expect(engineA.pendingCount, 1, reason: 'denied advance must retry');
    expect(engineSame.pendingCount, engineA.pendingCount);

    final loaded = _lavaIncreaseFixture(seed: delayedSeed);
    final loadedEngine = WorldTickEngine();
    expect(loadedEngine.prime(loaded), greaterThan(0));

    _drain(engineA, a, budget: 256, maxTicks: 300);
    _drain(engineSame, same, budget: 256, maxTicks: 300);
    _drain(loadedEngine, loaded, budget: 256, maxTicks: 300);

    expect(a.blockAt(80, 1, 80), Blocks.pack(Blocks.lava, 2));
    expect(
      _localSignature(a, 77, 82, 0, 2, 77, 83),
      _localSignature(same, 77, 82, 0, 2, 77, 83),
    );
    expect(
      _localSignature(a, 77, 82, 0, 2, 77, 83),
      _localSignature(loaded, 77, 82, 0, 2, 77, 83),
    );
  });

  test('queue capacity is a hard bound', () {
    final engine = WorldTickEngine(maxQueue: 2);
    expect(engine.enqueue(1, 1, 1), isTrue);
    expect(engine.enqueue(2, 1, 1), isTrue);
    expect(engine.enqueue(3, 1, 1), isFalse);
    expect(engine.pendingCount, 2);
    expect(engine.droppedUpdates, 1);
  });
}

VoxelWorld _fluidFixture() {
  final world = VoxelWorld();
  _fillFloor(world, centerX: 40, centerZ: 40, radius: 5);
  world.setBlock(40, 1, 40, Blocks.water);
  return world;
}

VoxelWorld _twoSourceFixture() {
  final world = VoxelWorld();
  _fillFloor(world, centerX: 40, centerZ: 40, radius: 5);
  world
    ..setBlock(39, 1, 40, Blocks.water)
    ..setBlock(41, 1, 40, Blocks.water);
  return world;
}

VoxelWorld _boundedFluidFixture() {
  final world = VoxelWorld();
  _fillFloor(world, centerX: 70, centerZ: 70, radius: 4);
  world.setBlock(70, 1, 70, Blocks.water);
  return world;
}

VoxelWorld _dropSearchFixture({required int centerX, required int centerZ}) {
  final world = VoxelWorld();
  for (var z = centerZ - 6; z <= centerZ + 6; z++) {
    for (var x = centerX - 6; x <= centerX + 6; x++) {
      world.setBlock(x, 1, z, Blocks.stone);
    }
  }
  world.setBlock(centerX, 2, centerZ, Blocks.water);
  return world;
}

VoxelWorld _lavaIncreaseFixture({required int seed}) {
  final world = VoxelWorld()..seed = seed;
  _fillFloor(world, centerX: 80, centerZ: 80, radius: 3);
  world
    ..setBlock(79, 1, 80, Blocks.lava)
    ..setBlock(80, 1, 80, Blocks.pack(Blocks.lava, 1))
    ..setBlock(78, 1, 80, Blocks.stone)
    ..setBlock(79, 1, 79, Blocks.stone)
    ..setBlock(79, 1, 81, Blocks.stone)
    ..setBlock(80, 1, 79, Blocks.stone)
    ..setBlock(80, 1, 81, Blocks.stone)
    ..setBlock(81, 1, 80, Blocks.stone);
  return world;
}

void _fillFloor(
  VoxelWorld world, {
  required int centerX,
  required int centerZ,
  required int radius,
}) {
  for (var z = centerZ - radius; z <= centerZ + radius; z++) {
    for (var x = centerX - radius; x <= centerX + radius; x++) {
      world.setBlock(x, 0, z, Blocks.stone);
    }
  }
}

void _advance(
  WorldTickEngine engine,
  VoxelWorld world,
  int ticks, {
  int budget = 256,
}) {
  for (var tick = 0; tick < ticks; tick++) {
    engine.tick(world, budget);
  }
}

void _drain(
  WorldTickEngine engine,
  VoxelWorld world, {
  required int budget,
  int maxTicks = 200,
}) {
  for (var tick = 0; tick < maxTicks && !engine.isIdle; tick++) {
    engine.tick(world, budget);
  }
  expect(engine.isIdle, isTrue, reason: 'simulation scheduler did not drain');
}

int _liquidCount(
  VoxelWorld world,
  int liquidId,
  int minX,
  int maxX,
  int y,
  int minZ,
  int maxZ,
) {
  var count = 0;
  for (var z = minZ; z <= maxZ; z++) {
    for (var x = minX; x <= maxX; x++) {
      if (Blocks.id(world.blockAt(x, y, z)) == liquidId) count++;
    }
  }
  return count;
}

List<int> _localSignature(
  VoxelWorld world,
  int minX,
  int maxX,
  int minY,
  int maxY,
  int minZ,
  int maxZ,
) => [
  for (var y = minY; y <= maxY; y++)
    for (var z = minZ; z <= maxZ; z++)
      for (var x = minX; x <= maxX; x++) world.blockAt(x, y, z),
];

List<int> _changeSignature(WorldChangeSet changes) => [
  for (final change in changes.changes)
    Object.hash(change.x, change.y, change.z, change.oldRaw, change.newRaw),
];

int _worldSignature(VoxelWorld world) {
  var hash = 0;
  for (final chunk in world.chunks) {
    for (final raw in chunk.blocks) {
      hash = Object.hash(hash, raw);
    }
  }
  return hash;
}
