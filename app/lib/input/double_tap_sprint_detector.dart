/// Deterministic forward-key double-tap state used to start a sprint.
///
/// Time enters through [forwardDown], so this class needs neither a clock nor
/// timers and can be tested without waiting in real time.
final class DoubleTapSprintDetector {
  DoubleTapSprintDetector({
    this.doubleTapWindow = const Duration(milliseconds: 300),
  }) : assert(!doubleTapWindow.isNegative);

  final Duration doubleTapWindow;

  Duration? _firstDownAt;
  bool _forwardHeld = false;
  bool _sprinting = false;

  /// True after a valid second press and only while forward remains held.
  bool get isSprinting => _sprinting && _forwardHeld;

  /// Records a forward-key press at the event's monotonic [timeStamp].
  ///
  /// Key repeats and duplicate downs cannot arm or start a sprint.
  void forwardDown(Duration timeStamp, {bool isRepeat = false}) {
    if (isRepeat || _forwardHeld) return;
    _forwardHeld = true;

    final firstDownAt = _firstDownAt;
    if (firstDownAt != null) {
      final elapsed = timeStamp - firstDownAt;
      if (!elapsed.isNegative && elapsed <= doubleTapWindow) {
        _firstDownAt = null;
        _sprinting = true;
        return;
      }
    }

    _firstDownAt = timeStamp;
    _sprinting = false;
  }

  /// Ends an active sprint. The release between the two taps keeps the first
  /// press armed; otherwise a keyboard double-tap could never complete.
  void forwardUp() {
    if (!_forwardHeld) return;
    _forwardHeld = false;
    if (_sprinting) reset();
  }

  /// Clears both an active sprint and any partially completed double-tap.
  void reset() {
    _firstDownAt = null;
    _forwardHeld = false;
    _sprinting = false;
  }
}
