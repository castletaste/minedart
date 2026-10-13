import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/data/worlds/world_models.dart';
import 'package:minedart/data/worlds/world_repository.dart';
import 'package:minedart/showcase/integration/world_session_coordinator.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('operation epoch invalidates async ownership at close', () async {
    final h = Harness();
    expect(h.session.operationEpoch, 0);
    final closing = h.session.close();
    expect(h.session.operationEpoch, 1);
    await closing;
    h.session.dispose();
    expect(h.session.operationEpoch, 1);
  });

  test(
    'switch retains old runtime until candidate is ready and removed',
    () async {
      final h = Harness();
      final ready = h.gate('stage:next');
      final operation = h.session.switchWorld(document('next'));
      await h.reached('stage:next');
      expect(h.session.current, same(h.old));
      expect(h.old.running, isFalse);
      expect(h.events, isNot(contains('release:old')));
      ready.complete();
      expect(await operation, isA<WorldSessionSuccess<void>>());
      expect(h.session.current.worldId, 'next');
      expect(
        h.events,
        containsAllInOrder([
          'quiesce:old',
          'save:old',
          'stage:next',
          'resume:next',
          'commit:next',
          'remove:old',
          'release:old',
        ]),
      );
      await h.close();
    },
  );

  test('failed loading resumes old and cleans candidate', () async {
    final h = Harness()..fail('stage:next');
    expect(
      await h.session.switchWorld(document('next')),
      isA<WorldSessionFailure<void>>(),
    );
    expect(h.session.current, same(h.old));
    expect(h.old.running, isTrue);
    expect(
      h.events,
      containsAllInOrder(['remove:next', 'release:next', 'resume:old']),
    );
    expect(h.events, isNot(contains('remove:old')));
    await h.close();
  });

  test('rename excludes autosave and synchronizes durable metadata', () async {
    final h = Harness();
    expect(
      await h.session.rename('old', 'Renamed'),
      isA<WorldSessionSuccess<void>>(),
    );
    expect(h.old.metadata.name, 'Renamed');
    expect(
      h.events,
      containsAllInOrder([
        'quiesce:old',
        'save:old',
        'rename:old',
        'metadata:old',
        'resume:old',
      ]),
    );
    await h.close();
  });

  test('commands validate identity when they execute in the queue', () async {
    final h = Harness();
    final gate = h.gate('stage:next');
    final switching = h.session.switchWorld(document('next'));
    await h.reached('stage:next');
    final rename = h.session.rename('old', 'Archived');
    gate.complete();
    await switching;
    await rename;
    expect(h.events.where((e) => e == 'save:old'), hasLength(1));
    expect(h.events, isNot(contains('metadata:old')));
    expect(h.session.current.worldId, 'next');
    await h.close();
  });

  for (final boundary in ['save:old', 'stage:next']) {
    test(
      'detach during $boundary cannot mount or resume a candidate',
      () async {
        final h = Harness();
        final gate = h.gate(boundary);
        final operation = h.session.switchWorld(document('next'));
        await h.reached(boundary);
        h.host.isAttached = false;
        final closing = h.session.close();
        gate.complete();
        expect(await operation, isA<WorldSessionCancelled<void>>());
        await closing;
        expect(h.events, isNot(contains('commit:next')));
        expect(h.events, isNot(contains('resume:old')));
        expect(h.events, contains('release:next'));
        if (boundary == 'save:old') {
          expect(h.events, isNot(contains('stage:next')));
        }
        h.session.dispose();
      },
    );
  }

  test('dispose detaches observers while accepted cleanup completes', () async {
    int notifications = 0;
    final h = Harness(onChanged: () => notifications++);
    final gate = h.gate('stage:next');
    final operation = h.session.switchWorld(document('next'));
    await h.reached('stage:next');
    h.session.dispose();
    final before = notifications;
    gate.complete();
    expect(await operation, isA<WorldSessionSuccess<void>>());
    expect(notifications, before);
    await h.session.close();
  });

  test('reset failure restores snapshot before resuming old session', () async {
    final h = Harness()..fail('resume:old-reset');
    final result = await h.session.reset(
      'old',
      (_) => document('old', name: 'reset'),
    );
    expect(result, isA<WorldSessionFailure<void>>());
    expect(h.repo.saved.map((d) => d.metadata.name), ['reset', 'old']);
    expect(h.old.running, isTrue);
    expect(h.session.isFaulted, isFalse);
    await h.close();
  });

  test(
    'failed reset rollback faults owner and never overwrites durable reset',
    () async {
      final h = Harness()
        ..fail('resume:old-reset')
        ..fail('write:old');
      final result = await h.session.reset(
        'old',
        (_) => document('old', name: 'reset'),
      );
      expect(
        result,
        isA<WorldSessionFailure<void>>().having(
          (r) => r.durableStateChanged,
          'durable',
          isTrue,
        ),
      );
      expect(h.session.isFaulted, isTrue);
      expect(h.old.running, isFalse);
      final saves = h.events.where((e) => e == 'save:old').length;
      await h.close();
      expect(h.events.where((e) => e == 'save:old'), hasLength(saves));
    },
  );

  test('metadata synchronization failure blocks stale autosave', () async {
    final h = Harness()..fail('metadata:old');
    final result = await h.session.rename('old', 'Renamed');
    expect(
      result,
      isA<WorldSessionFailure<void>>().having(
        (r) => r.durableStateChanged,
        'durable',
        isTrue,
      ),
    );
    expect(h.old.running, isFalse);
    expect(h.session.isFaulted, isTrue);
    expect(await h.session.saveCurrent(), isA<WorldSessionCancelled<void>>());
    await h.close();
    expect(h.events.where((e) => e == 'save:old'), hasLength(1));
  });

  test(
    'reset cannot rollback before candidate resource release succeeds',
    () async {
      final h = Harness()
        ..fail('resume:old-reset')
        ..fail('release:old-reset');
      final result =
          await h.session.reset('old', (_) => document('old', name: 'reset'))
              as WorldSessionFailure<void>;
      expect(result.durableStateChanged, isTrue);
      expect(h.repo.saved.map((d) => d.metadata.name), ['reset']);
      expect(h.session.isFaulted, isTrue);
      await h.close();
      expect(h.events.where((e) => e == 'save:old'), hasLength(1));
    },
  );

  test('delete error reports that active runtime already changed', () async {
    final h = Harness()..fail('delete:old');
    final result = await h.session.delete(
      'old',
      replacement: () async => document('next'),
    );
    expect(
      result,
      isA<WorldSessionFailure<void>>().having(
        (r) => r.activeWorldChanged,
        'active changed',
        isTrue,
      ),
    );
    expect(h.session.current.worldId, 'next');
    await h.close();
  });

  test(
    'close retries pending release without repeating final snapshot',
    () async {
      final h = Harness()..fail('release:old');
      await expectLater(
        h.session.close(),
        throwsA(isA<WorldSessionException>()),
      );
      expect(h.session.isFaulted, isTrue);
      await h.session.close();
      expect(h.events.where((e) => e == 'save:old'), hasLength(1));
      expect(h.events.where((e) => e == 'release:old'), hasLength(2));
      h.session.dispose();
    },
  );

  test(
    'close retry never touches a successfully released current runtime',
    () async {
      final h = Harness()..fail('save:old');
      await expectLater(
        h.session.close(),
        throwsA(isA<WorldSessionException>()),
      );
      final events = h.events.toList();
      await h.session.close();
      expect(h.events, events);
      h.session.dispose();
    },
  );

  test('rename reports durable success when runtime restore fails', () async {
    final h = Harness()..fail('resume:old');
    final result = await h.session.rename('old', 'Renamed');
    expect(
      result,
      isA<WorldSessionFailure<void>>().having(
        (r) => r.durableStateChanged,
        'durable',
        isTrue,
      ),
    );
    expect(h.session.isFaulted, isTrue);
    expect(h.old.running, isFalse);
    await h.close();
  });

  test('restore error cannot replace the original rename failure', () async {
    final h = Harness()
      ..fail('rename:old')
      ..fail('resume:old');
    final result =
        await h.session.rename('old', 'Renamed') as WorldSessionFailure<void>;
    expect(result.error.toString(), contains('rename:old'));
    expect(result.cleanupErrors.single.toString(), contains('resume:old'));
    await h.close();
  });

  test(
    'created world retains typed cleanup failures if activation fails',
    () async {
      final h = Harness()
        ..fail('stage:next')
        ..fail('release:next');
      final result =
          await h.session.createWorld(document('next'))
              as WorldSessionFailure<void>;
      expect(result.durableStateChanged, isTrue);
      expect(result.error.toString(), contains('stage:next'));
      expect(result.cleanupErrors.single.toString(), contains('release:next'));
      await h.close();
    },
  );
  for (final seed in [17, 43, 2026]) {
    test('seeded session commands preserve ownership (seed $seed)', () async {
      final random = Random(seed);
      final h = Harness();
      final base = document('old');
      var expected = 'old';
      for (var batch = 0; batch < 24; batch++) {
        final operations = <Future<WorldSessionResult<void>>>[];
        final failures = <bool>[];
        for (var command = 0; command < 1 + random.nextInt(4); command++) {
          if (random.nextBool()) {
            operations.add(h.session.saveCurrent());
            failures.add(false);
          } else {
            final id = 'world-$seed-$batch-$command';
            final fail = random.nextInt(4) == 0;
            if (fail) h.fail('stage:$id');
            operations.add(
              h.session.switchWorld(
                base.copyWith(
                  metadata: base.metadata.copyWith(id: id, name: id),
                ),
              ),
            );
            failures.add(fail);
            if (!fail) expected = id;
          }
        }
        final results = await Future.wait(operations);
        for (var i = 0; i < results.length; i++) {
          expect(
            results[i],
            failures[i]
                ? isA<WorldSessionFailure<void>>()
                : isA<WorldSessionSuccess<void>>(),
            reason: 'seed=$seed batch=$batch command=$i',
          );
        }
        expect(h.session.current.worldId, expected);
        expect(h.session.isBusy, isFalse);
        expect(h.session.isFaulted, isFalse);
        final current = h.session.current as Runtime;
        expect(current.running, isTrue);
        expect(h.runtimes.where((runtime) => runtime.running), [current]);
        expect(h.runtimes.where((runtime) => runtime.releases == 0), [current]);
        expect(h.runtimes.every((runtime) => runtime.releases <= 1), isTrue);
      }
      await h.close();
      final afterClose = List<String>.of(h.events);
      expect(await h.session.saveCurrent(), isA<WorldSessionCancelled<void>>());
      expect(
        await h.session.switchWorld(base),
        isA<WorldSessionCancelled<void>>(),
      );
      await h.session.close();
      expect(h.events, afterClose);
      expect(
        h.runtimes.every(
          (runtime) => runtime.releases == 1 && !runtime.running,
        ),
        isTrue,
      );
    });
  }
}

