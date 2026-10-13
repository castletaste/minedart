import 'dart:async';

/// One idle deadline, paused while gameplay is unavailable.
///
/// Activity moves the deadline without allocating a timer per movement frame.
/// A pending timer wakes at its old deadline and re-arms for the remainder.
final class ControlsHintIdleController {
  ControlsHintIdleController({
    required this.onChanged,
    this.delay = const Duration(seconds: 6),
    Duration Function()? elapsed,
  }) : assert(delay > Duration.zero),
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedDuration;

  final void Function() onChanged;
  final Duration delay;
  final Duration Function() _elapsed;
  Timer? _timer;
  Duration? _deadline;
  Duration? _remaining;
  bool _active = true;
  bool _visible = true;
  bool _disposed = false;

  bool get visible => _visible;

  void recordActivity() {
    if (_disposed) return;
    _remaining = delay;
    if (_active) {
      _deadline = _elapsed() + delay;
      _arm();
    }
    if (!_visible) return;
    _visible = false;
    onChanged();
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    if (!active) {
      if (_deadline case final deadline?) {
        final remaining = deadline - _elapsed();
        _remaining = remaining > Duration.zero ? remaining : Duration.zero;
      }
      _deadline = null;
      _timer?.cancel();
      _timer = null;
    } else if (!_visible) {
      _deadline = _elapsed() + (_remaining ?? delay);
      _arm();
    }
  }

  void reset() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _deadline = _remaining = null;
    if (_visible) return;
    _visible = true;
    onChanged();
  }

  void _arm() {
    _timer ??= Timer(_deadline! - _elapsed(), _expire);
  }

  void _expire() {
    _timer = null;
    if (_disposed || !_active) return;
    if (_deadline! > _elapsed()) {
      _arm();
      return;
    }
    _deadline = _remaining = null;
    _visible = true;
    onChanged();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}
