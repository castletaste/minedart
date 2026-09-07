import 'dart:async';
import 'dart:typed_data';

import 'package:flame_3d/graphics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/audio/audio.dart';
import 'package:minedart/data/worlds/worlds.dart';
import 'package:minedart/showcase/integration/launch_config.dart';
import 'package:minedart/showcase/integration/showcase_bootstrap.dart';
import 'package:minedart/showcase/integration/world_presets.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('ShowcaseBootstrap', () {
    testWidgets('shows progress, reports failure, and starts one retry', (
      tester,
    ) async {
      final attempts = <Completer<PendingShowcaseApp>>[
        Completer<PendingShowcaseApp>(),
        Completer<PendingShowcaseApp>(),
      ];
      var calls = 0;
      var loadingWasMountedBeforeStartup = false;

      await tester.pumpWidget(
        ShowcaseBootstrap(
          load: () {
            loadingWasMountedBeforeStartup = find
                .text('Loading world…')
                .evaluate()
                .isNotEmpty;
            return attempts[calls++].future;
          },
        ),
      );
      expect(find.text('Loading world…'), findsOneWidget);
      expect(loadingWasMountedBeforeStartup, isTrue);
      expect(calls, 1);

      attempts.first.completeError(StateError('GPU unavailable'));
      await tester.pump();
      expect(find.text('Minedart could not start'), findsOneWidget);
      expect(
        find.text(
          'The game could not finish loading. '
          'Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('GPU unavailable'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      expect(calls, 2, reason: 'retry cannot overlap an active attempt');
      await tester.pump();
      expect(find.text('Loading world…'), findsOneWidget);

      attempts.last.complete(
        PendingShowcaseApp(
          app: const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('Game ready'),
          ),
          onDispose: () async {},
        ),
      );
      await tester.pump();
      expect(find.text('Game ready'), findsOneWidget);
    });

    testWidgets('disposes a session that completes after bootstrap removal', (
      tester,
    ) async {
      final attempt = Completer<PendingShowcaseApp>();
      var disposals = 0;
      await tester.pumpWidget(ShowcaseBootstrap(load: () => attempt.future));

      await tester.pumpWidget(const SizedBox());
      attempt.complete(
        PendingShowcaseApp(
          app: const SizedBox(),
          onDispose: () async => disposals++,
        ),
      );
      await tester.pump();
      expect(disposals, 1);
    });

    testWidgets('disposes a completed session removed before publication', (
      tester,
    ) async {
      final attempt = Completer<PendingShowcaseApp>();
      var disposals = 0;
      await tester.pumpWidget(ShowcaseBootstrap(load: () => attempt.future));

      attempt.complete(
        PendingShowcaseApp(
          app: const SizedBox(),
          onDispose: () async => disposals++,
        ),
      );
      await tester.idle();
      await tester.pumpWidget(const SizedBox());

      expect(disposals, 1);
    });

    testWidgets('published app owns disposal without bootstrap duplication', (
      tester,
    ) async {
      final attempt = Completer<PendingShowcaseApp>();
      var childDisposals = 0;
      var pendingDisposals = 0;
      await tester.pumpWidget(ShowcaseBootstrap(load: () => attempt.future));

      attempt.complete(
        PendingShowcaseApp(
          app: _DisposeProbe(onDispose: () => childDisposals++),
          onDispose: () async => pendingDisposals++,
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());

      expect(childDisposals, 1);
      expect(pendingDisposals, 0);
    });

    testWidgets('shows safe recovery guidance for each GPU failure stage', (
      tester,
    ) async {
      const cases =
          <GpuInitializationFailureKind, (String title, String description)>{
            GpuInitializationFailureKind.apiUnavailable: (
              'WebGPU is unavailable',
              'Update your browser and make sure hardware acceleration is enabled.',
            ),
            GpuInitializationFailureKind.adapterUnavailable: (
              'No compatible graphics adapter',
              'Enable hardware acceleration or try another supported browser.',
            ),
            GpuInitializationFailureKind.deviceUnavailable: (
              'Graphics could not start',
              'Close other graphics-heavy tabs, then try again.',
            ),
          };

      for (final MapEntry(key: kind, value: message) in cases.entries) {
        await tester.pumpWidget(
          ShowcaseBootstrap(
            key: ValueKey(kind),
            load: () async => throw GpuInitializationException(
              kind,
              cause: StateError('private driver detail'),
            ),
          ),
        );
        await tester.pump();

        expect(find.text(message.$1), findsOneWidget);
        expect(find.text(message.$2), findsOneWidget);
        expect(find.textContaining('private driver detail'), findsNothing);

        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('ShowcaseBootstrapLoader', () {
    test(
      'cleans audio after runtime failure and caches successful GPU setup',
      () async {
        final repository = _Repository(<WorldDocument>[_document('selected')]);
        final audio = <_Audio>[];
        var gpuInitializations = 0;
        final loader = ShowcaseBootstrapLoader(
          initializeGpu: () async => gpuInitializations++,
          createRepository: () async => repository,
          createAudio: () async {
            final service = _Audio();
            audio.add(service);
            return service;
          },
          createRuntime:
              ({
                required repository,
                required document,
                required audio,
              }) async => throw StateError('runtime failed'),
          launchUri: () => Uri.parse('https://example.test/?world=selected'),
        );

        await expectLater(loader.load(), throwsStateError);
        await expectLater(loader.load(), throwsStateError);

        expect(gpuInitializations, 1);
        expect(audio, hasLength(2));
        expect(audio.every((service) => service.isDisposed), isTrue);
      },
    );

    test(
      'retries failed GPU setup and preserves null-audio fallback',
      () async {
        final repository = _Repository(<WorldDocument>[_document('selected')]);
        var gpuInitializations = 0;
        AudioServiceApi? runtimeAudio;
        final loader = ShowcaseBootstrapLoader(
          initializeGpu: () async {
            gpuInitializations++;
            if (gpuInitializations == 1) throw StateError('GPU failed');
          },
          createRepository: () async => repository,
          createAudio: () async => throw StateError('audio failed'),
          createRuntime:
              ({required repository, required document, required audio}) async {
                runtimeAudio = audio;
                throw StateError('runtime failed');
              },
          launchUri: () => Uri.parse('https://example.test/?world=selected'),
        );

        await expectLater(loader.load(), throwsStateError);
        await expectLater(loader.load(), throwsStateError);

        expect(gpuInitializations, 2);
        expect(runtimeAudio, isA<NullAudioService>());
      },
    );
  });

  group('loadInitialWorld', () {
    test('loads the world selected by the launch URI', () async {
      final selected = _document('selected', seed: 17);
      final repository = _Repository(<WorldDocument>[
        _document('recent'),
        selected,
      ]);

      final result = await loadInitialWorld(
        repository,
        ShowcaseLaunchConfig.fromUri(
          Uri.parse('https://example.test/?world=selected'),
        ),
      );

      expect(result, same(selected));
      expect(repository.loadCalls, <String>['selected']);
      expect(repository.created, isEmpty);
    });

    test('creates the requested shared seed and preset', () async {
      final repository = _Repository(const <WorldDocument>[]);
      final createdAt = DateTime.utc(2026, 9, 6, 12);
      var generatedSeed = 0;
      LaunchWorldPreset? generatedPreset;

      final result = await loadInitialWorld(
        repository,
        ShowcaseLaunchConfig.fromUri(
          Uri.parse('https://example.test/?seed=42&preset=flat'),
        ),
        clock: () => createdAt,
        readLegacy: (_) async => null,
        generateWorld: (seed, preset) {
          generatedSeed = seed;
          generatedPreset = preset;
          return VoxelWorld()..seed = seed;
        },
      );

      expect(generatedSeed, 42);
      expect(generatedPreset, LaunchWorldPreset.flat);
      expect(result.metadata.seed, 42);
      expect(result.metadata.name, 'flat · 42');
      expect(
        result.metadata.id,
        sharedWorldId(
          42,
          LaunchWorldPreset.flat,
          nonce: createdAt.microsecondsSinceEpoch,
        ),
      );
      expect(repository.created.single, same(result));
    });
  });
}

final class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

final class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

WorldDocument _document(String id, {int seed = 1}) {
  final time = DateTime.utc(2026, 9, 6);
  return WorldDocument(
    metadata: WorldMetadata(
      id: id,
      name: id,
      seed: seed,
      createdAt: time,
      updatedAt: time,
      spawn: const WorldSpawn.origin(),
    ),
    blocks: Uint16List(WorldDocument.blockCount),
  );
}

final class _Repository implements WorldRepository {
  _Repository(Iterable<WorldDocument> documents)
    : _documents = <String, WorldDocument>{
        for (final document in documents) document.metadata.id: document,
      };

  final Map<String, WorldDocument> _documents;
  final List<String> loadCalls = <String>[];
  final List<WorldDocument> created = <WorldDocument>[];

  @override
  Future<List<WorldSummary>> list() async => <WorldSummary>[
    for (final document in _documents.values) WorldSummary(document.metadata),
  ];

  @override
  Future<WorldDocument> create(WorldDocument document) async {
    created.add(document);
    _documents[document.metadata.id] = document;
    return document;
  }

  @override
  Future<WorldDocument?> load(String id) async {
    loadCalls.add(id);
    return _documents[id];
  }

  @override
  Future<void> save(WorldDocument document) async {
    _documents[document.metadata.id] = document;
  }

  @override
  Future<WorldSummary?> rename(String id, String name) async => null;

  @override
  Future<WorldDocument?> duplicate(String id, WorldMetadata metadata) async =>
      null;

  @override
  Future<bool> delete(String id) async => _documents.remove(id) != null;

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
