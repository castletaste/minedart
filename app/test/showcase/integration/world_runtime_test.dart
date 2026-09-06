import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/audio/audio.dart';
import 'package:minedart/data/worlds/world_models.dart';
import 'package:minedart/data/worlds/world_repository.dart';
import 'package:minedart/input/game_input_service.dart';
import 'package:minedart/input/mouse_look.dart';
import 'package:minedart/pipeline/mesh_pipeline_base.dart';
import 'package:minedart/showcase/integration/world_runtime.dart';
import 'package:minedart/showcase/integration/world_session_coordinator.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('minedart/mouse');
  const events = MethodChannel('minedart/mouse/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platformCalls = <String>[];
  setUp(() {
    platformCalls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      platformCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      platformCalls.add(call.method);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('throwing pipeline factory releases owned input channel', () async {
    final primary = StateError('pipeline construction');
    await expectLater(
      WorldRuntime.create(
        repository: Repository(),
        document: document,
        audio: const NullAudioService(),
        pipelineFactory: () => throw primary,
      ),
      throwsA(same(primary)),
    );
    expect(platformCalls.where((call) => call == 'listen'), hasLength(1));
    expect(platformCalls.where((call) => call == 'cancel'), hasLength(1));
  });

  test(
    'partial startup closes pipeline but leaves borrowed input to app',
    () async {
      final backend = InputBackend();
      final input = GameInputService(backend: backend);
      final pipeline = Pipeline()..startError = StateError('startup');
      await expectLater(
        WorldRuntime.create(
          repository: Repository(),
          document: document,
          audio: const NullAudioService(),
          input: input,
          pipelineFactory: () => pipeline,
        ),
        throwsStateError,
      );
      expect(pipeline.closes, 1);
      expect(backend.closes, 0);
      await input.close();
      expect(backend.closes, 1);
    },
  );

  test('game factory failure closes already started pipeline', () async {
    final pipeline = Pipeline();
    final primary = StateError('game setup');
    await expectLater(
      WorldRuntime.create(
        repository: Repository(),
        document: document,
        audio: const NullAudioService(),
        pipelineFactory: () => pipeline,
        gameFactory: (world, worker, input, spawn) {
          expect(worker, same(pipeline));
          expect(world.blockAt(0, 0, 0), Blocks.air);
          throw primary;
        },
      ),
      throwsA(same(primary)),
    );
    expect(pipeline.starts, 1);
    expect(pipeline.closes, 1);
    expect(platformCalls.where((call) => call == 'cancel'), hasLength(1));
  });

  test(
    'cleanup failure preserves startup error and still closes owned input',
    () async {
      final primary = StateError('startup');
      final cleanup = StateError('worker shutdown');
      final pipeline = Pipeline()
        ..startError = primary
        ..closeError = cleanup;
      await expectLater(
        WorldRuntime.create(
          repository: Repository(),
          document: document,
          audio: const NullAudioService(),
          pipelineFactory: () => pipeline,
        ),
        throwsA(
          isA<WorldSessionFailure<void>>()
              .having((failure) => failure.error, 'primary', same(primary))
              .having((failure) => failure.cleanupErrors, 'cleanup', [cleanup]),
        ),
      );
      expect(platformCalls.where((call) => call == 'cancel'), hasLength(1));
    },
  );
}

final document = WorldDocument.fromWorld(
  metadata: WorldMetadata(
    id: 'world',
    name: 'World',
    seed: 4,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    spawn: const WorldSpawn.origin(),
  ),
  world: VoxelWorld(),
);

final class Repository implements WorldRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class Pipeline implements MeshPipelineBase {
  int starts = 0;
  int closes = 0;
  Object? startError;
  Object? closeError;
  @override
  Future<void> start() async {
    starts++;
    if (startError case final error?) throw error;
  }

  @override
  Future<void> close() async {
    closes++;
    if (closeError case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class InputBackend implements PointerCaptureBackend {
  int closes = 0;
  @override
  Stream<MouseLookEvent> get events => const Stream.empty();
  @override
  bool get isCaptured => false;
  @override
  void start() {}
  @override
  Future<bool> capture() async => false;
  @override
  Future<void> release() async {}
  @override
  Future<void> close() async {
    closes++;
  }
}
