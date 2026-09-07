part of 'mesh_pipeline_io.dart';

typedef _WorkerMessageHandler =
    void Function(_WorkerSlot slot, Object? message);
typedef _WorkerLossHandler = void Function(_WorkerSlot slot, Object cause);

/// Owns native isolate slots and every port opened for them.
///
/// Scheduling and retry policy deliberately stay in [MeshPipeline]. This class
/// only provides atomic spawn/register, loss, and close operations so an
/// isolate can never outlive its ports or disappear between handshake and
/// registration.
final class _WorkerFleet {
  _WorkerFleet({
    required this.spawnWorker,
    required this.onMessage,
    required this.onLoss,
    this.afterHandshake,
  });

  final MeshWorkerSpawner spawnWorker;
  final _WorkerMessageHandler onMessage;
  final _WorkerLossHandler onLoss;
  final Future<void> Function(int slotId)? afterHandshake;
  final Map<int, _WorkerSlot> _slots = <int, _WorkerSlot>{};
  final Set<_WorkerSlot> _provisionalSlots = <_WorkerSlot>{};

  var _activeSpawnOperations = 0;
  Completer<void>? _spawnOperationsIdle;
  bool _closing = false;

  Iterable<_WorkerSlot> get slots => _slots.values;
  int get liveCount => _slots.length;

  Future<_WorkerSlot> spawnAndRegister({
    required int slotId,
    required int restartCount,
  }) async {
    if (_closing) {
      throw StateError('Mesh worker fleet is closing');
    }
    _activeSpawnOperations++;
    try {
      final slot = await _spawnSlot(slotId: slotId, restartCount: restartCount);
      if (_closing) {
        destroy(slot);
        throw StateError('Mesh worker fleet closed during startup');
      }
      if (!slot.isHealthy) {
        destroy(slot);
        throw StateError('Cannot register dead worker ${slot.id}');
      }
      _slots[slot.id] = slot;
      _provisionalSlots.remove(slot);
      return slot;
    } finally {
      _activeSpawnOperations--;
      final idle = _spawnOperationsIdle;
      if (_activeSpawnOperations == 0 && idle != null && !idle.isCompleted) {
        idle.complete();
      }
    }
  }

  /// Atomically marks [slot] lost and releases its isolate and ports.
  ///
  /// Returns false when another signal or shutdown already released the slot.
  bool lose(_WorkerSlot slot, Object cause) {
    if (slot.lost || slot.destroyed) return false;
    slot.lost = true;
    if (!slot.handshake.isCompleted) {
      slot.handshake.completeError(cause);
    }
    if (_slots[slot.id] == slot) _slots.remove(slot.id);
    _destroy(slot);
    return true;
  }

  void destroy(_WorkerSlot slot) {
    if (slot.destroyed) return;
    if (_slots[slot.id] == slot) _slots.remove(slot.id);
    _destroy(slot);
  }

  Future<void> close() async {
    _closing = true;
    for (final slot in _slots.values.toList()) {
      destroy(slot);
    }
    for (final slot in _provisionalSlots.toList()) {
      destroy(slot);
    }
    await _waitForSpawnOperations();
  }

  Future<_WorkerSlot> _spawnSlot({
    required int slotId,
    required int restartCount,
  }) async {
    final messagePort = ReceivePort('mesh-worker-$slotId-messages');
    final errorPort = ReceivePort('mesh-worker-$slotId-errors');
    final exitPort = ReceivePort('mesh-worker-$slotId-exit');
    final slot = _WorkerSlot(
      id: slotId,
      restartCount: restartCount,
      messagePort: messagePort,
      errorPort: errorPort,
      exitPort: exitPort,
    );
    _provisionalSlots.add(slot);

    messagePort.listen((message) => _handleMessage(slot, message));
    errorPort.listen(
      (error) => onLoss(slot, StateError('Worker isolate error: $error')),
    );
    exitPort.listen((_) => onLoss(slot, StateError('Worker isolate exited')));

    try {
      final isolate = await spawnWorker(
        meshWorkerMain,
        _WorkerBootstrap(messagePort.sendPort),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        debugName: 'mesh-worker-$slotId-$restartCount',
      );
      if (slot.destroyed || _closing) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('Mesh worker startup was cancelled');
      }
      slot.isolate = isolate;
      await slot.handshake.future.timeout(const Duration(seconds: 2));
      await afterHandshake?.call(slotId);
      if (!slot.isHealthy || _closing) {
        throw StateError('Worker $slotId exited during startup');
      }
      return slot;
    } catch (_) {
      destroy(slot);
      rethrow;
    }
  }

  void _handleMessage(_WorkerSlot slot, Object? message) {
    if (slot.destroyed) return;
    if (message case _WorkerReady(:final commands)) {
      if (slot.ready || slot.lost) return;
      slot
        ..commands = commands
        ..ready = true;
      if (!slot.handshake.isCompleted) slot.handshake.complete();
      return;
    }
    onMessage(slot, message);
  }

  void _destroy(_WorkerSlot slot) {
    _provisionalSlots.remove(slot);
    if (slot.isolate != null && !slot.handshake.isCompleted) {
      slot.handshake.completeError(
        StateError('Mesh worker was destroyed during startup'),
      );
    }
    slot
      ..destroyed = true
      ..isolate?.kill(priority: Isolate.immediate)
      ..messagePort.close()
      ..errorPort.close()
      ..exitPort.close();
  }

  Future<void> _waitForSpawnOperations() async {
    while (_activeSpawnOperations > 0) {
      _spawnOperationsIdle = Completer<void>();
      if (_activeSpawnOperations > 0) await _spawnOperationsIdle!.future;
    }
    _spawnOperationsIdle = null;
  }
}

final class _WorkerSlot {
  _WorkerSlot({
    required this.id,
    required this.restartCount,
    required this.messagePort,
    required this.errorPort,
    required this.exitPort,
  });

  final int id;
  final int restartCount;
  final ReceivePort messagePort;
  final ReceivePort errorPort;
  final ReceivePort exitPort;
  final Completer<void> handshake = Completer<void>();
  Isolate? isolate;
  SendPort? commands;
  int? activePhysicalJobId;
  bool ready = false;
  bool lost = false;
  bool destroyed = false;

  bool get isHealthy => ready && !lost && !destroyed && commands != null;
}