final _documents = <String, WorldDocument>{};
WorldDocument document(String id, {String? name}) => _documents.putIfAbsent(
  '$id/$name',
  () => WorldDocument(
    metadata: WorldMetadata(
      id: id,
      name: name ?? id,
      seed: 4,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      spawn: const WorldSpawn.origin(),
    ),
    blocks: Uint16List(
      WorldDims.worldBlocksX * WorldDims.worldBlocksY * WorldDims.worldBlocksZ,
    ),
  ),
);

final class Harness {
  Harness({void Function()? onChanged}) {
    old = Runtime(this, document('old'))..running = true;
    repo = Repository(this);
    host = Host(this);
    session = WorldSessionCoordinator(
      initialRuntime: old,
      repository: repo,
      host: host,
      onChanged: onChanged,
      createRuntime: (doc) async {
        await call('allocate:${doc.metadata.id}');
        return Runtime(this, doc);
      },
    );
  }
  final events = <String>[];
  final runtimes = <Runtime>[];
  final _gates = <String, Completer<void>>{};
  final _reached = <String, Completer<void>>{};
  final _failures = <String>{};
  late final Runtime old;
  late final Repository repo;
  late final Host host;
  late final WorldSessionCoordinator session;
  Completer<void> gate(String event) => _gates[event] = Completer<void>();
  Future<void> reached(String event) => events.contains(event)
      ? Future.value()
      : (_reached[event] ??= Completer<void>()).future;
  void fail(String event) => _failures.add(event);
  void sync(String event) {
    events.add(event);
    _reached.remove(event)?.complete();
    if (_failures.remove(event)) throw StateError(event);
  }

