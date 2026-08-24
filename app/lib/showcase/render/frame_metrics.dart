import 'dart:typed_data';

import '../../performance/performance_snapshot.dart';
import '../../performance/performance_snapshot_publisher.dart';
import '../../performance/performance_telemetry.dart';

/// Legacy metric names retained by the F3 graph API.
///
/// [render] is CPU render-submission time. It never represents GPU execution
/// time. New code should prefer [PerformanceMetric].
enum FrameMetric { frame, update, render, mesh }

/// Immutable percentile readout retained for F3 source compatibility.
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

/// Backward-compatible F3 facade over [PerformanceTelemetry].
///
/// Existing synchronized [record] calls and the wall-frame graph remain
/// available. New instrumentation can sample each channel independently and
/// publish one four-channel percentile snapshot at a throttled boundary.
final class FrameMetrics {
  FrameMetrics({this.capacity = 240})
    : _telemetry = PerformanceTelemetry(capacity: capacity);

  final int capacity;
  final PerformanceTelemetry _telemetry;

  PerformanceTelemetry get telemetry => _telemetry;
  int get length => _telemetry.sampleCount(PerformanceMetric.wallFrame);
  int get totalSamples => _telemetry.totalSamples(PerformanceMetric.wallFrame);
  bool get isEmpty => length == 0;
  bool get isFull => length == capacity;
  double get latestFrameTimeMs =>
      _telemetry.latestSample(PerformanceMetric.wallFrame);
  double get averageFrameTimeMs =>
      _telemetry.averageSample(PerformanceMetric.wallFrame);
  double get averageFps =>
      averageFrameTimeMs <= 0 ? 0 : 1000 / averageFrameTimeMs;

  double get p50 => percentile(0.50);
  double get p95 => percentile(0.95);
  double get p99 => percentile(0.99);

  /// Legacy synchronized sample API.
  ///
  /// [renderTimeMs] is explicitly CPU render-submission time. Independent new
  /// call sites should use the channel-specific methods below so omitted work
  /// is not represented by an artificial zero sample.
  void record({
    required double frameTimeMs,
    double updateTimeMs = 0,
    double renderTimeMs = 0,
    double meshTimeMs = 0,
  }) {
    _telemetry.recordTimings(
      wallFrameMs: frameTimeMs,
      updateMs: updateTimeMs,
      cpuRenderMs: renderTimeMs,
      mainThreadMeshMs: meshTimeMs,
    );
  }

  void recordWallFrame(double milliseconds) =>
      _telemetry.recordWallFrame(milliseconds);
  void recordUpdate(double milliseconds) =>
      _telemetry.recordUpdate(milliseconds);
  void recordCpuRender(double milliseconds) =>
      _telemetry.recordCpuRender(milliseconds);
  void recordMainThreadMesh(double milliseconds) =>
      _telemetry.recordMainThreadMesh(milliseconds);

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

  double percentile(
    double quantile, {
    FrameMetric metric = FrameMetric.frame,
  }) => _telemetry.percentile(_performanceMetric(metric), quantile);

  /// Computes p50/p95/p99 with one sort for the requested metric.
  FramePercentiles percentiles({FrameMetric metric = FrameMetric.frame}) {
    final timings = _telemetry.percentiles(_performanceMetric(metric));
    if (timings.isEmpty) return FramePercentiles.zero;
    return FramePercentiles(
      p50: timings.p50Ms,
      p95: timings.p95Ms,
      p99: timings.p99Ms,
    );
  }

  /// Computes all four metric summaries with one sort per non-empty channel.
  PerformanceSnapshot snapshot() => _telemetry.snapshot();

  PerformanceSnapshotPublisher createPublisher({
    Duration interval = PerformanceSnapshotPublisher.minimumInterval,
  }) => PerformanceSnapshotPublisher(_telemetry, interval: interval);

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
    _telemetry.updateSnapshotFields(
      drawCount: drawCount,
      meshQueue: meshQueue,
      devicePixelRatio: devicePixelRatio,
      effectiveTargetWidth: effectiveTargetWidth,
      effectiveTargetHeight: effectiveTargetHeight,
      retainedComponentCount: retainedComponentCount,
      retainedMeshBytes: retainedMeshBytes,
      uniformUploadHits: uniformUploadHits,
      uniformUploadMisses: uniformUploadMisses,
      bindGroupHits: bindGroupHits,
      bindGroupMisses: bindGroupMisses,
    );
  }

  /// Copies samples oldest-to-newest into caller-owned storage.
  int copyTo(
    Float64List destination, {
    FrameMetric metric = FrameMetric.frame,
  }) =>
      _telemetry.copySamplesTo(destination, metric: _performanceMetric(metric));

  void clear() => _telemetry.clearSamples();
}

PerformanceMetric _performanceMetric(FrameMetric metric) => switch (metric) {
  FrameMetric.frame => PerformanceMetric.wallFrame,
  FrameMetric.update => PerformanceMetric.update,
  FrameMetric.render => PerformanceMetric.cpuRender,
  FrameMetric.mesh => PerformanceMetric.mainThreadMesh,
};
