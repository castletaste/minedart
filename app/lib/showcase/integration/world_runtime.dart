import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:minedart_core/minedart_core.dart' show WorldDims;

import '../../audio/audio.dart';
import '../../data/worlds/world_models.dart';
import '../../data/worlds/world_repository.dart';
import '../../game/minedart_game.dart';
import '../../pipeline/mesh_pipeline.dart';
import 'repository_autosaver.dart';

final class WorldRuntime {
  WorldRuntime._({
    required this.repository,
    required this.document,
    required this.pipeline,
    required this.game,
    required this.autosaver,
  });

  static Future<WorldRuntime> create({
    required WorldRepository repository,
    required WorldDocument document,
    required AudioServiceApi audio,
  }) async {
    final world = document.toVoxelWorld();
    final pipeline = MeshPipeline(workers: 3);
    await pipeline.start();
    final spawn = document.metadata.spawn;
    final game = MinedartGame(
      world: world,
      pipeline: pipeline,
      audio: audio,
      initialFeet: validWorldSpawn(spawn)
          ? Vector3(spawn.x, spawn.y, spawn.z)
          : null,
      initialYaw: spawn.yaw,
      initialPitch: spawn.pitch,
    );
    final autosaver = RepositoryAutosaver(
      repository: repository,
      world: world,
      metadata: document.metadata,
      readSpawn: () => WorldSpawn(
        x: game.spawnFeet.x,
        y: game.spawnFeet.y,
        z: game.spawnFeet.z,
        yaw: game.cameraYaw,
        pitch: game.cameraPitch,
      ),
    )..start();
    return WorldRuntime._(
      repository: repository,
      document: document,
      pipeline: pipeline,
      game: game,
      autosaver: autosaver,
    );
  }

  final WorldRepository repository;
  final WorldDocument document;
  final MeshPipeline pipeline;
  final MinedartGame game;
  final RepositoryAutosaver autosaver;

  String get worldId => autosaver.metadata.id;
  WorldMetadata get metadata => autosaver.metadata;

  Future<void> close({bool save = true}) async {
    try {
      if (save) await autosaver.saveNow();
      await autosaver.stopAndWait();
    } finally {
      autosaver.stop();
      pipeline.dispose();
    }
  }
}

bool validWorldSpawn(WorldSpawn spawn) =>
    spawn.x >= 0 &&
    spawn.z >= 0 &&
    spawn.y > 0 &&
    spawn.x < WorldDims.worldBlocksX &&
    spawn.y < WorldDims.worldBlocksY &&
    spawn.z < WorldDims.worldBlocksZ;