  Future<void> call(String event) async {
    sync(event);
    await _gates.remove(event)?.future;
  }

  Future<void> close() async {
    await session.close();
    session.dispose();
  }
}

final class Runtime implements WorldSessionRuntime {
  Runtime(this.h, WorldDocument doc) : metadata = doc.metadata {
    h.runtimes.add(this);
  }
  final Harness h;
  @override
  WorldMetadata metadata;
  bool running = false;
  int releases = 0;
  String get _label => metadata.name == 'reset' ? '$worldId-reset' : worldId;
  @override
  String get worldId => metadata.id;
  @override
  Future<void> quiesce() async {
    running = false;
    await h.call('quiesce:$_label');
  }

  @override
  Future<void> save() => h.call('save:$_label');
  @override
  void resume() {
    h.sync('resume:$_label');
    running = true;
  }

  @override
  void replaceMetadata(WorldMetadata value) {
    h.sync('metadata:$_label');
    metadata = value;
  }

  @override
  Future<void> release() async {
    await h.call('release:$_label');
    releases++;
    running = false;
  }
}

final class Host implements WorldSessionHost {
  Host(this.h);
  final Harness h;
  @override
  bool isAttached = true;
  @override
  Future<void> stage(WorldSessionRuntime runtime) =>
      h.call('stage:${runtime.worldId}');
  @override
  void commit(WorldSessionRuntime runtime) =>
      h.sync('commit:${runtime.worldId}');
  @override
  Future<void> remove(WorldSessionRuntime runtime) =>
      h.call('remove:${runtime.worldId}');
}

final class Repository implements WorldRepository {
  Repository(this.h);
  final Harness h;
  final saved = <WorldDocument>[];
  @override
  Future<WorldDocument> create(WorldDocument value) async => value;
  @override
  Future<WorldDocument?> load(String id) async => document(id);
  @override
  Future<void> save(WorldDocument value) async {
    await h.call('write:${value.metadata.name}');
    saved.add(value);
  }

  @override
  Future<WorldSummary?> rename(String id, String name) async {
    await h.call('rename:$id');
    return WorldSummary(document(id, name: name).metadata);
  }

  @override
  Future<bool> delete(String id) async {
    await h.call('delete:$id');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
