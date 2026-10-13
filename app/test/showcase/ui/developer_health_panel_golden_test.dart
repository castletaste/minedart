import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/diagnostics/diagnostics.dart';
import 'package:minedart/performance/performance_telemetry.dart';
import 'package:minedart/showcase/ui/developer_health_panel.dart';

void main() {
  testWidgets('developer health panel golden', (tester) async {
    final telemetry = PerformanceTelemetry();
    telemetry.updateSnapshotFields(
      drawCount: 0,
      meshQueue: 2,
      devicePixelRatio: 1,
      effectiveTargetWidth: 0,
      effectiveTargetHeight: 0,
      retainedComponentCount: 18,
      retainedMeshBytes: 4096,
      uniformUploadHits: 0,
      uniformUploadMisses: 0,
      bindGroupHits: 0,
      bindGroupMisses: 0,
    );
    final collector = DiagnosticsCollector()
      ..updateState(
        sessionEpoch: 7,
        inputActive: true,
        rendererReady: true,
        activeChunks: 12,
      )
      ..updatePerformance(telemetry.snapshot());
    final snapshot = collector.publish();

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const Key('health-golden'),
          child: ColoredBox(
            color: const Color(0xFF121812),
            child: SizedBox(
              width: 360,
              height: 120,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: DeveloperHealthPanel(snapshot: snapshot),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const Key('health-golden')),
      matchesGoldenFile('goldens/developer_health_panel.png'),
    );
    collector.dispose();
  });
}
