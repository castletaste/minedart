import 'dart:typed_data';

import 'performance_snapshot.dart';

/// Fixed-capacity double ring with preallocated percentile scratch storage.
///
/// [add] performs no sorting or buffer allocation. A percentile read copies
/// the live window into the retained scratch buffer and sorts that buffer once.
final class FixedCapacitySampleRing {
  FixedCapacitySampleRing({required this.capacity})
    : _samples = Float64List(capacity > 0 ? capacity : 0),
      _scratch = Float64List(capacity > 0 ? capacity : 0) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final Float64List _samples;
  final Float64List _scratch;

  int _length = 0;
  int _writeIndex = 0;
  int _totalSamples = 0;
  int _debugSortPasses = 0;
  double _sum = 0;

  int get length => _length;
  int get totalSamples => _totalSamples;
  bool get isEmpty => _length == 0;
  bool get isFull => _length == capacity;
  double get latest =>
      isEmpty ? 0 : _samples[(_writeIndex - 1 + capacity) % capacity];
  double get average => isEmpty ? 0 : _sum / _length;

  /// Diagnostic used by deterministic tests to prove sampling never sorts.
  int get debugSortPasses => _debugSortPasses;

  void add(double milliseconds) {
    validateSample(milliseconds);
    if (_length == capacity) {
      _sum -= _samples[_writeIndex];
    } else {
      _length++;
    }
    _samples[_writeIndex] = milliseconds;
    _sum += milliseconds;
    _writeIndex = (_writeIndex + 1) % capacity;
    _totalSamples++;
  }

  TimingPercentiles snapshotPercentiles() {
    if (isEmpty) return TimingPercentiles.empty;
    _prepareSortedScratch();
    return TimingPercentiles(
      sampleCount: _length,
      p50Ms: _nearestRank(0.50),
      p95Ms: _nearestRank(0.95),
      p99Ms: _nearestRank(0.99),
    );
  }

  double percentile(double quantile) {
    _validateQuantile(quantile);
    if (isEmpty) return 0;
    _prepareSortedScratch();
    return _nearestRank(quantile);
  }

  /// Copies live samples oldest-to-newest into caller-owned storage.
  int copyTo(Float64List destination) {
    if (destination.length < _length) {
      throw RangeError.range(
        destination.length,
        _length,
        null,
        'destination.length',
      );
    }
    final oldest = isFull ? _writeIndex : 0;
    for (var i = 0; i < _length; i++) {
      destination[i] = _samples[(oldest + i) % capacity];
    }
    return _length;
  }

  void clear() {
    _length = 0;
    _writeIndex = 0;
    _totalSamples = 0;
    _debugSortPasses = 0;
    _sum = 0;
  }

  static void validateSample(
    double milliseconds, {
    String name = 'milliseconds',
  }) {
    if (!milliseconds.isFinite || milliseconds < 0) {
      throw ArgumentError.value(
        milliseconds,
        name,
        'must be finite and non-negative',
      );
    }
  }

  void _prepareSortedScratch() {
    for (var i = 0; i < _length; i++) {
      _scratch[i] = _samples[i];
    }
    _heapSort(_length);
    _debugSortPasses++;
  }

  double _nearestRank(double quantile) {
    final rank = quantile == 0 ? 0 : (quantile * _length).ceil() - 1;
    return _scratch[rank.clamp(0, _length - 1)];
  }

  void _heapSort(int count) {
    if (count < 2) return;
    for (var start = (count - 2) ~/ 2; start >= 0; start--) {
      _siftDown(start, count - 1);
    }
    for (var end = count - 1; end > 0; end--) {
      final value = _scratch[end];
      _scratch[end] = _scratch[0];
      _scratch[0] = value;
      _siftDown(0, end - 1);
    }
  }

  void _siftDown(int root, int end) {
    while (root * 2 + 1 <= end) {
      var child = root * 2 + 1;
      var swapIndex = root;
      if (_scratch[swapIndex] < _scratch[child]) {
        swapIndex = child;
      }
      if (child + 1 <= end && _scratch[swapIndex] < _scratch[child + 1]) {
        swapIndex = child + 1;
      }
      if (swapIndex == root) return;
      final value = _scratch[root];
      _scratch[root] = _scratch[swapIndex];
      _scratch[swapIndex] = value;
      root = swapIndex;
    }
  }
}

void _validateQuantile(double quantile) {
  if (!quantile.isFinite || quantile < 0 || quantile > 1) {
    throw RangeError.range(quantile, 0, 1, 'quantile');
  }
}
