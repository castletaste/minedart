import 'package:flame_3d/graphics.dart';
import 'package:flutter/widgets.dart';

import 'audio/audio.dart';
import 'data/worlds/worlds.dart';
import 'showcase/integration/launch_config.dart';
import 'showcase/integration/legacy_world_migration.dart';
import 'showcase/integration/showcase_app.dart';
import 'showcase/integration/world_runtime.dart';
import 'showcase/integration/world_presets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GpuBackend.initialize();

  final launch = ShowcaseLaunchConfig.fromUri(Uri.base);
  final repository = await createDefaultWorldRepository();
  final document = await _loadInitialWorld(repository, launch);
  late final AudioServiceApi audio;
  try {
    audio = await AudioService.create(maxPlayers: 4);
  } on Object {
    audio = const NullAudioService();
  }
  final runtime = await WorldRuntime.create(
    repository: repository,
    document: document,
    audio: audio,
  );

  runApp(
    ShowcaseApp(repository: repository, audio: audio, initialRuntime: runtime),
  );
}

Future<WorldDocument> _loadInitialWorld(
  WorldRepository repository,
  ShowcaseLaunchConfig launch,
) async {
  int? generatedSeed;
  int seedForNewWorld() => generatedSeed ??= launch.resolveNewWorldSeed();

  if (launch.worldId case final id?) {
    final selected = await _loadRecovering(repository, id);
    if (selected != null) return selected;
  }
  if (launch.requestsGeneratedWorld) {
    final seed = seedForNewWorld();
    final world = generatePresetWorld(seed, launch.preset);
    final now = DateTime.now().toUtc();
    final id = sharedWorldId(
      seed,
      launch.preset,
      nonce: now.microsecondsSinceEpoch,
    );
    final shared = WorldDocument.fromWorld(
      metadata: WorldMetadata(
        id: id,
        name: '${launch.preset.name} · $seed',
        seed: seed,
        createdAt: now,
        updatedAt: now,
        spawn: defaultWorldSpawn(world),
      ),
      world: world,
    );
    await repository.create(shared);
    return shared;
  }
  final worlds = await repository.list();
  for (final summary in worlds) {
    final recent = await _loadRecovering(repository, summary.id);
    if (recent != null) return recent;
  }

  final legacy = await readLegacyWorld(fallbackSeed: seedForNewWorld());
  if (legacy != null) {
    final world = legacy.toVoxelWorld();
    final now = DateTime.now().toUtc();
    final migrated = legacy.copyWith(
      metadata: legacy.metadata.copyWith(
        id: 'world-${now.microsecondsSinceEpoch.toRadixString(36)}',
        createdAt: now,
        updatedAt: now,
        spawn: validWorldSpawn(legacy.metadata.spawn)
            ? legacy.metadata.spawn
            : defaultWorldSpawn(world),
      ),
    );
    await repository.create(migrated);
    return migrated;
  }

  final seed = seedForNewWorld();
  final world = generatePresetWorld(seed, LaunchWorldPreset.classic);
  final now = DateTime.now().toUtc();
  final document = WorldDocument.fromWorld(
    metadata: WorldMetadata(
      id: 'world-${now.microsecondsSinceEpoch.toRadixString(36)}',
      name: 'Classic World',
      seed: seed,
      createdAt: now,
      updatedAt: now,
      spawn: defaultWorldSpawn(world),
    ),
    world: world,
  );
  await repository.create(document);
  return document;
}

Future<WorldDocument?> _loadRecovering(
  WorldRepository repository,
  String id,
) async {
  try {
    return await repository.load(id);
  } on Object catch (error, stackTrace) {
    debugPrint('Skipping unreadable world $id: $error\n$stackTrace');
    return null;
  }
}
