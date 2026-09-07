import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:minedart_core/minedart_core.dart';

import '../../data/worlds/world_models.dart';
import '../../data/worlds/world_repository.dart';

final class RepositoryAutosaver {
  RepositoryAutosaver({
    required this.repository,
    required this.world,
    required WorldMetadata metadata,
    required this.readSpawn,
    this.interval = const Duration(seconds: 60),
    this.onError,
    // The public constructor intentionally exposes a readable parameter.
    // ignore: prefer_initializing_formals
  }) : _metadata = metadata;

  final WorldRepository repository;
  final VoxelWorld world;
  final WorldSpawn Function() readSpawn;
  final Duration interval;
  final void Function(Object error, StackTrace stackTrace)? onError;

  WorldMetadata _metadata;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Future<void>? _saveTask;
  bool _queued = false;

  WorldMetadata get metadata => _metadata;

  /// Keeps repository-side metadata changes (for example a rename) from
  /// being overwritten by the next runtime snapshot.
  void replaceMetadata(WorldMetadata metadata) {
    if (metadata.id != _metadata.id) {
      throw ArgumentError.value(metadata.id, 'metadata.id', _metadata.id);
    }
    if (_timer != null || _lifecycle != null || _saveTask != null) {
      throw StateError(
        'Stop and drain autosave before replacing durable metadata',
      );
    }
    _metadata = metadata;
  }

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(saveSafely()));
    _lifecycle ??= AppLifecycleListener(
      onExitRequested: () async {
        return await saveSafely()
            ? AppExitResponse.exit
            : AppExitResponse.cancel;
      },
    );
  }

  /// Boundary for timer/lifecycle calls whose futures cannot be surfaced to
  /// an awaiting UI action. Explicit [saveNow] calls still throw to callers.
  Future<bool> saveSafely() async {
    try {
      await saveNow();
      return true;
    } on Object catch (error, stackTrace) {
      (onError ?? _defaultErrorHandler)(error, stackTrace);
      return false;
    }
  }

  Future<void> saveNow() {
    _queued = true;
    return _saveTask ??= _drain();
  }

  Future<void> _drain() async {
    try {
      do {
        _queued = false;
        final now = DateTime.now().toUtc();
        _metadata = _metadata.copyWith(updatedAt: now, spawn: readSpawn());
        await repository.save(
          WorldDocument.fromWorld(metadata: _metadata, world: world),
        );
      } while (_queued);
    } finally {
      _saveTask = null;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Stops background saves and waits for an already-running atomic write.
  /// Explicit [saveNow] remains available for an owner-controlled final save.
  Future<void> stopAndWait() async {
    stop();
    final task = _saveTask;
    if (task != null) await task;
  }
}

void _defaultErrorHandler(Object error, StackTrace stackTrace) {
  debugPrint('World autosave failed: $error\n$stackTrace');
}
