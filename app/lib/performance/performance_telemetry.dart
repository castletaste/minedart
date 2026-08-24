import 'dart:typed_data';

import 'fixed_capacity_sample_ring.dart';
import 'performance_snapshot.dart';

/// Independently sampled CPU/wall timing channels.
enum PerformanceMetric { wallFrame, update, cpuRender, mainThreadMesh }

/// Allocation-stable short-window performance sampler.
///
/// Four rings, four percentile scratch buffers, and four stopwatches are
/// retained for this object's lifetime. Recording never computes percentiles;
/// [snapshot] performs exactly one percentile sort for each non-empty channel.
final class PerformanceTelemetry {
  PerformanceTelemetry({this.capacity = 240})
    : _wallFrame = FixedCapacitySampleRing(capacity: capacity),
      _update = FixedCapacitySampleRing(capacity: capacity),
      _cpuRender = FixedCapacitySampleRing(capacity: capacity),
      _mainThreadMesh = FixedCapacitySampleRing(capacity: capacity);

  final int capacity;
  final FixedCapacitySampleRing _wallFrame;
  final FixedCapacitySampleRing _update;
  final FixedCapacitySampleRing _cpuRender;
  final FixedCapacitySampleRing _mainThreadMesh;

  final Stopwatch _wallFrameStopwatch = Stopwatch();
  final Stopwatch _updateStopwatch = Stopwatch();
  final Stopwatch _cpuRenderStopwatch = Stopwatch();
  final Stopwatch _mainThreadMeshStopwatch = Stopwatch();

  int _drawCount = 0;
  int _meshQueue = 0;
  double _devicePixelRatio = 0;
  int _effectiveTargetWidth = 0;
  int _effectiveTargetHeight = 0;
  int _retainedComponentCount = 0;
  int _retainedMeshBytes = 0;
  int _uniformUploadHits = 0;
  int _uniformUploadMisses = 0;
  int _bindGroupHits = 0;
  int _bindGroupMisses = 0;
  double _pendingMainThreadMeshMs = 0;

  int sampleCount(PerformanceMetric metric) => _ringFor(metric).length;
  int totalSamples(PerformanceMetric metric) => _ringFor(metric).totalSamples;
  double latestSample(PerformanceMetric metric) => _ringFor(metric).latest;
  double averageSample(PerformanceMetric metric) => _ringFor(metric).average;
  int debugSortPasses(PerformanceMetric metric) =>
      _ringFor(metric).debugSortPasses;
  double get pendingMainThreadMeshMs => _pendingMainThreadMeshMs;

  void recordWallFrame(double milliseconds) => _wallFrame.add(milliseconds);
  void recordUpdate(double milliseconds) => _update.add(milliseconds);

  /// Records CPU render submission work, never GPU execution time.
  void recordCpuRender(double milliseconds) => _cpuRender.add(milliseconds);

  /// Records main-thread CPU time spent draining completed mesh work.
  void recordMainThreadMesh(double milliseconds) =>
      _mainThreadMesh.add(milliseconds);

  /// Accumulates Web mesh-drain CPU work until the next frame consumes it.
  void accumulateMainThreadMesh(double milliseconds) {
    FixedCapacitySampleRing.validateSample(milliseconds, name: 'milliseconds');
    final next = _pendingMainThreadMeshMs + milliseconds;
    FixedCapacitySampleRing.validateSample(
      next,
      name: 'accumulatedMainThreadMeshMs',
    );
    _pendingMainThreadMeshMs = next;
  }

  /// Atomically resets the accumulator and records one per-frame CPU sample.
  double consumeMainThreadMesh() {
    final milliseconds = _pendingMainThreadMeshMs;
    _pendingMainThreadMeshMs = 0;
    _mainThreadMesh.add(milliseconds);
    return milliseconds;
  }

  /// Records any subset without inserting zeroes into omitted channels.
  ///
  /// Every supplied value is validated before any ring is mutated.
  void recordTimings({
    double? wallFrameMs,
    double? updateMs,
    double? cpuRenderMs,
    double? mainThreadMeshMs,
  }) {
    if (wallFrameMs != null) {
      FixedCapacitySampleRing.validateSample(wallFrameMs, name: 'wallFrameMs');
    }
    if (updateMs != null) {
      FixedCapacitySampleRing.validateSample(updateMs, name: 'updateMs');
    }
    if (cpuRenderMs != null) {
      FixedCapacitySampleRing.validateSample(cpuRenderMs, name: 'cpuRenderMs');
    }
    if (mainThreadMeshMs != null) {
      FixedCapacitySampleRing.validateSample(
        mainThreadMeshMs,
        name: 'mainThreadMeshMs',
      );
    }

    if (wallFrameMs != null) _wallFrame.add(wallFrameMs);
    if (updateMs != null) _update.add(updateMs);
    if (cpuRenderMs != null) _cpuRender.add(cpuRenderMs);
    if (mainThreadMeshMs != null) _mainThreadMesh.add(mainThreadMeshMs);
  }

  /// Starts one of the retained stopwatches after resetting its old value.
  void startTiming(PerformanceMetric metric) {
    final stopwatch = _stopwatchFor(metric);
    if (stopwatch.isRunning) {
      throw StateError('$metric timing is already running');
    }
    stopwatch
      ..reset()
      ..start();
  }

