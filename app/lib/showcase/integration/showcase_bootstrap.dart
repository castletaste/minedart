import 'dart:async';

import 'package:flame_3d/graphics.dart';
import 'package:flutter/material.dart';
import 'package:minedart_core/minedart_core.dart' show VoxelWorld;

import '../../audio/audio.dart';
import '../../data/worlds/worlds.dart';
import 'launch_config.dart';
import 'legacy_world_migration.dart';
import 'showcase_app.dart';
import 'world_presets.dart';
import 'world_runtime.dart';

typedef ShowcaseBootstrapTask = Future<PendingShowcaseApp> Function();
typedef WorldRuntimeFactory =
    Future<WorldRuntime> Function({
      required WorldRepository repository,
      required WorldDocument document,
      required AudioServiceApi audio,
    });
typedef LegacyWorldReader = Future<WorldDocument?> Function(int fallbackSeed);

/// An app subtree whose resources are still owned by the bootstrapper.
///
/// Once [app] is mounted, its [GameShell] owns runtime, input, and audio
/// shutdown. If mounting never happens, [disposeUnused] releases them instead.
final class PendingShowcaseApp {
  PendingShowcaseApp({required this.app, required this.onDispose});

  final Widget app;
  final Future<void> Function() onDispose;
  Future<void>? _closing;

  Future<void> disposeUnused() => _closing ??= onDispose();
}

/// Loads platform services after the first Flutter frame can show progress.
final class ShowcaseBootstrapLoader {
  ShowcaseBootstrapLoader({
    Future<void> Function()? initializeGpu,
    Future<WorldRepository> Function()? createRepository,
    Future<AudioServiceApi> Function()? createAudio,
    WorldRuntimeFactory? createRuntime,
    Uri Function()? launchUri,
    LegacyWorldReader? readLegacy,
  }) : _initializeGpu = initializeGpu ?? GpuBackend.initialize,
       _createRepository = createRepository ?? createDefaultWorldRepository,
       _createAudio = createAudio ?? (() => AudioService.create(maxPlayers: 4)),
       _createRuntime = createRuntime ?? WorldRuntime.create,
       _launchUri = launchUri ?? (() => Uri.base),
       _readLegacy =
           readLegacy ??
           ((fallbackSeed) => readLegacyWorld(fallbackSeed: fallbackSeed));

  final Future<void> Function() _initializeGpu;
  final Future<WorldRepository> Function() _createRepository;
  final Future<AudioServiceApi> Function() _createAudio;
  final WorldRuntimeFactory _createRuntime;
  final Uri Function() _launchUri;
  final LegacyWorldReader _readLegacy;
  Future<void>? _gpuReady;

  Future<PendingShowcaseApp> load() async {
    await _ensureGpuReady();
    final launch = ShowcaseLaunchConfig.fromUri(_launchUri());
    final repository = await _createRepository();
    final document = await loadInitialWorld(
      repository,
      launch,
      readLegacy: _readLegacy,
    );
    final audio = await _createAudioWithFallback();
    late final WorldRuntime runtime;
    try {
      runtime = await _createRuntime(
        repository: repository,
        document: document,
        audio: audio,
      );
    } catch (error, stackTrace) {
      await _disposeAfterFailure(audio.dispose, 'audio', error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }

    return PendingShowcaseApp(
      app: ShowcaseApp(
        repository: repository,
        audio: audio,
        initialRuntime: runtime,
      ),
      onDispose: () => _disposeUnpublished(runtime, audio),
    );
  }

  Future<void> _ensureGpuReady() async {
    if (_gpuReady case final ready?) return ready;
    final pending = Future<void>.sync(_initializeGpu);
    _gpuReady = pending;
    try {
      await pending;
    } catch (_) {
      if (identical(_gpuReady, pending)) _gpuReady = null;
      rethrow;
    }
  }

  Future<AudioServiceApi> _createAudioWithFallback() async {
    try {
      return await _createAudio();
    } catch (error, stackTrace) {
      debugPrint(
        'Audio unavailable; continuing without it: $error\n$stackTrace',
      );
      return const NullAudioService();
    }
  }
}

/// Owns retry and the handoff from startup resources to the mounted game.
final class ShowcaseBootstrap extends StatefulWidget {
  const ShowcaseBootstrap({this.load, super.key});

  /// Test/embedder seam. Production uses [ShowcaseBootstrapLoader].
  final ShowcaseBootstrapTask? load;

