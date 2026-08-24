import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/performance/performance_telemetry.dart';

void main() {
  group('PerformanceTelemetry', () {
    test('keeps channel samples and write positions independent', () {
      final telemetry = PerformanceTelemetry(capacity: 3)
        ..recordWallFrame(16)
        ..recordUpdate(2)
        ..recordUpdate(4)
        ..recordCpuRender(7)
        ..recordMainThreadMesh(0.5)
        ..recordMainThreadMesh(1.5)
        ..recordMainThreadMesh(2.5)
        ..recordMainThreadMesh(3.5);

      final wallSamples = Float64List(3);
      final updateSamples = Float64List(3);
      expect(
        telemetry.copySamplesTo(
          wallSamples,
          metric: PerformanceMetric.wallFrame,
        ),
        1,
      );
      expect(
        telemetry.copySamplesTo(
          updateSamples,
          metric: PerformanceMetric.update,
        ),
        2,
      );
      expect(wallSamples.first, 16);
      expect(updateSamples.take(2), <double>[2, 4]);

      final snapshot = telemetry.snapshot();
      expect(snapshot.wallFrame.sampleCount, 1);
      expect(snapshot.wallFrame.p50Ms, 16);
      expect(snapshot.update.sampleCount, 2);
      expect(snapshot.update.p50Ms, 2);
      expect(snapshot.cpuRender.sampleCount, 1);
      expect(snapshot.cpuRender.p50Ms, 7);
      expect(snapshot.mainThreadMesh.sampleCount, 3);
      expect(snapshot.mainThreadMesh.p50Ms, 2.5);
    });

    test('recording does not sort and one snapshot sorts once per channel', () {
      final telemetry = PerformanceTelemetry(capacity: 4)
        ..recordTimings(
          wallFrameMs: 16,
          updateMs: 2,
          cpuRenderMs: 6,
          mainThreadMeshMs: 1,
        );

      for (final metric in PerformanceMetric.values) {
        expect(telemetry.debugSortPasses(metric), 0);
      }

      telemetry.snapshot();
      for (final metric in PerformanceMetric.values) {
        expect(telemetry.debugSortPasses(metric), 1);
      }

      telemetry.recordWallFrame(17);
      for (final metric in PerformanceMetric.values) {
        expect(telemetry.debugSortPasses(metric), 1);
      }
    });

    test('validates a multi-channel sample before mutating any ring', () {
      final telemetry = PerformanceTelemetry(capacity: 4);

      expect(
        () => telemetry.recordTimings(
          wallFrameMs: 16,
          updateMs: 2,
          cpuRenderMs: double.nan,
          mainThreadMeshMs: 1,
        ),
        throwsArgumentError,
      );

      for (final metric in PerformanceMetric.values) {
        expect(telemetry.sampleCount(metric), 0);
        expect(telemetry.totalSamples(metric), 0);
      }
    });

    test('accumulates mesh drain work into one consumed frame sample', () {
      final telemetry = PerformanceTelemetry(capacity: 3)
        ..accumulateMainThreadMesh(0.25)
        ..accumulateMainThreadMesh(0.75);

      expect(telemetry.pendingMainThreadMeshMs, 1);
      expect(telemetry.consumeMainThreadMesh(), 1);
      expect(telemetry.pendingMainThreadMeshMs, 0);
      expect(telemetry.consumeMainThreadMesh(), 0);

      final snapshot = telemetry.snapshot();
      expect(snapshot.mainThreadMesh.sampleCount, 2);
      expect(snapshot.mainThreadMesh.p50Ms, 0);
      expect(snapshot.mainThreadMesh.p95Ms, 1);
    });

    test('captures exact target, retention, and Web cache fields', () {
      final telemetry = PerformanceTelemetry(capacity: 2)
        ..updateSnapshotFields(
          drawCount: 83,
          meshQueue: 7,
          devicePixelRatio: 2,
          effectiveTargetWidth: 2560,
          effectiveTargetHeight: 1440,
          retainedComponentCount: 321,
          retainedMeshBytes: 987654,
          uniformUploadHits: 45,
          uniformUploadMisses: 3,
          bindGroupHits: 42,
          bindGroupMisses: 6,
        );

      final snapshot = telemetry.snapshot();
      expect(snapshot.drawCount, 83);
      expect(snapshot.meshQueue, 7);
      expect(snapshot.devicePixelRatio, 2);
      expect(snapshot.effectiveTargetWidth, 2560);
      expect(snapshot.effectiveTargetHeight, 1440);
      expect(snapshot.retainedComponentCount, 321);
      expect(snapshot.retainedMeshBytes, 987654);
      expect(snapshot.webCache.uniformUploadHits, 45);
      expect(snapshot.webCache.uniformUploadMisses, 3);
      expect(snapshot.webCache.bindGroupHits, 42);
      expect(snapshot.webCache.bindGroupMisses, 6);
    });

    test('rejects invalid snapshot fields atomically', () {
      final telemetry = PerformanceTelemetry(capacity: 2)
        ..updateSnapshotFields(
          drawCount: 1,
          meshQueue: 2,
          devicePixelRatio: 2,
          effectiveTargetWidth: 800,
          effectiveTargetHeight: 600,
          retainedComponentCount: 3,
          retainedMeshBytes: 4,
          uniformUploadHits: 5,
          uniformUploadMisses: 6,
          bindGroupHits: 7,
          bindGroupMisses: 8,
        );
      final before = telemetry.snapshot();

      expect(
        () => telemetry.updateSnapshotFields(
          drawCount: 10,
          meshQueue: 20,
          devicePixelRatio: double.nan,
          effectiveTargetWidth: 1600,
          effectiveTargetHeight: 1200,
          retainedComponentCount: 30,
          retainedMeshBytes: 40,
          uniformUploadHits: 50,
          uniformUploadMisses: 60,
          bindGroupHits: 70,
          bindGroupMisses: 80,
        ),
        throwsArgumentError,
      );
      expect(telemetry.snapshot(), before);
    });
  });
}
