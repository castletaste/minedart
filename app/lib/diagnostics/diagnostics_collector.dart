import 'package:flutter/foundation.dart';

import '../performance/fixed_capacity_sample_ring.dart';
import '../performance/performance_snapshot.dart';
import 'diagnostics_snapshot.dart';
import 'resource_budget.dart';

/// Allocation-stable runtime diagnostics with a throttled immutable boundary.
final class DiagnosticsCollector {
  DiagnosticsCollector({
    this.budget = const ResourceBudget(),
  }) : _persistence = FixedCapacitySampleRing(capacity: 32),
       snapshot = ValueNotifier<DiagnosticsSnapshot>(DiagnosticsSnapshot.empty);

  final ResourceBudget budget;
  final FixedCapacitySampleRing _persistence;
  final ValueNotifier<DiagnosticsSnapshot> snapshot;
  PerformanceSnapshot _performance = PerformanceSnapshot.empty;

  int _sessionEpoch = 0;
  bool _sessionBusy = false;
  bool _sessionFaulted = false;
  bool _inputActive = false;
  bool _rendererReady = false;
  bool _storageReady = true;
  int _activeChunks = 0;

  void recordPersistence(double milliseconds) =>
      _persistence.add(milliseconds);

  /// Supplies the already-published performance model instead of maintaining
  /// a second frame/mesh telemetry ring inside diagnostics.
  void updatePerformance(PerformanceSnapshot performance) {
    _performance = performance;
  }

  void updateState({
    int? sessionEpoch,
    bool? sessionBusy,
    bool? sessionFaulted,
    bool? inputActive,
    bool? rendererReady,
    bool? storageReady,
    int? activeChunks,
  }) {
    _sessionEpoch = sessionEpoch ?? _sessionEpoch;
    _sessionBusy = sessionBusy ?? _sessionBusy;
    _sessionFaulted = sessionFaulted ?? _sessionFaulted;
    _inputActive = inputActive ?? _inputActive;
    _rendererReady = rendererReady ?? _rendererReady;
    _storageReady = storageReady ?? _storageReady;
    _activeChunks = activeChunks ?? _activeChunks;
  }

  DiagnosticsSnapshot publish() {
    final next = DiagnosticsSnapshot(
      sessionEpoch: _sessionEpoch,
      sessionBusy: _sessionBusy,
      sessionFaulted: _sessionFaulted,
      inputActive: _inputActive,
      rendererReady: _rendererReady,
      storageReady: _storageReady,
      meshQueue: _performance.meshQueue,
      activeChunks: _activeChunks,
      retainedComponents: _performance.retainedComponentCount,
      retainedMeshBytes: _performance.retainedMeshBytes,
      tick: _performance.update,
      persistence: _persistence.snapshotPercentiles(),
      budget: budget.evaluate(
        pendingMeshJobs: _performance.meshQueue,
        retainedMeshBytes: _performance.retainedMeshBytes,
        retainedComponents: _performance.retainedComponentCount,
      ),
    );
    snapshot.value = next;
    return next;
  }

  void dispose() => snapshot.dispose();
}
