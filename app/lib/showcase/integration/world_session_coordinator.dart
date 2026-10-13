import 'dart:async';
import 'dart:typed_data';

import '../../data/worlds/world_models.dart';
import '../../data/worlds/world_repository.dart';
import 'cleanup_errors.dart';
import 'world_session_errors.dart';

export 'world_session_errors.dart';

/// Resources belonging to a world, independent of Flutter mounting and routes.
abstract interface class WorldSessionRuntime {
  String get worldId;
  WorldMetadata get metadata;
  Future<void> quiesce();
  Future<void> save();
  void resume();
  void replaceMetadata(WorldMetadata metadata);
  Future<void> release();
}

abstract interface class WorldSessionHost {
  bool get isAttached;
  Future<void> stage(WorldSessionRuntime candidate);

  /// Synchronous, non-throwing publication of a ready candidate.
  void commit(WorldSessionRuntime candidate);

  /// Idempotent; also safe after the host widget has been disposed.
  Future<void> remove(WorldSessionRuntime runtime);
}

typedef WorldRuntimeCreator =
    Future<WorldSessionRuntime> Function(WorldDocument document);

/// One owner and one command queue. UI completions never own runtime cleanup.
final class WorldSessionCoordinator {
  WorldSessionCoordinator({
    required WorldSessionRuntime initialRuntime,
    required this.repository,
    required this.createRuntime,
    required this.host,
    this.onChanged,
  }) : _current = initialRuntime;

  final WorldRepository repository;
  final WorldRuntimeCreator createRuntime;
  final WorldSessionHost host;
  final void Function()? onChanged;
  WorldSessionRuntime _current;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  final Set<WorldSessionRuntime> _retiring = {};
  _SessionLifecycle _lifecycle = _SessionLifecycle.active;
  bool _disposed = false;
  bool _faulted = false;
  bool _unsafeToSave = false;
  int _epoch = 0;
  bool _closeSaveAttempted = false;
  bool _currentReleased = false;
  int _pending = 0;

  WorldSessionRuntime get current => _current;
  bool get isBusy => _pending > 0;
  bool get isFaulted => _faulted;

  /// Monotonic token for callers that own additional async work for a world.
  /// Any value captured before [close] is stale after the close begins.
  int get operationEpoch => _epoch;
  bool get _stopping =>
      _lifecycle != _SessionLifecycle.active || !host.isAttached;

  Future<WorldSessionResult<T>> _run<T>(Future<T> Function() command) {
    if (_stopping || _faulted) return Future.value(WorldSessionCancelled<T>());
    final epoch = _epoch;
    final completion = Completer<WorldSessionResult<T>>();
    _pending++;
    _publish();
    _tail = _tail.then((_) async {
      final before = _current;
      try {
        if (_stopping || _faulted) {
          completion.complete(WorldSessionCancelled<T>());
        } else {
          final value = await command();
          completion.complete(
            epoch == _epoch && !_stopping
                ? WorldSessionSuccess(value)
                : WorldSessionCancelled<T>(),
          );
        }
      } on _SessionClosing {
        completion.complete(WorldSessionCancelled<T>());
      } on WorldSessionException catch (failure) {
        completion.complete(
          failure.toFailure<T>(
            activeWorldChanged: !identical(before, _current),
          ),
        );
      } catch (error) {
        completion.complete(
          WorldSessionFailure<T>(
            error,
            activeWorldChanged: !identical(before, _current),
          ),
        );
      } finally {
        _pending--;
        _publish();
      }
    });
    return completion.future;
  }

  Future<WorldSessionResult<void>> switchWorld(WorldDocument document) =>
      _run(() async {
        if (document.metadata.id != _current.worldId) await _replace(document);
      });

  Future<WorldSessionResult<void>> loadWorld(String id) => _run(() async {
    if (id == _current.worldId) return;
    final document = await repository.load(id);
    if (document == null) throw WorldNotFoundException(id);
    await _replace(document);
  });

  Future<WorldSessionResult<void>> createWorld(WorldDocument document) =>
      _run(() async {
        await repository.create(document);
        try {
          await _replace(document);
        } catch (error) {
          throw _failure(error, durable: true);
        }
      });

