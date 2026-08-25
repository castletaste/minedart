/// Deterministic inactivity state for the reusable controls legend.
library;

final class ControlsHintIdleState {
  ControlsHintIdleState({this.delay = defaultDelay})
    : assert(!delay.isNegative && delay > Duration.zero);

  static const Duration defaultDelay = Duration(seconds: 6);

  final Duration delay;
  Duration _idleFor = Duration.zero;
  bool _visible = true;

  bool get visible => _visible;
  Duration get idleFor => _idleFor;

  /// Records real camera/player movement. Returns whether visibility changed.
  bool recordActivity() {
    _idleFor = Duration.zero;
    if (!_visible) return false;
    _visible = false;
    return true;
  }

  /// Advances active-gameplay inactivity. Returns whether the hint reappeared.
  bool advance(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'Must not be negative');
    }
    if (_visible || elapsed == Duration.zero) return false;
    _idleFor += elapsed;
    if (_idleFor < delay) return false;
    _visible = true;
    return true;
  }

  void reset() {
    _idleFor = Duration.zero;
    _visible = true;
  }
}
