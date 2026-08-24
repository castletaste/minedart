import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/performance/fixed_capacity_sample_ring.dart';

void main() {
  group('FixedCapacitySampleRing', () {
    test('overwrites the oldest sample without changing capacity', () {
      final ring = FixedCapacitySampleRing(capacity: 3)
        ..add(1)
        ..add(2)
        ..add(3)
        ..add(4);
      final samples = Float64List(3);

      expect(ring.capacity, 3);
      expect(ring.length, 3);
      expect(ring.totalSamples, 4);
      expect(ring.isFull, isTrue);
      expect(ring.latest, 4);
      expect(ring.average, 3);
      expect(ring.copyTo(samples), 3);
      expect(samples, <double>[2, 3, 4]);
    });

    test('computes all nearest-rank percentiles with one sort', () {
      final ring = FixedCapacitySampleRing(capacity: 100);
      for (var value = 100; value >= 1; value--) {
        ring.add(value.toDouble());
      }

      expect(ring.debugSortPasses, 0);
      final snapshot = ring.snapshotPercentiles();

      expect(snapshot.sampleCount, 100);
      expect(snapshot.p50Ms, 50);
      expect(snapshot.p95Ms, 95);
      expect(snapshot.p99Ms, 99);
      expect(ring.debugSortPasses, 1);
    });

    test('rejects invalid samples before mutating the ring', () {
      final ring = FixedCapacitySampleRing(capacity: 2)..add(16);

      expect(() => ring.add(double.nan), throwsArgumentError);
      expect(() => ring.add(double.infinity), throwsArgumentError);
      expect(() => ring.add(-0.001), throwsArgumentError);
      expect(ring.length, 1);
      expect(ring.latest, 16);
      expect(ring.totalSamples, 1);
      expect(ring.debugSortPasses, 0);
    });

    test('rejects non-positive capacity', () {
      expect(() => FixedCapacitySampleRing(capacity: 0), throwsArgumentError);
    });
  });
}