  Future<WorldSessionResult<void>> importWorld(
    Uint8List bytes, {
    required WorldMetadata legacyMetadata,
  }) => _run(() async {
    await repository.importBytes(bytes, legacyMetadata: legacyMetadata);
  });

  Future<WorldSessionResult<void>> saveCurrent() =>
      _run(() => _withSnapshot(_current.worldId, () async {}));

  Future<WorldSessionResult<void>> rename(String id, String name) => _run(() {
    var written = false;
    return _withSnapshot(id, () async {
      final summary = await repository.rename(id, name);
      if (summary == null) throw WorldNotFoundException(id);
      written = true;
      if (id == _current.worldId) {
        try {
          _current.replaceMetadata(summary.metadata);
        } catch (error) {
          _faulted = _unsafeToSave = true;
          throw _failure(error, durable: true);
        }
      }
    }, durableChanged: () => written);
  });

  Future<WorldSessionResult<Uint8List>> exportWorld(String id) =>
      _run(() => _withSnapshot(id, () => repository.exportBytes(id)));

  Future<WorldSessionResult<void>> duplicateWorld(
    String id,
    WorldMetadata Function(WorldDocument source) metadata,
  ) => _run(() {
    var written = false;
    return _withSnapshot(id, () async {
      final source = await repository.load(id);
      if (source == null) throw WorldNotFoundException(id);
      final duplicate = await repository.duplicate(id, metadata(source));
      if (duplicate == null) throw WorldNotFoundException(id);
      written = true;
    }, durableChanged: () => written);
  });

  Future<WorldSessionResult<void>> reset(
    String id,
    WorldDocument Function(WorldDocument current) buildReset,
  ) => _run(() async {
    await _withSnapshot(id, () async {
      final original = await repository.load(id);
      if (original == null) throw WorldNotFoundException(id);
      final reset = buildReset(original);
      if (reset.metadata.id != id) {
        throw ArgumentError('Reset changed world id');
      }
      if (id == _current.worldId) {
        await _replace(
          reset,
          previousSnapshot: original,
          alreadyQuiesced: true,
        );
      } else {
        await repository.save(reset);
      }
    });
  });

  Future<WorldSessionResult<void>> delete(
    String id, {
    required Future<WorldDocument> Function() replacement,
  }) => _run(() async {
    if (id == _current.worldId) {
      final next = await replacement();
      if (next.metadata.id == id) {
        throw ArgumentError('Cannot switch to deleted world');
      }
      await _replace(next);
    }
    await repository.delete(id);
  });

  Future<T> _withSnapshot<T>(
    String id,
    Future<T> Function() action, {
    bool Function()? durableChanged,
  }) async {
    final runtime = _current;
    if (id != runtime.worldId) return action();
    late T value;
    Object? primaryError;
    final cleanup = <Object>[];
    try {
      await runtime.quiesce();
      await runtime.save();
      _ensureAttached();
      value = await action();
    } catch (error) {
      primaryError = error;
    }
    if (identical(runtime, _current) && !_stopping && !_faulted) {
      try {
        await _restore(runtime);
      } catch (error) {
        cleanup.add(error);
      }
    }
    if (primaryError is _SessionClosing && cleanup.isEmpty) throw primaryError;
    if (primaryError != null) {
      throw _failure(
        primaryError,
        durable: durableChanged?.call() ?? false,
        cleanup: cleanup,
      );
    }
    if (cleanup.isNotEmpty) {
      throw _failure(
        cleanup.first,
        durable: durableChanged?.call() ?? false,
        cleanup: cleanup.skip(1),
      );
    }
    return value;
  }

