import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/integration/controls_hint_idle.dart';

void main() {
  test('movement hides the initial hint and six idle seconds restore it', () {
    final state = ControlsHintIdleState();
    expect(state.visible, isTrue);

    expect(state.recordActivity(), isTrue);
    expect(state.visible, isFalse);
    expect(state.advance(const Duration(milliseconds: 5999)), isFalse);
    expect(state.visible, isFalse);
    expect(state.advance(const Duration(milliseconds: 1)), isTrue);
    expect(state.visible, isTrue);
  });

  test('continued movement restarts the complete inactivity window', () {
    final state = ControlsHintIdleState()..recordActivity();

    state.advance(const Duration(seconds: 5));
    expect(state.recordActivity(), isFalse);
    expect(state.idleFor, Duration.zero);
    expect(state.advance(const Duration(seconds: 5)), isFalse);
    expect(state.advance(const Duration(seconds: 1)), isTrue);
  });

  test('reset restores startup state and negative time is rejected', () {
    final state = ControlsHintIdleState()
      ..recordActivity()
      ..advance(const Duration(seconds: 2))
      ..reset();

    expect(state.visible, isTrue);
    expect(state.idleFor, Duration.zero);
    expect(
      () => state.advance(const Duration(microseconds: -1)),
      throwsArgumentError,
    );
  });
}