  /// Stops a retained stopwatch and records its elapsed milliseconds.
  double stopAndRecordTiming(PerformanceMetric metric) {
    final stopwatch = _stopwatchFor(metric);
    if (!stopwatch.isRunning) {
      throw StateError('$metric timing is not running');
    }
    stopwatch.stop();
    final milliseconds = stopwatch.elapsedMicroseconds / 1000;
    _ringFor(metric).add(milliseconds);
    return milliseconds;
  }

  void cancelTiming(PerformanceMetric metric) {
    _stopwatchFor(metric)
      ..stop()
      ..reset();
  }

  /// Atomically replaces the scalar fields captured by the next snapshot.
  ///
  /// Cache counts are for one completed Web frame. Native callers report zero.
  void updateSnapshotFields({
    required int drawCount,
    required int meshQueue,
    required double devicePixelRatio,
    required int effectiveTargetWidth,
    required int effectiveTargetHeight,
    required int retainedComponentCount,
    required int retainedMeshBytes,
    required int uniformUploadHits,
    required int uniformUploadMisses,
    required int bindGroupHits,
    required int bindGroupMisses,
  }) {
    _validateNonNegative(drawCount, 'drawCount');
    _validateNonNegative(meshQueue, 'meshQueue');
    if (!devicePixelRatio.isFinite || devicePixelRatio < 0) {
      throw ArgumentError.value(
        devicePixelRatio,
        'devicePixelRatio',
        'must be finite and non-negative',
      );
    }
    _validateNonNegative(effectiveTargetWidth, 'effectiveTargetWidth');
    _validateNonNegative(effectiveTargetHeight, 'effectiveTargetHeight');
    _validateNonNegative(retainedComponentCount, 'retainedComponentCount');
    _validateNonNegative(retainedMeshBytes, 'retainedMeshBytes');
    _validateNonNegative(uniformUploadHits, 'uniformUploadHits');
    _validateNonNegative(uniformUploadMisses, 'uniformUploadMisses');
    _validateNonNegative(bindGroupHits, 'bindGroupHits');
    _validateNonNegative(bindGroupMisses, 'bindGroupMisses');

    _drawCount = drawCount;
    _meshQueue = meshQueue;
    _devicePixelRatio = devicePixelRatio;
    _effectiveTargetWidth = effectiveTargetWidth;
    _effectiveTargetHeight = effectiveTargetHeight;
    _retainedComponentCount = retainedComponentCount;
    _retainedMeshBytes = retainedMeshBytes;
    _uniformUploadHits = uniformUploadHits;
    _uniformUploadMisses = uniformUploadMisses;
    _bindGroupHits = bindGroupHits;
    _bindGroupMisses = bindGroupMisses;
  }

  PerformanceSnapshot snapshot() => PerformanceSnapshot(
    wallFrame: _wallFrame.snapshotPercentiles(),
    update: _update.snapshotPercentiles(),
    cpuRender: _cpuRender.snapshotPercentiles(),
    mainThreadMesh: _mainThreadMesh.snapshotPercentiles(),
    drawCount: _drawCount,
    meshQueue: _meshQueue,
    devicePixelRatio: _devicePixelRatio,
    effectiveTargetWidth: _effectiveTargetWidth,
    effectiveTargetHeight: _effectiveTargetHeight,
    retainedComponentCount: _retainedComponentCount,
    retainedMeshBytes: _retainedMeshBytes,
    webCache: WebCacheCountersSnapshot(
      uniformUploadHits: _uniformUploadHits,
      uniformUploadMisses: _uniformUploadMisses,
      bindGroupHits: _bindGroupHits,
      bindGroupMisses: _bindGroupMisses,
    ),
  );

  TimingPercentiles percentiles(PerformanceMetric metric) =>
      _ringFor(metric).snapshotPercentiles();

  double percentile(PerformanceMetric metric, double quantile) =>
      _ringFor(metric).percentile(quantile);

  int copySamplesTo(
    Float64List destination, {
    required PerformanceMetric metric,
  }) => _ringFor(metric).copyTo(destination);

  void clearSamples() {
    _pendingMainThreadMeshMs = 0;
    for (final metric in PerformanceMetric.values) {
      cancelTiming(metric);
      _ringFor(metric).clear();
    }
  }

  FixedCapacitySampleRing _ringFor(PerformanceMetric metric) =>
      switch (metric) {
        PerformanceMetric.wallFrame => _wallFrame,
        PerformanceMetric.update => _update,
        PerformanceMetric.cpuRender => _cpuRender,
        PerformanceMetric.mainThreadMesh => _mainThreadMesh,
      };

  Stopwatch _stopwatchFor(PerformanceMetric metric) => switch (metric) {
    PerformanceMetric.wallFrame => _wallFrameStopwatch,
    PerformanceMetric.update => _updateStopwatch,
    PerformanceMetric.cpuRender => _cpuRenderStopwatch,
    PerformanceMetric.mainThreadMesh => _mainThreadMeshStopwatch,
  };
}

void _validateNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must be non-negative');
  }
}
