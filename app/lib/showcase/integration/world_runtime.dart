import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:minedart_core/minedart_core.dart' show WorldDims, VoxelWorld;

import '../../audio/audio.dart';
import '../../input/game_input_service.dart';
import '../../data/worlds/world_models.dart';
import '../../data/worlds/world_repository.dart';
import '../../game/minedart_game.dart';
import '../../pipeline/mesh_pipeline.dart';
import 'repository_autosaver.dart';
import 'cleanup_errors.dart';
import 'world_session_coordinator.dart';

typedef RuntimeGameFactory =
    MinedartGame Function(
      VoxelWorld world,
      MeshPipelineBase pipeline,
      GameInputService input,
      WorldSpawn spawn,
    );

final class WorldRuntime implements WorldSessionRuntime {
  WorldRuntime._({
    required this.repository,
    required this.document,
    required this.pipeline,
    required this.game,
    required this.autosaver,
    required this.input,
  });

  static Future<WorldRuntime> create({
    required WorldRepository repository,
    required WorldDocument document,
    required AudioServiceApi audio,
    GameInputService? input,
    MeshPipelineBase Function()? pipelineFactory,
    RuntimeGameFactory? gameFactory,
  }) async {
    final service = input ?? GameInputService();
    MeshPipelineBase? pipeline;
    MinedartGame? game;
    try {
      pipeline = (pipelineFactory ?? () => MeshPipeline(workers: 3))();
      final world = document.toVoxelWorld();
      await pipeline.start();
      final spawn = document.metadata.spawn;
      game =
          (gameFactory?.call(world, pipeline, service, spawn) ??
                MinedartGame(
                  world: world,
                  pipeline: pipeline,
                  input: service,
                  audio: audio,
                  initialFeet: validWorldSpawn(spawn)
                      ? Vector3(spawn.x, spawn.y, spawn.z)
                      : null,
                  initialYaw: spawn.yaw,
                  initialPitch: spawn.pitch,
                ))
            ..pauseEngine();
      final createdGame = game;
      final autosaver = RepositoryAutosaver(
        repository: repository,
        world: world,
        metadata: document.metadata,
        onError: (_, _) {
          createdGame.diagnostics.updateState(
            storageReady: false,
            sessionFaulted: true,
          );
        },
        readSpawn: () => WorldSpawn(
          x: createdGame.spawnFeet.x,
          y: createdGame.spawnFeet.y,
          z: createdGame.spawnFeet.z,
          yaw: createdGame.cameraYaw,
          pitch: createdGame.cameraPitch,
        ),
      );
      return WorldRuntime._(
        repository: repository,
        document: document,
        pipeline: pipeline,
        game: game,
        autosaver: autosaver,
        input: service,
      );
    } catch (error) {
      final failures = CleanupErrors();
      try {
        game?.disposeSessionResources();
        await game?.meshCleanup;
      } catch (failure) {
        failures.add(failure);
      }
      try {
        await pipeline?.close();
      } catch (failure) {
        failures.add(failure);
      }
      if (input == null) {
        try {
          await service.close();
        } catch (failure) {
          failures.add(failure);
        }
      }
      if (!failures.isEmpty) {
        throw WorldSessionException(error, cleanupErrors: failures.values);
      }
      rethrow;
    }
  }

  final WorldRepository repository;
  final WorldDocument document;
  final MeshPipelineBase pipeline;
  final GameInputService input;
  final MinedartGame game;
  final RepositoryAutosaver autosaver;

  Future<void>? _releaseTask;

  @override
  String get worldId => autosaver.metadata.id;
  @override
  WorldMetadata get metadata => autosaver.metadata;

  @override
  Future<void> quiesce() =>
      _completeWithCleanup(game.quiesceSession, autosaver.stopAndWait);

  @override
  Future<void> save() async {
    final stopwatch = Stopwatch()..start();
    try {
      await autosaver.saveNow();
      game.diagnostics.updateState(storageReady: true);
    } catch (_) {
      game.diagnostics.updateState(storageReady: false, sessionFaulted: true);
      rethrow;
    } finally {
      stopwatch.stop();
      game.diagnostics.recordPersistence(stopwatch.elapsedMicroseconds / 1000);
    }
  }

  @override
  void resume() {
    game.activateInput();
    game.resumeSession();
    autosaver.start();
  }

  @override
  void replaceMetadata(WorldMetadata metadata) =>
      autosaver.replaceMetadata(metadata);

  /// The host removes the game before releasing its pipeline resources.
  @override
  Future<void> release() => _releaseTask ??= _release();

  Future<void> _release() async {
    final errors = CleanupErrors();
    try {
      await autosaver.stopAndWait();
    } catch (error) {
      errors.add(error);
    }
    try {
      game.disposeSessionResources();
      await game.meshCleanup;
    } catch (error) {
      errors.add(error);
    }
    try {
      await pipeline.close();
    } catch (error) {
      errors.add(error);
    }
    if (!errors.isEmpty) {
      _releaseTask = null;
      throw WorldSessionException(errors.first, cleanupErrors: errors.rest);
    }
  }

  Future<void> close({bool save = true}) => _completeWithCleanup(() async {
    await quiesce();
    if (save) await this.save();
  }, release);
}

/// Always runs cleanup while retaining the operation that caused the failure.
Future<void> _completeWithCleanup(
  Future<void> Function() operation,
  Future<void> Function() cleanup,
) => runWithCleanup(operation, cleanup);

bool validWorldSpawn(WorldSpawn spawn) =>
    spawn.x >= 0 &&
    spawn.z >= 0 &&
    spawn.y > 0 &&
    spawn.x < WorldDims.worldBlocksX &&
    spawn.y < WorldDims.worldBlocksY &&
    spawn.z < WorldDims.worldBlocksZ;
