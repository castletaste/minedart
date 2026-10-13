import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/diagnostics/diagnostics.dart';
import 'package:minedart/performance/performance_telemetry.dart';

void main() {
  test('diagnostics classify budget and lifecycle problems', () {
    final telemetry = PerformanceTelemetry();
    telemetry.updateSnapshotFields(
      drawCount: 0,
      meshQueue: 3,
      devicePixelRatio: 1,
      effectiveTargetWidth: 0,
      effectiveTargetHeight: 0,
      retainedComponentCount: 4,
      retainedMeshBytes: 101,
      uniformUploadHits: 0,
      uniformUploadMisses: 0,
      bindGroupHits: 0,
      bindGroupMisses: 0,
    );
    final diagnostics =
        DiagnosticsCollector(
          budget: const ResourceBudget(
            maxPendingMeshJobs: 2,
            maxRetainedMeshBytes: 100,
            maxRetainedComponents: 3,
          ),
        )..updateState(
          sessionEpoch: 4,
          sessionBusy: true,
          inputActive: true,
          rendererReady: true,
          activeChunks: 5,
        )..updatePerformance(telemetry.snapshot());

    final snapshot = diagnostics.publish();
    expect(snapshot.health, DiagnosticsHealth.warning);
    expect(snapshot.issues, contains('budget: pending mesh jobs'));
    expect(snapshot.toJson()['sessionEpoch'], 4);
    diagnostics.dispose();
  });

  test('healthy snapshot is JSON stable for diagnostic exports', () {
    final diagnostics = DiagnosticsCollector()
      ..updateState(
        inputActive: true,
        rendererReady: true,
        activeChunks: 8,
      );
    final snapshot = diagnostics.publish();
    expect(snapshot.health, DiagnosticsHealth.healthy);
    expect(snapshot.encode(), contains('"health":"healthy"'));
    diagnostics.dispose();
  });

  test('storage failure remains critical while soft budgets stay warnings', () {
    final diagnostics = DiagnosticsCollector()
      ..updateState(storageReady: false);

    expect(diagnostics.publish().health, DiagnosticsHealth.critical);
    diagnostics.dispose();
  });
}
