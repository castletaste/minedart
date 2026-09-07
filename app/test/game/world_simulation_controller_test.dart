import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/game/world_simulation_controller.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  test('requires a finite positive fixed tick step', () {
    for (final tickStep in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      0,
      -0.05,
    ]) {
      expect(
        () =>
            WorldSimulationController(world: VoxelWorld(), tickStep: tickStep),
        throwsArgumentError,
      );
    }
  });

  test('ignores non-finite and non-positive frame deltas', () {
    final world = VoxelWorld()..setBlock(10, 2, 10, Blocks.sand);
    final simulation = WorldSimulationController(world: world)..initialize();

    for (final dt in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      0,
      -1,
    ]) {
      simulation.advance(dt);
    }

    expect(simulation.ticks.currentTick, 0);
    expect(world.blockAt(10, 2, 10), Blocks.sand);
  });

  test('loaded simulation work converges without creating player history', () {
    final world = VoxelWorld()..setBlock(10, 3, 10, Blocks.sand);
    final observed = <WorldChangeSet>[];
    final simulation = WorldSimulationController(
      world: world,
      onChanges: observed.add,
    )..initialize();

    _advanceUntilIdle(simulation);

    expect(world.blockAt(10, 0, 10), Blocks.sand);
    expect(observed, isNotEmpty);
    expect(simulation.history.canUndo, isFalse);
  });

  test('undo reconvergence preserves redo and adds no hidden history', () {
    final world = VoxelWorld()..setBlock(12, 2, 12, Blocks.sand);
    final simulation = WorldSimulationController(world: world);
    final edit = WorldChangeSetBuilder(world)..set(12, 1, 12, Blocks.stone);
    simulation.recordUserEdit(edit.build());

    final undone = simulation.undo();

    expect(undone.isNotEmpty, isTrue);
    expect(world.blockAt(12, 1, 12), Blocks.air);
    expect(simulation.history.canRedo, isTrue);
    _advanceUntilIdle(simulation);
    expect(world.blockAt(12, 0, 12), Blocks.sand);
    expect(simulation.history.canUndo, isFalse);
    expect(simulation.history.canRedo, isTrue);

    final redone = simulation.redo();
    expect(redone.isNotEmpty, isTrue);
    expect(world.blockAt(12, 1, 12), Blocks.stone);
    expect(simulation.history.undoLength, 1);
    expect(simulation.history.canRedo, isFalse);
  });

  test('one player edit and its simulation cascade form one undo group', () {
    final world = VoxelWorld();
    _fillFloor(world, centerX: 90, centerZ: 90, radius: 4);
    final simulation = WorldSimulationController(
      world: world,
      ticks: WorldTickEngine(maxFluidLevel: 2),
    );
    final edit = WorldChangeSetBuilder(world)..set(90, 1, 90, Blocks.water);

    simulation.recordUserEdit(edit.build());
    _advanceUntilIdle(simulation);

    expect(simulation.history.undoLength, 1);
    final undone = simulation.undo();
    expect(undone.changes, hasLength(13));
    expect(simulation.history.canUndo, isFalse);
    expect(simulation.history.canRedo, isTrue);
  });

  test('an activated TNT fuse and explosion remain one undo group', () {
    final world = VoxelWorld()..setBlock(24, 8, 24, Blocks.tnt);
    final simulation = WorldSimulationController(
      world: world,
      ticks: WorldTickEngine(tntFuseTicks: 2, explosionRadius: 0),
    );

    expect(simulation.ticks.activateTnt(world, 24, 8, 24), isTrue);
    simulation.beginUserCascade();
    _advanceUntilIdle(simulation);

    expect(world.blockAt(24, 8, 24), Blocks.air);
    expect(simulation.history.undoLength, 1);
    simulation.undo();
    expect(world.blockAt(24, 8, 24), Blocks.tnt);
  });

  test('no-op history replay still re-primes persisted world work', () {
    final world = VoxelWorld()..setBlock(14, 2, 14, Blocks.gravel);
    final simulation = WorldSimulationController(world: world);

    expect(simulation.undo().isEmpty, isTrue);
    expect(simulation.ticks.isIdle, isFalse);
    _advanceUntilIdle(simulation);

    expect(world.blockAt(14, 0, 14), Blocks.gravel);
    expect(simulation.history.canUndo, isFalse);
    expect(simulation.history.canRedo, isFalse);
  });

  test('advance enforces per-tick work and per-frame step bounds', () {
    final world = VoxelWorld()
      ..setBlock(10, 10, 10, Blocks.pack(Blocks.tnt, 1))
      ..setBlock(30, 10, 10, Blocks.pack(Blocks.tnt, 1));
    final observed = <WorldChangeSet>[];
    final simulation = WorldSimulationController(
      world: world,
      ticks: WorldTickEngine(tntFuseTicks: 1),
      tickBudget: 1,
      onChanges: observed.add,
    )..initialize();

    simulation.advance(0.05);

    expect(simulation.ticks.currentTick, 1);
    expect(observed, hasLength(1));
    expect(world.blockAt(10, 10, 10), Blocks.air);
    expect(Blocks.id(world.blockAt(30, 10, 10)), Blocks.tnt);

    simulation.advance(1);
    expect(simulation.ticks.currentTick, 6);
    expect(world.blockAt(30, 10, 10), Blocks.air);
    expect(simulation.history.canUndo, isFalse);
  });
}

void _advanceUntilIdle(WorldSimulationController simulation) {
  for (var frame = 0; frame < 500 && !simulation.ticks.isIdle; frame++) {
    simulation.advance(0.05);
  }
  expect(simulation.ticks.isIdle, isTrue);
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
