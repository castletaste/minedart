import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/render/frame_metrics.dart';

void main() {
  group('FrameMetrics', () {
    test('reports nearest-rank p50 p95 and p99', () {
      final metrics = FrameMetrics(capacity: 100);
      for (var value = 100; value >= 1; value--) {
        metrics.record(frameTimeMs: value.toDouble(), updateTimeMs: value / 2);
      }

      expect(metrics.p50, 50);
      expect(metrics.p95, 95);
      expect(metrics.p99, 99);
      expect(metrics.percentiles().p95, 95);
      expect(metrics.percentile(0.50, metric: FrameMetric.update), 25);
    });

    test('overwrites oldest samples at fixed capacity', () {
      final metrics = FrameMetrics(capacity: 3)
        ..add(1)
        ..add(2)
        ..add(3)
        ..add(4);
      final destination = Float64List(3);

      expect(metrics.length, 3);
      expect(metrics.totalSamples, 4);
      expect(metrics.isFull, isTrue);
      expect(metrics.latestFrameTimeMs, 4);
      expect(metrics.averageFrameTimeMs, 3);
      expect(metrics.p50, 3);
      expect(metrics.copyTo(destination), 3);
      expect(destination, <double>[2, 3, 4]);
    });

    test('records durations and clears without changing capacity', () {
      final metrics = FrameMetrics(capacity: 2)
        ..recordDuration(
          const Duration(microseconds: 16667),
          render: const Duration(milliseconds: 7),
        );

      expect(metrics.latestFrameTimeMs, closeTo(16.667, 0.0001));
      expect(metrics.percentile(1, metric: FrameMetric.render), 7);
      metrics.clear();
      expect(metrics.length, 0);
      expect(metrics.capacity, 2);
      expect(metrics.percentiles(), same(FramePercentiles.zero));
    });

    test('rejects invalid samples before mutating the ring', () {
      final metrics = FrameMetrics(capacity: 4)..add(16);

      expect(
        () => metrics.record(frameTimeMs: double.nan),
        throwsArgumentError,
      );
      expect(() => metrics.record(frameTimeMs: -1), throwsArgumentError);
      expect(metrics.length, 1);
      expect(metrics.latestFrameTimeMs, 16);
    });

    test('supports independent explicitly named CPU timing channels', () {
      final metrics = FrameMetrics(capacity: 4)
        ..recordWallFrame(16)
        ..recordUpdate(2)
        ..recordUpdate(4)
        ..recordCpuRender(6)
        ..recordMainThreadMesh(1);

      final snapshot = metrics.snapshot();
      expect(snapshot.wallFrame.sampleCount, 1);
      expect(snapshot.update.sampleCount, 2);
      expect(snapshot.cpuRender.sampleCount, 1);
      expect(snapshot.cpuRender.p50Ms, 6);
      expect(snapshot.mainThreadMesh.sampleCount, 1);
      expect(snapshot.mainThreadMesh.p50Ms, 1);
    });
  });
}
