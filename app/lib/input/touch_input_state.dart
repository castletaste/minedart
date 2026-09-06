/// Input sampled by the game loop from the Flutter touch controls.
///
/// Movement and held buttons persist until the controls update them. Look and
/// block actions are frame events and are cleared by [consumeFrame]. A jump
/// edge persists until physics acknowledges a simulation step, so a short tap
/// cannot disappear during a render frame that advances zero fixed steps.
final class TouchInputState {
  bool _enabled = false;
  double _forward = 0;
  double _strafe = 0;
  bool _jumpHeld = false;
  bool _jumpRequested = false;
  bool _sprintHeld = false;
  double _lookDx = 0;
  double _lookDy = 0;
  int _breakRequests = 0;
  int _placeRequests = 0;

  bool get enabled => _enabled;
  bool get sprintHeld => _enabled && _sprintHeld;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) reset();
  }

  void setMovement({required double forward, required double strafe}) {
    if (!_enabled) return;
    _forward = forward.clamp(-1.0, 1.0);
    _strafe = strafe.clamp(-1.0, 1.0);
  }

  void setJumpHeld(bool held) {
    if (!_enabled) return;
    if (held && !_jumpHeld) _jumpRequested = true;
    _jumpHeld = held;
  }

  /// Queues one jump frame for controls that expose activation, not holding.
  void requestJump() {
    if (_enabled) _jumpRequested = true;
  }

  void setSprintHeld(bool held) {
    if (_enabled) _sprintHeld = held;
  }

  void addLookDelta(double dx, double dy) {
    if (!_enabled) return;
    _lookDx += dx;
    _lookDy += dy;
  }

  void requestBreak() {
    if (_enabled) _breakRequests++;
  }

  void requestPlace() {
    if (_enabled) _placeRequests++;
  }

  void acknowledgeJumpRequest() {
    _jumpRequested = false;
  }

  TouchInputFrame consumeFrame() {
    if (!_enabled) return TouchInputFrame.zero;
    final frame = TouchInputFrame(
      forward: _forward,
      strafe: _strafe,
      jumpHeld: _jumpHeld,
      jumpRequested: _jumpRequested,
      sprintHeld: _sprintHeld,
      lookDx: _lookDx,
      lookDy: _lookDy,
      breakRequests: _breakRequests,
      placeRequests: _placeRequests,
    );
    _lookDx = 0;
    _lookDy = 0;
    _breakRequests = 0;
    _placeRequests = 0;
    return frame;
  }

  /// Clears held and queued input while retaining the selected control mode.
  void reset() {
    _forward = 0;
    _strafe = 0;
    _jumpHeld = false;
    _jumpRequested = false;
    _sprintHeld = false;
    _lookDx = 0;
    _lookDy = 0;
    _breakRequests = 0;
    _placeRequests = 0;
  }
}

final class TouchInputFrame {
  const TouchInputFrame({
    required this.forward,
    required this.strafe,
    required this.jumpHeld,
    required this.jumpRequested,
    required this.sprintHeld,
    required this.lookDx,
    required this.lookDy,
    required this.breakRequests,
    required this.placeRequests,
  });

  static const zero = TouchInputFrame(
    forward: 0,
    strafe: 0,
    jumpHeld: false,
    jumpRequested: false,
    sprintHeld: false,
    lookDx: 0,
    lookDy: 0,
    breakRequests: 0,
    placeRequests: 0,
  );

  final double forward;
  final double strafe;
  final bool jumpHeld;
  final bool jumpRequested;
  final bool sprintHeld;
  final double lookDx;
  final double lookDy;
  final int breakRequests;
  final int placeRequests;

  bool get hasImmediateInput =>
      forward != 0 ||
      strafe != 0 ||
      jumpHeld ||
      jumpRequested ||
      lookDx != 0 ||
      lookDy != 0 ||
      breakRequests != 0 ||
      placeRequests != 0;
}
