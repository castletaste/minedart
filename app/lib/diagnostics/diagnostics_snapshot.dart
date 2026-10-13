import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../performance/performance_snapshot.dart';
import 'resource_budget.dart';

enum DiagnosticsHealth { healthy, warning, critical }

@immutable
final class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.sessionEpoch,
    required this.sessionBusy,
    required this.sessionFaulted,
    required this.inputActive,
    required this.rendererReady,
    required this.storageReady,
    required this.meshQueue,
    required this.activeChunks,
    required this.retainedComponents,
    required this.retainedMeshBytes,
    required this.tick,
    required this.persistence,
    required this.budget,
  });

  static const empty = DiagnosticsSnapshot(
    sessionEpoch: 0,
    sessionBusy: false,
    sessionFaulted: false,
    inputActive: false,
    rendererReady: false,
    storageReady: true,
    meshQueue: 0,
    activeChunks: 0,
    retainedComponents: 0,
    retainedMeshBytes: 0,
    tick: TimingPercentiles.empty,
    persistence: TimingPercentiles.empty,
    budget: ResourceBudgetStatus(
      pendingMeshJobs: 0,
      retainedMeshBytes: 0,
      retainedComponents: 0,
      pendingMeshJobsExceeded: false,
      retainedMeshBytesExceeded: false,
      retainedComponentsExceeded: false,
    ),
  );

  final int sessionEpoch;
  final bool sessionBusy;
  final bool sessionFaulted;
  final bool inputActive;
  final bool rendererReady;
  final bool storageReady;
  final int meshQueue;
  final int activeChunks;
  final int retainedComponents;
  final int retainedMeshBytes;
  final TimingPercentiles tick;
  final TimingPercentiles persistence;
  final ResourceBudgetStatus budget;

  DiagnosticsHealth get health {
    if (sessionFaulted || !storageReady) {
      return DiagnosticsHealth.critical;
    }
    if (sessionBusy || !rendererReady || !inputActive || budget.exceeded) {
      return DiagnosticsHealth.warning;
    }
    return DiagnosticsHealth.healthy;
  }

  List<String> get issues => <String>[
    if (sessionFaulted) 'session faulted',
    if (!storageReady) 'storage unavailable',
    if (!rendererReady) 'renderer not ready',
    if (!inputActive) 'input inactive',
    if (sessionBusy) 'session busy',
    ...budget.violations.map((value) => 'budget: $value'),
  ];

  Map<String, Object> toJson() => <String, Object>{
    'sessionEpoch': sessionEpoch,
    'sessionBusy': sessionBusy,
    'sessionFaulted': sessionFaulted,
    'inputActive': inputActive,
    'rendererReady': rendererReady,
    'storageReady': storageReady,
    'meshQueue': meshQueue,
    'activeChunks': activeChunks,
    'retainedComponents': retainedComponents,
    'retainedMeshBytes': retainedMeshBytes,
    'health': health.name,
    'issues': issues,
    'tick': _timingJson(tick),
    'persistence': _timingJson(persistence),
  };

  String encode() => jsonEncode(toJson());
}

Map<String, Object> _timingJson(TimingPercentiles timing) => <String, Object>{
  'sampleCount': timing.sampleCount,
  'p50Ms': timing.p50Ms,
  'p95Ms': timing.p95Ms,
  'p99Ms': timing.p99Ms,
};
