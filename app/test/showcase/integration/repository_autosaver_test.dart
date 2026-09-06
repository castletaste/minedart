import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/worlds.dart';
import 'package:minedart/showcase/integration/repository_autosaver.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repository autosaver persists blocks and latest spawn', () async {
    final repository = StoredWorldRepository(MemoryWorldByteStore());
    final world = VoxelWorld()..seed = 42;
    world.setBlock(4, 5, 6, Blocks.brick);
    final now = DateTime.utc(2026, 8, 24);
    final metadata = WorldMetadata(
      id: 'test-world',
      name: 'Test World',
      seed: 42,
      createdAt: now,
      updatedAt: now,
      spawn: const WorldSpawn.origin(),
    );
    await repository.create(
      WorldDocument.fromWorld(metadata: metadata, world: world),
    );

    final autosaver = RepositoryAutosaver(
      repository: repository,
      world: world,
      metadata: metadata,
      readSpawn: () => const WorldSpawn(x: 10, y: 20, z: 30),
    );
    await autosaver.saveNow();

    final loaded = await repository.load('test-world');
    expect(loaded, isNotNull);
    expect(loaded!.metadata.spawn, const WorldSpawn(x: 10, y: 20, z: 30));
    expect(loaded.toVoxelWorld().blockAt(4, 5, 6), Blocks.brick);

    autosaver.replaceMetadata(autosaver.metadata.copyWith(name: 'Renamed'));
    await autosaver.saveNow();
    await autosaver.stopAndWait();
    expect((await repository.load('test-world'))!.metadata.name, 'Renamed');
    expect(
      () => autosaver.replaceMetadata(
        autosaver.metadata.copyWith(id: 'different-world'),
      ),
      throwsArgumentError,
    );
  });

  test('background save boundary reports storage failures', () async {
    final world = VoxelWorld()..seed = 7;
    final now = DateTime.utc(2026, 8, 24);
    final errors = <Object>[];
    final autosaver = RepositoryAutosaver(
      repository: StoredWorldRepository(_FailingStore()),
      world: world,
      metadata: WorldMetadata(
        id: 'failing-world',
        name: 'Failing',
        seed: 7,
        createdAt: now,
        updatedAt: now,
        spawn: const WorldSpawn.origin(),
      ),
      readSpawn: () => const WorldSpawn.origin(),
      onError: (error, _) => errors.add(error),
    );

    expect(await autosaver.saveSafely(), isFalse);
    expect(errors.single, isA<StateError>());
    await autosaver.stopAndWait();
  });

  test('a failed in-flight stop can be restarted and retried', () async {
    final store = _FailOnceStore();
    final now = DateTime.utc(2026, 8, 24);
    final autosaver = RepositoryAutosaver(
      repository: StoredWorldRepository(store),
      world: VoxelWorld()..seed = 9,
      metadata: WorldMetadata(
        id: 'retry-world',
        name: 'Retry',
        seed: 9,
        createdAt: now,
        updatedAt: now,
        spawn: const WorldSpawn.origin(),
      ),
      readSpawn: () => const WorldSpawn.origin(),
    );

    final firstSave = autosaver.saveNow();
    await expectLater(autosaver.stopAndWait(), throwsStateError);
    await expectLater(firstSave, throwsStateError);

    autosaver.start();
    expect(await autosaver.saveSafely(), isTrue);
    await autosaver.stopAndWait();
    expect(store.writeCalls, 2);
  });

  test('metadata replacement requires stopped and drained ownership', () async {
    final now = DateTime.utc(2026, 8, 24);
    final autosaver = RepositoryAutosaver(
      repository: StoredWorldRepository(MemoryWorldByteStore()),
      world: VoxelWorld(),
      metadata: WorldMetadata(
        id: 'metadata-world',
        name: 'Before',
        seed: 1,
        createdAt: now,
        updatedAt: now,
        spawn: const WorldSpawn.origin(),
      ),
      readSpawn: () => const WorldSpawn.origin(),
    )..start();

    expect(
      () => autosaver.replaceMetadata(
        autosaver.metadata.copyWith(name: 'Unsafe'),
      ),
      throwsStateError,
    );
    await autosaver.stopAndWait();
    autosaver.replaceMetadata(autosaver.metadata.copyWith(name: 'Safe'));
    await autosaver.saveNow();
    expect(autosaver.metadata.name, 'Safe');
  });

  test('stopAndWait blocks until an in-flight final write completes', () async {
    final store = _GatedStore();
    final now = DateTime.utc(2026, 8, 24);
    final autosaver = RepositoryAutosaver(
      repository: StoredWorldRepository(store),
      world: VoxelWorld(),
      metadata: WorldMetadata(
        id: 'gated-world',
        name: 'Gated',
        seed: 2,
        createdAt: now,
        updatedAt: now,
        spawn: const WorldSpawn.origin(),
      ),
      readSpawn: () => const WorldSpawn.origin(),
    )..start();

    final saving = autosaver.saveNow();
    await store.writeStarted.future;
    var stopped = false;
    final stopping = autosaver.stopAndWait().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(
      () => autosaver.replaceMetadata(
        autosaver.metadata.copyWith(name: 'Too early'),
      ),
      throwsStateError,
    );

    store.allowWrite.complete();
    await saving;
    await stopping;
    expect(stopped, isTrue);
    autosaver.replaceMetadata(autosaver.metadata.copyWith(name: 'After drain'));
  });
}

final class _FailingStore implements WorldByteStore {
  @override
  Future<List<String>> keys() async => const [];

  @override
  Future<Uint8List?> read(String id) async => null;

  @override
  Future<bool> remove(String id) async => false;

  @override
  Future<void> write(String id, Uint8List bytes) async {
    throw StateError('disk full');
  }
}

final class _FailOnceStore implements WorldByteStore {
  int writeCalls = 0;
  Uint8List? bytes;

  @override
  Future<List<String>> keys() async =>
      bytes == null ? const [] : ['retry-world'];

  @override
  Future<Uint8List?> read(String id) async => bytes;

  @override
  Future<bool> remove(String id) async {
    final existed = bytes != null;
    bytes = null;
    return existed;
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    writeCalls++;
    if (writeCalls == 1) throw StateError('transient disk full');
    this.bytes = Uint8List.fromList(bytes);
  }
}

final class _GatedStore implements WorldByteStore {
  final writeStarted = Completer<void>();
  final allowWrite = Completer<void>();

  @override
  Future<List<String>> keys() async => const [];

  @override
  Future<Uint8List?> read(String id) async => null;

  @override
  Future<bool> remove(String id) async => false;

  @override
  Future<void> write(String id, Uint8List bytes) async {
    writeStarted.complete();
    await allowWrite.future;
  }
}
