import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/performance/performance_snapshot_publisher.dart';
import 'package:minedart/performance/performance_telemetry.dart';

void main() {
  group('PerformanceSnapshotPublisher', () {
    test('publishes at the exact 250 ms boundary and never before it', () {
      final telemetry = PerformanceTelemetry(capacity: 4)..recordWallFrame(16);
      final publisher = PerformanceSnapshotPublisher(telemetry);

      final first = publisher.publishIfDue(elapsedMicroseconds: 0);
      expect(first, isNotNull);
      expect(first!.wallFrame.p50Ms, 16);
      expect(publisher.publicationCount, 1);
      expect(telemetry.debugSortPasses(PerformanceMetric.wallFrame), 1);

      telemetry.recordWallFrame(32);
      expect(publisher.publishIfDue(elapsedMicroseconds: 249999), isNull);
      expect(telemetry.debugSortPasses(PerformanceMetric.wallFrame), 1);

      final boundary = publisher.publishIfDue(elapsedMicroseconds: 250000);
      expect(boundary, isNotNull);
      expect(boundary!.wallFrame.sampleCount, 2);
      expect(publisher.publicationCount, 2);
      expect(publisher.latest, same(boundary));
      expect(telemetry.debugSortPasses(PerformanceMetric.wallFrame), 2);
      expect(publisher.publishIfDue(elapsedMicroseconds: 250000), isNull);
    });

    test('rejects an interval faster than four Hertz', () {
      final telemetry = PerformanceTelemetry();

      expect(
        () => PerformanceSnapshotPublisher(
          telemetry,
          interval: const Duration(microseconds: 249999),
        ),
        throwsArgumentError,
      );
      expect(
        PerformanceSnapshotPublisher(
          telemetry,
          interval: const Duration(milliseconds: 250),
        ).interval,
        const Duration(milliseconds: 250),
      );
    });

    test('requires one monotonic elapsed clock', () {
      final publisher = PerformanceSnapshotPublisher(PerformanceTelemetry());
      publisher.publishIfDue(elapsedMicroseconds: 1000);
      publisher.publishIfDue(elapsedMicroseconds: 2000);

      expect(
        () => publisher.publishIfDue(elapsedMicroseconds: 1500),
        throwsArgumentError,
      );
      expect(
        () => PerformanceSnapshotPublisher(
          PerformanceTelemetry(),
        ).publishIfDue(elapsedMicroseconds: -1),
        throwsArgumentError,
      );
    });
  });
}
