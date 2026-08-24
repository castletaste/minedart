import 'dart:typed_data';

/// Timings retained by [FrameMetrics].
enum FrameMetric { frame, update, render, mesh }

/// Immutable percentile readout. Creating this is a UI/readout operation;
/// frame sampling itself remains allocation-stable.
final class FramePercentiles {
  const FramePercentiles({
    required this.p50,
    required this.p95,
    required this.p99,
  });

  static const FramePercentiles zero = FramePercentiles(p50: 0, p95: 0, p99: 0);

  final double p50;
  final double p95;
  final double p99;
}

/// Fixed-capacity, allocation-stable frame timing ring.
///
/// [record] only writes primitive values into preallocated typed buffers.
/// Percentile reads reuse one preallocated scratch buffer and use nearest-rank
/// quantiles, so repeated F3 readouts do not grow the heap either.
final class FrameMetrics {
  FrameMetrics({this.capacity = 240})
    : assert(capacity > 0),
      _frame = Float64List(capacity),
      _update = Float64List(capacity),
      _render = Float64List(capacity),
      _mesh = Float64List(capacity),
      _scratch = Float64List(capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final Float64List _frame;
  final Float64List _update;
  final Float64List _render;
  final Float64List _mesh;
  final Float64List _scratch;

  int _length = 0;
  int _writeIndex = 0;
  int _totalSamples = 0;
  double _frameSum = 0;

  int get length => _length;
  int get totalSamples => _totalSamples;
  bool get isEmpty => _length == 0;
  bool get isFull => _length == capacity;
  double get latestFrameTimeMs =>
      isEmpty ? 0 : _frame[(_writeIndex - 1 + capacity) % capacity];
  double get averageFrameTimeMs => isEmpty ? 0 : _frameSum / _length;
  double get averageFps =>
      averageFrameTimeMs <= 0 ? 0 : 1000 / averageFrameTimeMs;

  double get p50 => percentile(0.50);
  double get p95 => percentile(0.95);
  double get p99 => percentile(0.99);

  /// Adds one sample in milliseconds without allocating an intermediate object.
  void record({
    required double frameTimeMs,
    double updateTimeMs = 0,
    double renderTimeMs = 0,
    double meshTimeMs = 0,
  }) {
    _checkTiming(frameTimeMs, 'frameTimeMs');
    _checkTiming(updateTimeMs, 'updateTimeMs');
    _checkTiming(renderTimeMs, 'renderTimeMs');
    _checkTiming(meshTimeMs, 'meshTimeMs');

    if (_length == capacity) {
      _frameSum -= _frame[_writeIndex];
    } else {
      _length++;
    }
    _frame[_writeIndex] = frameTimeMs;
    _update[_writeIndex] = updateTimeMs;
    _render[_writeIndex] = renderTimeMs;
    _mesh[_writeIndex] = meshTimeMs;
    _frameSum += frameTimeMs;
    _writeIndex = (_writeIndex + 1) % capacity;
    _totalSamples++;
  }

  void add(double frameTimeMs) => record(frameTimeMs: frameTimeMs);

  void recordDuration(
    Duration frame, {
    Duration update = Duration.zero,
    Duration render = Duration.zero,
    Duration mesh = Duration.zero,
  }) => record(
    frameTimeMs: frame.inMicroseconds / 1000,
    updateTimeMs: update.inMicroseconds / 1000,
    renderTimeMs: render.inMicroseconds / 1000,
    meshTimeMs: mesh.inMicroseconds / 1000,
  );

  double percentile(double quantile, {FrameMetric metric = FrameMetric.frame}) {
    if (quantile < 0 || quantile > 1 || !quantile.isFinite) {
      throw RangeError.range(quantile, 0, 1, 'quantile');
    }
    if (_length == 0) return 0;
    final source = _bufferFor(metric);
    for (var i = 0; i < _length; i++) {
      _scratch[i] = source[i];
    }
    _sortScratch(_length);
    final rank = quantile == 0 ? 0 : (quantile * _length).ceil() - 1;
    return _scratch[rank.clamp(0, _length - 1)];
  }

  FramePercentiles percentiles({FrameMetric metric = FrameMetric.frame}) =>
      isEmpty
      ? FramePercentiles.zero
      : FramePercentiles(
          p50: percentile(0.50, metric: metric),
          p95: percentile(0.95, metric: metric),
          p99: percentile(0.99, metric: metric),
        );

  /// Copies samples oldest-to-newest into caller-owned storage.
  int copyTo(
    Float64List destination, {
    FrameMetric metric = FrameMetric.frame,
  }) {
    if (destination.length < _length) {
      throw RangeError.range(destination.length, _length, null, 'length');
    }
    final source = _bufferFor(metric);
    final oldest = _length == capacity ? _writeIndex : 0;
    for (var i = 0; i < _length; i++) {
      destination[i] = source[(oldest + i) % capacity];
    }
    return _length;
  }

  void clear() {
    _length = 0;
    _writeIndex = 0;
    _totalSamples = 0;
    _frameSum = 0;
  }

  Float64List _bufferFor(FrameMetric metric) => switch (metric) {
    FrameMetric.frame => _frame,
    FrameMetric.update => _update,
    FrameMetric.render => _render,
    FrameMetric.mesh => _mesh,
  };

  void _sortScratch(int count) {
    for (var i = 1; i < count; i++) {
      final value = _scratch[i];
      var j = i - 1;
      while (j >= 0 && _scratch[j] > value) {
        _scratch[j + 1] = _scratch[j];
        j--;
      }
      _scratch[j + 1] = value;
    }
  }
}

void _checkTiming(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'must be finite and non-negative');
  }
}
