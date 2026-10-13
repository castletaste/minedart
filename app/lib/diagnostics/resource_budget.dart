import 'package:flutter/foundation.dart';

/// Soft resource limits used by the runtime health readout.
@immutable
final class ResourceBudget {
  const ResourceBudget({
    this.maxPendingMeshJobs = 256,
    this.maxRetainedMeshBytes = 64 * 1024 * 1024,
    this.maxRetainedComponents = 512,
  });

  final int maxPendingMeshJobs;
  final int maxRetainedMeshBytes;
  final int maxRetainedComponents;

  ResourceBudgetStatus evaluate({
    required int pendingMeshJobs,
    required int retainedMeshBytes,
    required int retainedComponents,
  }) => ResourceBudgetStatus(
    pendingMeshJobs: pendingMeshJobs,
    retainedMeshBytes: retainedMeshBytes,
    retainedComponents: retainedComponents,
    pendingMeshJobsExceeded: pendingMeshJobs > maxPendingMeshJobs,
    retainedMeshBytesExceeded: retainedMeshBytes > maxRetainedMeshBytes,
    retainedComponentsExceeded: retainedComponents > maxRetainedComponents,
  );
}

@immutable
final class ResourceBudgetStatus {
  const ResourceBudgetStatus({
    required this.pendingMeshJobs,
    required this.retainedMeshBytes,
    required this.retainedComponents,
    required this.pendingMeshJobsExceeded,
    required this.retainedMeshBytesExceeded,
    required this.retainedComponentsExceeded,
  });

  final int pendingMeshJobs;
  final int retainedMeshBytes;
  final int retainedComponents;
  final bool pendingMeshJobsExceeded;
  final bool retainedMeshBytesExceeded;
  final bool retainedComponentsExceeded;

  bool get exceeded =>
      pendingMeshJobsExceeded ||
      retainedMeshBytesExceeded ||
      retainedComponentsExceeded;

  List<String> get violations => <String>[
    if (pendingMeshJobsExceeded) 'pending mesh jobs',
    if (retainedMeshBytesExceeded) 'retained mesh bytes',
    if (retainedComponentsExceeded) 'retained components',
  ];
}
