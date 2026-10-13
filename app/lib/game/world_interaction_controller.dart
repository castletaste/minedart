import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart';

import '../audio/audio.dart';
import '../hud/hud_state.dart';
import '../interact/block_interactor.dart';
import 'world_effects.dart';
import 'world_simulation_controller.dart';

/// Owns block edits, deterministic simulation, and their gameplay effects.
///
/// The game shell supplies the current eye ray and effect callbacks. This
/// keeps world mutation and history out of the Flame component while retaining
/// one place for break/place/TNT/undo/redo behavior.
final class WorldInteractionController {
  WorldInteractionController({
    required VoxelWorld world,
    required this.hud,
    required this.effects,
  }) : voxelWorld = world,
       interactor = BlockInteractor(world: world, onDirty: effects.remesh) {
    simulation = WorldSimulationController(
      world: world,
      onChanges: _applySimulationChanges,
    );
  }

  final VoxelWorld voxelWorld;
  final HudState hud;
  final BlockInteractor interactor;
  final WorldEffects effects;
  late final WorldSimulationController simulation;

  EditHistory get editHistory => simulation.history;
  WorldTickEngine get worldTicks => simulation.ticks;

  void initialize() => simulation.initialize();

  void advance(double dt) => simulation.advance(dt);

  void breakTarget(Vector3 eye, Vector3 look) {
    final hit = interactor.target(eye, look);
    final brokenBlockId = hit == null
        ? Blocks.air
        : Blocks.id(voxelWorld.blockAt(hit.x, hit.y, hit.z));
    if (hit != null && brokenBlockId == Blocks.tnt) {
      if (worldTicks.activateTnt(voxelWorld, hit.x, hit.y, hit.z)) {
        simulation.beginUserCascade();
        hud.recordAction('tnt fuse ${hit.x}/${hit.y}/${hit.z}');
        effects.audio(
          AudioCue.tntFuse,
          seed: _editAudioSeed(hit.x, hit.y, hit.z),
        );
      }
      return;
    }

    final result = interactor.breakBlock(eye, look);
    hud.recordAction(
      result.changed
          ? 'broke ${result.x}/${result.y}/${result.z}'
          : 'break none',
    );
    if (!result.changed) return;

    simulation.recordUserEdit(result.changeSet);
    effects.particle(
      blockId: brokenBlockId,
      x: result.x,
      y: result.y,
      z: result.z,
    );
    effects.audio(
      AudioCue.forBlock(brokenBlockId, BlockAudioAction.breakBlock),
      seed: _editAudioSeed(result.x, result.y, result.z),
    );
  }

  void placeSelected(Vector3 eye, Vector3 look, int blockId) {
    final result = interactor.placeBlock(eye, look, blockId);
    hud.recordAction(
      result.changed
          ? 'placed ${result.x}/${result.y}/${result.z}'
          : 'place none',
    );
    if (!result.changed) return;

    simulation.recordUserEdit(result.changeSet);
    effects.particle(
      blockId: result.blockId,
      x: result.x,
      y: result.y,
      z: result.z,
      count: 3,
    );
    effects.audio(
      AudioCue.forBlock(result.blockId, BlockAudioAction.placeBlock),
      seed: _editAudioSeed(result.x, result.y, result.z),
    );
  }

  void undo() => _applyHistoryResult(simulation.undo(), 'undo');

  void redo() => _applyHistoryResult(simulation.redo(), 'redo');

  void _applySimulationChanges(WorldChangeSet changes) {
    effects.remesh(changes.dirtyChunks);
    final exploded = shouldPlayExplosionForWorldChanges(changes.changes);
    var removed = 0;
    for (final change in changes.changes) {
      final oldId = Blocks.id(change.oldRaw);
      if (oldId != Blocks.air && Blocks.id(change.newRaw) == Blocks.air) {
        removed++;
        effects.particle(
          blockId: oldId,
          x: change.x,
          y: change.y,
          z: change.z,
          count: 2,
        );
      }
    }
    if (exploded) effects.audio(AudioCue.explosion, seed: removed);
  }

  void _applyHistoryResult(WorldChangeSet changes, String action) {
    if (changes.isEmpty) {
      hud.recordAction('$action none');
      return;
    }
    effects.remesh(changes.dirtyChunks);
    hud.recordAction('$action ${changes.changes.length}');
  }
}

int _editAudioSeed(int x, int y, int z) =>
    x * 73856093 ^ y * 19349663 ^ z * 83492791;
