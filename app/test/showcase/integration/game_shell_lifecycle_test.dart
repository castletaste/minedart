import 'dart:async';
import 'dart:typed_data';

import 'package:flame_3d/graphics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/audio/audio.dart';
import 'package:minedart/data/worlds/worlds.dart';
import 'package:minedart/input/game_input_service.dart';
import 'package:minedart/input/mouse_look.dart';
import 'package:minedart/pipeline/mesh_pipeline_base.dart';
import 'package:minedart/showcase/controller/options_controller.dart';
import 'package:minedart/showcase/integration/game_runtime_host.dart';
import 'package:minedart/showcase/integration/game_shell.dart';
import 'package:minedart/showcase/integration/showcase_app.dart';
import 'package:minedart/showcase/integration/world_runtime.dart';
import 'package:minedart/showcase/integration/world_session_coordinator.dart';
import 'package:minedart/showcase/ui/pause_options.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  setUpAll(_NoopGpuBackend.new);

  testWidgets('options update preserves the mounted game host', (tester) async {
    final harness = await _Harness.create();

    await tester.pumpWidget(
      ShowcaseApp(
        repository: harness.repository,
        audio: harness.audio,
        initialRuntime: harness.runtime,
      ),
    );
    harness.runtime.game.onRemove();
    await tester.pump();
    final options = tester.widget<GameShell>(find.byType(GameShell)).options;
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final host = tester.widget<GameRuntimeHost>(find.byType(GameRuntimeHost));
    final hostState = tester.state(find.byType(GameRuntimeHost));

    options
      ..setMasterVolume(0.35)
      ..setMouseSensitivity(0.8);
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)),
      same(materialApp),
    );
    expect(
      tester.widget<GameRuntimeHost>(find.byType(GameRuntimeHost)),
      same(host),
    );
    expect(tester.state(find.byType(GameRuntimeHost)), same(hostState));
    await harness.unmount(tester);
  });

  testWidgets('pause dialog resolves the Navigator below MaterialApp', (
    tester,
  ) async {
    final harness = await _Harness.create();
    final options = OptionsController();
    addTearDown(options.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameShell(
          repository: harness.repository,
          audio: harness.audio,
          initialRuntime: harness.runtime,
          options: options,
        ),
      ),
    );
    harness.runtime.game.onRemove();
    await tester.pump();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('GAME PAUSED'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.unmount(tester);
  });

  testWidgets('save and quit is single-flight and surfaces save failure', (
    tester,
  ) async {
    final saveGate = Completer<void>();
    final harness = await _Harness.create(
      saveGate: saveGate,
      saveError: StateError('disk full'),
    );
    final options = OptionsController();
    addTearDown(options.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameShell(
          repository: harness.repository,
          audio: harness.audio,
          initialRuntime: harness.runtime,
          options: options,
        ),
      ),
    );
    harness.runtime.game.onRemove();
    await tester.pump();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final save = find.byKey(PauseOptionsKeys.saveAndQuit);
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();
    expect(harness.repository.saveCalls, 1);

    saveGate.complete();
    for (
      var attempt = 0;
      attempt < 10 && find.textContaining('disk full').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump();
    }
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(harness.repository.saveCalls, 1);
    await harness.unmount(tester);
  });

  testWidgets('initial mountedReady failure is visible in ShowcaseApp', (
    tester,
  ) async {
    final harness = await _Harness.create();

    await tester.pumpWidget(
      ShowcaseApp(
        repository: harness.repository,
        audio: harness.audio,
        initialRuntime: harness.runtime,
      ),
    );
    harness.runtime.game.onRemove();
    await tester.pump();

    expect(find.textContaining('Game was removed'), findsWidgets);
    await harness.unmount(tester);
  });

  testWidgets('host disposal cancels a staged candidate before it mounts', (
    tester,
  ) async {
    final initial = await _Harness.create();
    final candidate = await _Harness.create(id: 'candidate');
    final host = GameRuntimeHostController(initial.runtime);
    await tester.pumpWidget(
      MaterialApp(home: GameRuntimeHost(controller: host)),
    );

    final staging = expectLater(
      host.stage(candidate.runtime),
      throwsA(isA<StateError>()),
    );
    await tester.pumpWidget(const SizedBox());

    await staging;
    expect(candidate.runtime.game.isSessionDisposed, isTrue);
    await host.remove(candidate.runtime);
    await initial.disposeUnhosted(tester);
    await candidate.disposeUnhosted(tester);
  });

  testWidgets('failed readiness is surfaced and same-id runtimes keep keys', (
    tester,
  ) async {
    final initial = await _Harness.create(id: 'same');
    final candidate = await _Harness.create(id: 'same');
    final host = GameRuntimeHostController(initial.runtime);
    await tester.pumpWidget(
      MaterialApp(home: GameRuntimeHost(controller: host)),
    );

    final staging = expectLater(
      host.stage(candidate.runtime),
      throwsA(isA<StateError>()),
    );
    await tester.pump();
    expect(find.byKey(ObjectKey(initial.runtime)), findsOneWidget);
    expect(find.byKey(ObjectKey(candidate.runtime)), findsOneWidget);
    candidate.runtime.game.onRemove();
    await staging;

    await host.remove(candidate.runtime);
    await tester.pumpWidget(const SizedBox());
    await initial.disposeUnhosted(tester);
    await candidate.disposeUnhosted(tester);
  });

  test(
    'quiesce preserves input failure and reports autosave drain failure',
    () async {
      final saveGate = Completer<void>();
      final releaseGate = Completer<void>();
      final inputError = StateError('input release failed');
      final saveError = StateError('autosave drain failed');
      final harness = await _Harness.create(
        saveGate: saveGate,
        saveError: saveError,
        inputReleaseError: inputError,
        inputReleaseGate: releaseGate,
      );
      harness.runtime.resume();
      unawaited(harness.runtime.autosaver.saveNow().catchError((_) {}));
      while (harness.repository.saveCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final quiesce = harness.runtime.quiesce();
      await harness.inputBackend.releaseStarted.future;
      releaseGate.complete();
      await Future<void>.delayed(Duration.zero);
      saveGate.complete();
      final failure = await _failureOf(quiesce);

      expect(failure.error, isA<InputReleaseException>());
      expect(failure.cleanupErrors, <Object>[saveError]);
      await harness.disposeUnhostedAsync();
    },
  );

  test(
    'close preserves save failure and flattens pipeline cleanup failure',
    () async {
      final saveError = StateError('save failed');
      final pipelineError = StateError('pipeline close failed');
      final harness = await _Harness.create(
        saveError: saveError,
        pipelineCloseError: pipelineError,
      );

      final failure = await _failureOf(harness.runtime.close());

      expect(failure.error, same(saveError));
      expect(failure.cleanupErrors, <Object>[pipelineError]);
      await harness.disposeUnhostedAsync();
    },
  );
}

