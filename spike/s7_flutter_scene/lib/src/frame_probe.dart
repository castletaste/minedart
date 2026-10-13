import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Fixed-capacity sample ring with nearest-rank percentiles, matching the
/// minedart telemetry method so A/B numbers are comparable.
final class SampleRing {
  SampleRing(this.capacity) : _values = Float64List(capacity);

  final int capacity;
  final Float64List _values;
  int _count = 0;
  int _next = 0;

  void add(double value) {
    _values[_next] = value;
    _next = (_next + 1) % capacity;
    if (_count < capacity) _count++;
  }

  void clear() {
    _count = 0;
    _next = 0;
  }

  int get length => _count;

  List<double> percentiles(List<double> ranks) {
    if (_count == 0) return [for (final _ in ranks) 0];
    final sorted = Float64List.sublistView(_values, 0, _count).toList()..sort();
    return [
      for (final rank in ranks)
        sorted[((rank * _count).ceil() - 1).clamp(0, _count - 1)],
    ];
  }
}

/// Collects per-frame timings and prints one JSON line every [intervalMs] of
/// wall time (SwiftShader frames are slow, so a frame-count window starves).
///
/// Lines start with `S7 ` so the Playwright probe can pick them out of the
/// browser console.
final class FrameProbe {
  FrameProbe({this.intervalMs = 3000});

  final double intervalMs;
  final SampleRing wall = SampleRing(7200);
  final SampleRing cpuRender = SampleRing(7200);
  final SampleRing update = SampleRing(7200);
  int draws = 0;
  int culled = 0;
  int submitted = 0;
  int paced = 0;
  int _frames = 0;
  double _sinceReportMs = 0;

  void record({
    required double wallMs,
    required double cpuRenderMs,
    required double updateMs,
  }) {
    wall.add(wallMs);
    cpuRender.add(cpuRenderMs);
    update.add(updateMs);
    _frames++;
    _sinceReportMs += wallMs;
    if (_sinceReportMs >= intervalMs) {
      _sinceReportMs = 0;
      report('frames');
    }
  }

  void report(String kind, [Map<String, Object?> extra = const {}]) {
    String fmt(SampleRing ring) => ring
        .percentiles(const [0.5, 0.95, 0.99])
        .map((v) => v.toStringAsFixed(2))
        .join('/');
    debugPrint(
      'S7 ${jsonEncode({'kind': kind, 'frames': _frames, 'samples': wall.length, 'wall': fmt(wall), 'cpuRender': fmt(cpuRender), 'update': fmt(update), 'draws': draws, 'culled': culled, 'submitted': submitted, 'paced': paced, ...extra})}',
    );
  }
}

/// Logs a one-off measurement line.
void logEvent(String kind, Map<String, Object?> data) {
  debugPrint('S7 ${jsonEncode({'kind': kind, ...data})}');
}
