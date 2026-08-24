import 'performance_snapshot.dart';
import 'performance_telemetry.dart';

/// Produces immutable telemetry snapshots at no more than four Hertz.
///
/// Callers pass microseconds from one monotonic, retained [Stopwatch]. Calls
/// before the boundary return `null` without computing percentiles.
final class PerformanceSnapshotPublisher {
  PerformanceSnapshotPublisher(
    this._telemetry, {
    this.interval = minimumInterval,
  }) : _intervalMicroseconds = interval.inMicroseconds {
    if (interval < minimumInterval) {
      throw ArgumentError.value(
        interval,
        'interval',
        'must be at least $minimumInterval',
      );
    }
  }

  static const int maximumRateHz = 4;
  static const Duration minimumInterval = Duration(milliseconds: 250);

  final PerformanceTelemetry _telemetry;
  final Duration interval;
  final int _intervalMicroseconds;

  int? _lastObservedMicroseconds;
  int? _lastPublishedMicroseconds;
  int _publicationCount = 0;
  PerformanceSnapshot? _latest;

  int get publicationCount => _publicationCount;
  PerformanceSnapshot? get latest => _latest;

  PerformanceSnapshot? publishIfDue({required int elapsedMicroseconds}) {
    if (elapsedMicroseconds < 0) {
      throw ArgumentError.value(
        elapsedMicroseconds,
        'elapsedMicroseconds',
        'must be non-negative',
      );
    }
    final lastObserved = _lastObservedMicroseconds;
    if (lastObserved != null && elapsedMicroseconds < lastObserved) {
      throw ArgumentError.value(
        elapsedMicroseconds,
        'elapsedMicroseconds',
        'must be monotonic',
      );
    }
    _lastObservedMicroseconds = elapsedMicroseconds;

    final last = _lastPublishedMicroseconds;
    if (last != null) {
      if (elapsedMicroseconds - last < _intervalMicroseconds) return null;
    }

    final next = _telemetry.snapshot();
    _lastPublishedMicroseconds = elapsedMicroseconds;
    _publicationCount++;
    _latest = next;
    return next;
  }

  void reset() {
    _lastObservedMicroseconds = null;
    _lastPublishedMicroseconds = null;
    _publicationCount = 0;
    _latest = null;
  }
}
