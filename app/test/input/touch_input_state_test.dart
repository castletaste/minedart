import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/touch_input_state.dart';

void main() {
  test('disabled state ignores every input source', () {
    final state = TouchInputState();

    state
      ..setMovement(forward: 1, strafe: -1)
      ..setJumpHeld(true)
      ..requestJump()
      ..setSprintHeld(true)
      ..addLookDelta(4, -3)
      ..requestBreak()
      ..requestPlace();

    expect(state.consumeFrame(), same(TouchInputFrame.zero));
  });

  test(
    'held controls persist while frame events are consumed exactly once',
    () {
      final state = TouchInputState()
        ..setEnabled(true)
        ..setMovement(forward: 2, strafe: -2)
        ..setJumpHeld(true)
        ..setSprintHeld(true)
        ..addLookDelta(4, -3)
        ..addLookDelta(2, 1)
        ..requestBreak()
        ..requestBreak()
        ..requestPlace();

      final first = state.consumeFrame();
      expect(first.forward, 1);
      expect(first.strafe, -1);
      expect(first.jumpHeld, isTrue);
      expect(first.jumpRequested, isTrue);
      expect(first.sprintHeld, isTrue);
      expect(first.lookDx, 6);
      expect(first.lookDy, -2);
      expect(first.breakRequests, 2);
      expect(first.placeRequests, 1);

      state.acknowledgeJumpRequest();
      final second = state.consumeFrame();
      expect(second.forward, 1);
      expect(second.strafe, -1);
      expect(second.jumpHeld, isTrue);
      expect(second.jumpRequested, isFalse);
      expect(second.sprintHeld, isTrue);
      expect(second.lookDx, 0);
      expect(second.lookDy, 0);
      expect(second.breakRequests, 0);
      expect(second.placeRequests, 0);
    },
  );

  test('quick jump press survives frames without a physics step', () {
    final state = TouchInputState()
      ..setEnabled(true)
      ..setJumpHeld(true)
      ..setJumpHeld(false);

    final first = state.consumeFrame();
    expect(first.jumpHeld, isFalse);
    expect(first.jumpRequested, isTrue);

    final second = state.consumeFrame();
    expect(second.jumpHeld, isFalse);
    expect(second.jumpRequested, isTrue);

    state.acknowledgeJumpRequest();
    expect(state.consumeFrame().jumpRequested, isFalse);

    state.requestJump();
    expect(state.consumeFrame().jumpRequested, isTrue);
  });

  test('reset clears held and queued input but retains the control mode', () {
    final state = TouchInputState()
      ..setEnabled(true)
      ..setMovement(forward: 1, strafe: 0.5)
      ..setJumpHeld(true)
      ..setSprintHeld(true)
      ..addLookDelta(2, 3)
      ..requestBreak()
      ..reset();

    expect(state.enabled, isTrue);
    expect(state.sprintHeld, isFalse);
    expect(state.consumeFrame(), _isZeroFrame);

    state
      ..setMovement(forward: 1, strafe: 0)
      ..setEnabled(false)
      ..setEnabled(true);
    expect(state.consumeFrame(), _isZeroFrame);
  });
}

final _isZeroFrame = isA<TouchInputFrame>()
    .having((frame) => frame.forward, 'forward', 0)
    .having((frame) => frame.strafe, 'strafe', 0)
    .having((frame) => frame.jumpHeld, 'jump', isFalse)
    .having((frame) => frame.jumpRequested, 'jump request', isFalse)
    .having((frame) => frame.sprintHeld, 'sprint', isFalse)
    .having((frame) => frame.lookDx, 'look dx', 0)
    .having((frame) => frame.lookDy, 'look dy', 0)
    .having((frame) => frame.breakRequests, 'break requests', 0)
    .having((frame) => frame.placeRequests, 'place requests', 0);