Future<WorldSessionFailure<void>> _failureOf(Future<void> operation) async {
  try {
    await operation;
  } on WorldSessionFailure<void> catch (failure) {
    return failure;
  }
  throw TestFailure('Expected WorldSessionFailure');
}

final class _Harness {
  _Harness({
    required this.repository,
    required this.audio,
    required this.inputBackend,
    required this.pipeline,
    required this.runtime,
  });

  static Future<_Harness> create({
    Completer<void>? saveGate,
    Object? saveError,
    Object? inputReleaseError,
    Completer<void>? inputReleaseGate,
    Object? pipelineCloseError,
    String id = 'initial',
  }) async {
    final document = _document(id);
    final repository = _Repository(
      document,
      saveGate: saveGate,
      saveError: saveError,
    );
    final audio = _Audio();
    final inputBackend = _InputBackend(
      releaseError: inputReleaseError,
      releaseGate: inputReleaseGate,
    );
    final input = GameInputService(backend: inputBackend);
    final pipeline = _Pipeline(closeError: pipelineCloseError);
    final runtime = await WorldRuntime.create(
      repository: repository,
      document: document,
      audio: audio,
      input: input,
      pipelineFactory: () => pipeline,
    );
    return _Harness(
      repository: repository,
      audio: audio,
      inputBackend: inputBackend,
      pipeline: pipeline,
      runtime: runtime,
    );
  }

  final _Repository repository;
  final _Audio audio;
  final _InputBackend inputBackend;
  final _Pipeline pipeline;
  final WorldRuntime runtime;

  Future<void> unmount(WidgetTester tester) async {
    final saveGate = repository.saveGate;
    if (saveGate != null && !saveGate.isCompleted) saveGate.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await disposeUnhosted(tester);
    expect(audio.isDisposed, isTrue, reason: 'test resources must be closed');
    expect(inputBackend._closed, isTrue);
  }

  Future<void> disposeUnhosted(WidgetTester tester) async {
    await tester.runAsync(disposeUnhostedAsync);
  }

  Future<void> disposeUnhostedAsync() async {
    runtime.game.disposeSessionResources();
    try {
      await pipeline.close();
    } catch (_) {}
    await inputBackend.close();
    await audio.dispose();
  }
}

