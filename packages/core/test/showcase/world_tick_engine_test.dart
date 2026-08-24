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

  test('fluid metadata bounds horizontal spread and queue drains', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 20, centerZ: 20, radius: 5);
    world.setBlock(20, 1, 20, Blocks.water);
    final engine = WorldTickEngine(maxFluidLevel: 2)..enqueue(20, 1, 20);

    _drain(engine, world, budget: 128);

    var waterCount = 0;
    for (var z = 15; z <= 25; z++) {
      for (var x = 15; x <= 25; x++) {
        final raw = world.blockAt(x, 1, z);
        if (Blocks.id(raw) != Blocks.water) continue;
        waterCount++;
        final distance = (x - 20).abs() + (z - 20).abs();
        expect(distance, lessThanOrEqualTo(2));
        expect(Blocks.meta(raw), distance);
      }
    }
    expect(waterCount, 13);
    expect(engine.pendingCount, 0);
  });

  test('water-lava contact always solidifies the lava cell as cobblestone', () {
    final world = VoxelWorld()
      ..setBlock(10, 1, 10, Blocks.water)
      ..setBlock(11, 1, 10, Blocks.lava);
    final engine = WorldTickEngine()..enqueue(11, 1, 10);

    final changes = engine.tick(world, 1);

    expect(world.blockAt(10, 1, 10), Blocks.water);
    expect(world.blockAt(11, 1, 10), Blocks.cobblestone);
    expect(changes.changes.single.oldRaw, Blocks.lava);
    expect(changes.changes.single.newRaw, Blocks.cobblestone);
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

void _drain(WorldTickEngine engine, VoxelWorld world, {required int budget}) {
  for (var tick = 0; tick < 200 && engine.pendingCount > 0; tick++) {
    engine.tick(world, budget);
  }
  expect(engine.pendingCount, 0, reason: 'simulation queue did not drain');
}

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
