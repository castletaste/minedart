import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/diagnostics/diagnostics.dart';
import 'package:minedart/performance/performance_telemetry.dart';
import 'package:minedart/showcase/ui/developer_health_panel.dart';

void main() {
  test('health formatting exposes actionable runtime state', () {
    final telemetry = PerformanceTelemetry();
    telemetry.updateSnapshotFields(
      drawCount: 0,
      meshQueue: 2,
      devicePixelRatio: 1,
      effectiveTargetWidth: 0,
      effectiveTargetHeight: 0,
      retainedComponentCount: 0,
      retainedMeshBytes: 0,
      uniformUploadHits: 0,
      uniformUploadMisses: 0,
      bindGroupHits: 0,
      bindGroupMisses: 0,
    );
    final collector = DiagnosticsCollector()
      ..updateState(
        sessionEpoch: 3,
        inputActive: true,
        rendererReady: true,
        activeChunks: 9,
      )
      ..updatePerformance(telemetry.snapshot());
    final text = formatDeveloperHealth(collector.publish());

    expect(text, contains('health HEALTHY'));
    expect(text, contains('epoch 3'));
    expect(text, contains('active chunks 9'));
    collector.dispose();
  });
}
