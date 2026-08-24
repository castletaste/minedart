import 'package:flutter/foundation.dart';

/// Immutable nearest-rank timing summary in milliseconds.
@immutable
final class TimingPercentiles {
  const TimingPercentiles({
    required this.sampleCount,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
  });

  static const TimingPercentiles empty = TimingPercentiles(
    sampleCount: 0,
    p50Ms: 0,
    p95Ms: 0,
    p99Ms: 0,
  );

  final int sampleCount;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;

  bool get isEmpty => sampleCount == 0;

  @override
  bool operator ==(Object other) =>
      other is TimingPercentiles &&
      other.sampleCount == sampleCount &&
      other.p50Ms == p50Ms &&
      other.p95Ms == p95Ms &&
      other.p99Ms == p99Ms;

  @override
  int get hashCode => Object.hash(sampleCount, p50Ms, p95Ms, p99Ms);
}

/// Web bind-cache counters for the most recently observed rendered frame.
///
/// These are CPU-side cache counters. They do not represent GPU execution
/// time.
@immutable
final class WebCacheCountersSnapshot {
  const WebCacheCountersSnapshot({
    required this.uniformUploadHits,
    required this.uniformUploadMisses,
    required this.bindGroupHits,
    required this.bindGroupMisses,
  });

  static const WebCacheCountersSnapshot empty = WebCacheCountersSnapshot(
    uniformUploadHits: 0,
    uniformUploadMisses: 0,
    bindGroupHits: 0,
    bindGroupMisses: 0,
  );

  final int uniformUploadHits;
  final int uniformUploadMisses;
  final int bindGroupHits;
  final int bindGroupMisses;

  @override
  bool operator ==(Object other) =>
      other is WebCacheCountersSnapshot &&
      other.uniformUploadHits == uniformUploadHits &&
      other.uniformUploadMisses == uniformUploadMisses &&
      other.bindGroupHits == bindGroupHits &&
      other.bindGroupMisses == bindGroupMisses;

  @override
  int get hashCode => Object.hash(
    uniformUploadHits,
    uniformUploadMisses,
    bindGroupHits,
    bindGroupMisses,
  );
}

/// Immutable HUD/benchmark snapshot of the short performance window.
///
/// [cpuRender] measures CPU work spent submitting render commands. No field in
/// this model claims GPU execution time. Target dimensions are effective 3D
/// render-target pixels and are always captured together with
/// [devicePixelRatio].
@immutable
final class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.wallFrame,
    required this.update,
    required this.cpuRender,
    required this.mainThreadMesh,
    required this.drawCount,
    required this.meshQueue,
    required this.devicePixelRatio,
    required this.effectiveTargetWidth,
    required this.effectiveTargetHeight,
    required this.retainedComponentCount,
    required this.retainedMeshBytes,
    required this.webCache,
  });

  static const PerformanceSnapshot empty = PerformanceSnapshot(
    wallFrame: TimingPercentiles.empty,
    update: TimingPercentiles.empty,
    cpuRender: TimingPercentiles.empty,
    mainThreadMesh: TimingPercentiles.empty,
    drawCount: 0,
    meshQueue: 0,
    devicePixelRatio: 0,
    effectiveTargetWidth: 0,
    effectiveTargetHeight: 0,
    retainedComponentCount: 0,
    retainedMeshBytes: 0,
    webCache: WebCacheCountersSnapshot.empty,
  );

  final TimingPercentiles wallFrame;
  final TimingPercentiles update;

  /// CPU render submission time, not GPU execution time.
  final TimingPercentiles cpuRender;

  /// Main-thread CPU time spent draining completed mesh work.
  final TimingPercentiles mainThreadMesh;

  /// Actual draws reported by the live render context after rendering.
  final int drawCount;
  final int meshQueue;
  final double devicePixelRatio;
  final int effectiveTargetWidth;
  final int effectiveTargetHeight;
  final int retainedComponentCount;
  final int retainedMeshBytes;
  final WebCacheCountersSnapshot webCache;

  @override
  bool operator ==(Object other) =>
      other is PerformanceSnapshot &&
      other.wallFrame == wallFrame &&
      other.update == update &&
      other.cpuRender == cpuRender &&
      other.mainThreadMesh == mainThreadMesh &&
      other.drawCount == drawCount &&
      other.meshQueue == meshQueue &&
      other.devicePixelRatio == devicePixelRatio &&
      other.effectiveTargetWidth == effectiveTargetWidth &&
      other.effectiveTargetHeight == effectiveTargetHeight &&
      other.retainedComponentCount == retainedComponentCount &&
      other.retainedMeshBytes == retainedMeshBytes &&
      other.webCache == webCache;

  @override
  int get hashCode => Object.hash(
    wallFrame,
    update,
    cpuRender,
    mainThreadMesh,
    drawCount,
    meshQueue,
    devicePixelRatio,
    effectiveTargetWidth,
    effectiveTargetHeight,
    retainedComponentCount,
    retainedMeshBytes,
    webCache,
  );
}