WorldDocument _document(String id) {
  final time = DateTime.utc(2026, 9, 6);
  return WorldDocument(
    metadata: WorldMetadata(
      id: id,
      name: id,
      seed: 1,
      createdAt: time,
      updatedAt: time,
      spawn: const WorldSpawn(x: 8, y: 40, z: 8),
    ),
    blocks: Uint16List(WorldDocument.blockCount),
  );
}

final class _Repository implements WorldRepository {
  _Repository(this.document, {this.saveGate, this.saveError});

  final WorldDocument document;
  final Completer<void>? saveGate;
  final Object? saveError;
  int saveCalls = 0;

  @override
  Future<List<WorldSummary>> list() async => <WorldSummary>[
    WorldSummary(document.metadata),
  ];

  @override
  Future<WorldDocument?> load(String id) async =>
      id == document.metadata.id ? document : null;

  @override
  Future<void> save(WorldDocument document) async {
    saveCalls++;
    final gate = saveGate;
    if (gate != null) await gate.future;
    if (saveError case final error?) throw error;
  }

  @override
  Future<WorldDocument> create(WorldDocument document) async => document;
  @override
  Future<WorldSummary?> rename(String id, String name) async => null;
  @override
  Future<WorldDocument?> duplicate(String id, WorldMetadata metadata) async =>
      null;
  @override
  Future<bool> delete(String id) async => false;
  @override
  Future<WorldDocument> importBytes(
    Uint8List bytes, {
    WorldMetadata? legacyMetadata,
  }) => throw UnimplementedError();
  @override
  Future<Uint8List> exportBytes(String id) => throw UnimplementedError();
}

final class _Audio implements AudioServiceApi {
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;
  @override
  bool get muted => false;
  @override
  double get musicVolume => 1;
  @override
  double get sfxVolume => 1;
  @override
  Future<void> dispose() async => _disposed = true;
  @override
  Future<void> play(AudioCue cue, {int seed = 0, double volume = 1}) async {}
  @override
  Future<void> setMusicVolume(double value) async {}
  @override
  Future<void> setMuted(bool value) async {}
  @override
  Future<void> setSfxVolume(double value) async {}
}

final class _InputBackend implements PointerCaptureBackend {
  _InputBackend({this.releaseError, this.releaseGate});

  final Object? releaseError;
  final Completer<void>? releaseGate;
  final Completer<void> releaseStarted = Completer<void>();
  bool _closed = false;

  @override
  Stream<MouseLookEvent> get events => const Stream<MouseLookEvent>.empty();
  @override
  bool get isCaptured => false;
  @override
  void start() {}
  @override
  Future<bool> capture() async => false;
  @override
  Future<void> release() async {
    if (!releaseStarted.isCompleted) releaseStarted.complete();
    await releaseGate?.future;
    if (releaseError case final error?) throw error;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
  }
}

final class _Pipeline implements MeshPipelineBase {
  _Pipeline({this.closeError});

  final Object? closeError;
  final StreamController<ChunkMeshData> _results =
      StreamController<ChunkMeshData>.broadcast();
  bool _closed = false;

  @override
  Stream<ChunkMeshData> get results => _results.stream;
  @override
  MeshPipelineActivity activity = MeshPipelineActivity.idle;
  @override
  MainThreadMeshTimeObserver? onMainThreadMeshTime;
  @override
  int get pendingCount => 0;
  @override
  Future<void> start() async {}
  @override
  void request(MeshJob job) {}
  @override
  void pauseDeadlines() {}
  @override
  void resumeDeadlines() {}
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _results.close();
    if (closeError case final error?) throw error;
  }

  @override
  void dispose() {
    unawaited(close());
  }
}

/// Registers a backend so constructing a real Flame game stays GPU-free.
final class _NoopGpuBackend extends GpuBackend {
  _NoopGpuBackend();

  Never get _unexpected => throw StateError('Unexpected GPU access in test');

  @override
  GpuBuffer createBuffer({
    required GpuStorageMode storageMode,
    required int sizeInBytes,
  }) => _unexpected;

  @override
  GpuPipeline createPipeline({
    required GpuShader vertexShader,
    required GpuShader fragmentShader,
  }) => _unexpected;

  @override
  GpuRenderTarget createRenderTarget({
    required int width,
    required int height,
    required Color clearValue,
  }) => _unexpected;

  @override
  GpuTexture createTexture({
    required GpuStorageMode storageMode,
    required int width,
    required int height,
    required GpuPixelFormat format,
  }) => _unexpected;

  @override
  GpuShaderLibrary loadShaderLibrary(String assetName) => _unexpected;

  @override
  GpuFrame beginFrame() => _unexpected;
}