  Future<void> _replace(
    WorldDocument document, {
    WorldDocument? previousSnapshot,
    bool alreadyQuiesced = false,
  }) async {
    final previous = _current;
    WorldSessionRuntime? candidate;
    bool committed = false;
    bool written = false;
    try {
      // Factory failure owns its partial allocations; no game is mounted yet.
      candidate = await createRuntime(document);
      _ensureAttached();
      if (!alreadyQuiesced) {
        await previous.quiesce();
        await previous.save();
      }
      _ensureAttached();
      await host.stage(candidate);
      _ensureAttached();
      if (previousSnapshot != null) {
        await repository.save(document);
        written = true;
        _ensureAttached();
      }
      // Resume is synchronous: no async gap separates activation and commit.
      candidate.resume();
      host.commit(candidate);
      _current = candidate;
      committed = true;
      _publish();
    } catch (error) {
      final cleanup = <Object>[];
      var candidateReleased = candidate == null;
      if (candidate != null && !committed) {
        try {
          await candidate.quiesce();
        } catch (failure) {
          cleanup.add(failure);
          _faulted = true;
        }
        try {
          await _retire(candidate);
          candidateReleased = true;
        } catch (failure) {
          cleanup.add(failure);
          _faulted = true;
        }
      }
      if (written && !candidateReleased) {
        // A surviving candidate writer may still target this same world ID.
        // Do not race it with rollback or save the stale current snapshot.
        _faulted = _unsafeToSave = true;
      } else if (written) {
        try {
          await repository.save(previousSnapshot!);
          written = false;
        } catch (failure) {
          cleanup.add(failure);
          _faulted = _unsafeToSave = true;
        }
      }
      if (!_stopping && !_faulted && !alreadyQuiesced) {
        try {
          await _restore(previous);
        } catch (failure) {
          cleanup.add(failure);
        }
      }
      if (error is _SessionClosing && cleanup.isEmpty) rethrow;
      throw _failure(error, durable: written, cleanup: cleanup);
    }
    try {
      await _retire(previous);
    } catch (error) {
      throw _failure(error, durable: previousSnapshot != null);
    }
  }

  Future<void> _restore(WorldSessionRuntime runtime) async {
    if (_stopping || _faulted) return;
    try {
      runtime.resume();
    } catch (error) {
      _faulted = true;
      final cleanupErrors = CleanupErrors();
      try {
        await runtime.quiesce();
      } catch (cleanup) {
        cleanupErrors.add(cleanup);
      }
      if (!cleanupErrors.isEmpty) {
        throw WorldSessionException(error, cleanupErrors: cleanupErrors.values);
      }
      rethrow;
    }
  }

  Future<void> _retire(WorldSessionRuntime runtime) async {
    _retiring.add(runtime);
    await host.remove(runtime);
    await runtime.release();
    _retiring.remove(runtime);
  }

  void _ensureAttached() {
    if (_stopping) throw const _SessionClosing();
  }

  Future<void> close() {
    if (_lifecycle == _SessionLifecycle.closed) return Future.value();
    if (_closing case final closing?) return closing;
    _epoch++;
    _lifecycle = _SessionLifecycle.closing;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    await _tail;
    final errors = CleanupErrors();
    try {
      if (!_currentReleased) {
        await _current.quiesce();
        if (!_unsafeToSave && !_closeSaveAttempted) {
          _closeSaveAttempted = true;
          await _current.save();
        }
      }
    } catch (error) {
      errors.add(error);
    }
    if (!_currentReleased) _retiring.add(_current);
    for (final runtime in _retiring.toList()) {
      try {
        await _retire(runtime);
        if (identical(runtime, _current)) _currentReleased = true;
      } catch (error) {
        errors.add(error);
      }
    }
    if (!errors.isEmpty) {
      _faulted = true;
      _lifecycle = _SessionLifecycle.active;
      _closing = null;
      throw WorldSessionException(errors.first, cleanupErrors: errors.rest);
    }
    _lifecycle = _SessionLifecycle.closed;
  }

  void _publish() {
    if (!_disposed) onChanged?.call();
  }

  void dispose() {
    _disposed = true;
  }
}

final class _SessionClosing implements Exception {
  const _SessionClosing();
}

enum _SessionLifecycle { active, closing, closed }

WorldSessionException _failure(
  Object error, {
  bool durable = false,
  Iterable<Object> cleanup = const [],
}) {
  if (error is WorldSessionException) {
    final cleanupErrors = CleanupErrors()..addAll(error.cleanupErrors);
    cleanupErrors.addAll(cleanup);
    return WorldSessionException(
      error.error,
      durableStateChanged: durable || error.durableStateChanged,
      cleanupErrors: cleanupErrors.values,
    );
  }
  final cleanupErrors = CleanupErrors()..addAll(cleanup);
  return WorldSessionException(
    error,
    durableStateChanged: durable,
    cleanupErrors: cleanupErrors.values,
  );
}
