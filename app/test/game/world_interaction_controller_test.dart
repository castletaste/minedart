import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/audio/audio.dart';
import 'package:minedart/game/world_effects.dart';
import 'package:minedart/game/world_interaction_controller.dart';
import 'package:minedart/hud/hud_state.dart';
import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart';

VoxelWorld _flatWorld() {
  final world = VoxelWorld();
  for (var z = 8; z < 24; z++) {
    for (var x = 8; x < 24; x++) {
      for (var y = 0; y < 4; y++) {
        world.setBlock(x, y, z, Blocks.stone);
      }
    }
  }
  return world;
}

void main() {
  test(
    'break records history and forwards remesh, particle, and audio effects',
    () {
      final world = _flatWorld();
      final dirty = <int>{};
      final particles = <({int blockId, int x, int y, int z, int count})>[];
      final audio = <AudioCue>[];
      final controller = WorldInteractionController(
        world: world,
        hud: HudState(),
        effects: CallbackWorldEffects(
          onRemesh: dirty.addAll,
          onParticle:
              ({
                required blockId,
                required x,
                required y,
                required z,
                count = 8,
              }) => particles.add((
                blockId: blockId,
                x: x,
                y: y,
                z: z,
                count: count,
              )),
          onAudio: (cue, {seed = 0}) => audio.add(cue),
        ),
      );

      controller.breakTarget(Vector3(16.5, 6, 16.5), Vector3(0, -1, 0));

      expect(Blocks.id(world.blockAt(16, 3, 16)), Blocks.air);
      expect(dirty, isNotEmpty);
      expect(particles.single, (
        blockId: Blocks.stone,
        x: 16,
        y: 3,
        z: 16,
        count: 8,
      ));
      expect(audio, hasLength(1));
      controller.undo();
      expect(Blocks.id(world.blockAt(16, 3, 16)), Blocks.stone);
      expect(controller.editHistory.canRedo, isTrue);
    },
  );

  test(
    'place forwards the selected block and uses the smaller effect burst',
    () {
      final world = _flatWorld();
      final particles = <int>[];
      final controller = WorldInteractionController(
        world: world,
        hud: HudState(),
        effects: CallbackWorldEffects(
          onRemesh: (_) {},
          onParticle:
              ({
                required blockId,
                required x,
                required y,
                required z,
                count = 8,
              }) => particles.add(count),
          onAudio: (_, {seed = 0}) {},
        ),
      );

      controller.placeSelected(
        Vector3(16.5, 8, 16.5),
        Vector3(0, -1, 0),
        Blocks.brick,
      );

      expect(Blocks.id(world.blockAt(16, 4, 16)), Blocks.brick);
      expect(particles, [3]);
    },
  );
}