  @override
  State<ShowcaseBootstrap> createState() => _ShowcaseBootstrapState();
}

final class _ShowcaseBootstrapState extends State<ShowcaseBootstrap> {
  late final ShowcaseBootstrapTask _load;
  PendingShowcaseApp? _pendingApp;
  Object? _error;
  bool _loading = true;
  bool _published = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load = widget.load ?? ShowcaseBootstrapLoader().load;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _start() {
    if (!_loading || _pendingApp != null) return;
    final generation = ++_generation;
    Future<PendingShowcaseApp>.sync(_load).then(
      (pendingApp) {
        if (!mounted || generation != _generation) {
          _discard(pendingApp);
          return;
        }
        setState(() {
          _pendingApp = pendingApp;
          _loading = false;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _generation) return;
        debugPrint('Minedart startup failed: $error\n$stackTrace');
        setState(() {
          _error = error;
          _loading = false;
        });
      },
    );
  }

  void _retry() {
    if (_loading || _pendingApp != null) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    _start();
  }

  @override
  void dispose() {
    _generation++;
    final pendingApp = _pendingApp;
    if (pendingApp != null && !_published) {
      _discard(pendingApp);
    }
    super.dispose();
  }

  void _discard(PendingShowcaseApp pendingApp) {
    unawaited(
      Future<void>.sync(pendingApp.disposeUnused).catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint('Unused startup session cleanup failed: $error\n$stack');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingApp case final pendingApp?) {
      _published = true;
      return pendingApp.app;
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Minedart Classic Showcase',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B9D42),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: _loading
              ? const _StartupProgress()
              : _StartupFailure(error: _error!, onRetry: _retry),
        ),
      ),
    );
  }
}

final class _StartupProgress extends StatelessWidget {
  const _StartupProgress();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Starting Minedart',
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Loading world…'),
      ],
    ),
  );
}

final class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          Text(
            'Minedart could not start',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

Future<WorldDocument> loadInitialWorld(
  WorldRepository repository,
  ShowcaseLaunchConfig launch, {
  LegacyWorldReader? readLegacy,
  DateTime Function()? clock,
  VoxelWorld Function(int seed, LaunchWorldPreset preset)? generateWorld,
}) async {
  final now = clock ?? (() => DateTime.now().toUtc());
  final generate = generateWorld ?? generatePresetWorld;
  final legacyReader =
      readLegacy ??
      ((fallbackSeed) => readLegacyWorld(fallbackSeed: fallbackSeed));
  int? generatedSeed;
  int seedForNewWorld() => generatedSeed ??= launch.resolveNewWorldSeed();

  if (launch.worldId case final id?) {
    final selected = await _loadRecovering(repository, id);
    if (selected != null) return selected;
  }
  if (launch.requestsGeneratedWorld) {
    final seed = seedForNewWorld();
    final world = generate(seed, launch.preset);
    final createdAt = now().toUtc();
    final id = sharedWorldId(
      seed,
      launch.preset,
      nonce: createdAt.microsecondsSinceEpoch,
    );
    final shared = WorldDocument.fromWorld(
      metadata: WorldMetadata(
        id: id,
        name: '${launch.preset.name} · $seed',
        seed: seed,
        createdAt: createdAt,
        updatedAt: createdAt,
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

  final legacy = await legacyReader(seedForNewWorld());
  if (legacy != null) {
    final world = legacy.toVoxelWorld();
    final createdAt = now().toUtc();
    final migrated = legacy.copyWith(
      metadata: legacy.metadata.copyWith(
        id: 'world-${createdAt.microsecondsSinceEpoch.toRadixString(36)}',
        createdAt: createdAt,
        updatedAt: createdAt,
        spawn: validWorldSpawn(legacy.metadata.spawn)
            ? legacy.metadata.spawn
            : defaultWorldSpawn(world),
      ),
    );
    await repository.create(migrated);
    return migrated;
  }

  final seed = seedForNewWorld();
  final world = generate(seed, LaunchWorldPreset.classic);
  final createdAt = now().toUtc();
  final document = WorldDocument.fromWorld(
    metadata: WorldMetadata(
      id: 'world-${createdAt.microsecondsSinceEpoch.toRadixString(36)}',
      name: 'Classic World',
      seed: seed,
      createdAt: createdAt,
      updatedAt: createdAt,
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

Future<void> _disposeUnpublished(
  WorldRuntime runtime,
  AudioServiceApi audio,
) async {
  for (final (name, cleanup) in <(String, Future<void> Function())>[
    ('runtime', () => runtime.close(save: false)),
    ('input', runtime.input.close),
    ('audio', audio.dispose),
  ]) {
    try {
      await cleanup();
    } catch (error, stackTrace) {
      debugPrint('Unused bootstrap $name cleanup failed: $error\n$stackTrace');
    }
  }
}

Future<void> _disposeAfterFailure(
  Future<void> Function() cleanup,
  String name,
  Object originalError,
  StackTrace originalStack,
) async {
  try {
    await cleanup();
  } catch (cleanupError, cleanupStack) {
    debugPrint(
      'Startup $name cleanup failed after $originalError:\n'
      '$cleanupError\n$cleanupStack\nOriginal stack:\n$originalStack',
    );
  }
}
