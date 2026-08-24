final class SampleStats {
  SampleStats(List<int> ticks, this.frequency)
    : samples = List<int>.of(ticks)..sort(),
      assert(ticks.isNotEmpty);

  final List<int> samples;
  final int frequency;

  double get medianMs {
    final middle = samples.length ~/ 2;
    final ticks = samples.length.isOdd
        ? samples[middle].toDouble()
        : (samples[middle - 1] + samples[middle]) / 2;
    return ticks * 1000 / frequency;
  }

  double get p99Ms =>
      samples[((samples.length * 0.99).ceil() - 1).clamp(
        0,
        samples.length - 1,
      )] *
      1000 /
      frequency;

  Map<String, Object> toJson() => {
    'median_ms': double.parse(medianMs.toStringAsFixed(6)),
    'p99_ms': double.parse(p99Ms.toStringAsFixed(6)),
  };
}

int measureTicks(Object? Function() operation) {
  final stopwatch = Stopwatch()..start();
  final value = operation();
  final ticks = stopwatch.elapsedTicks;
  if (value.hashCode == -1) throw StateError('unreachable');
  return ticks;
}
