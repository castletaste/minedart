import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/integration/controls_hint_idle.dart';

void main() {
  testWidgets('only the last activity starts the six-second idle window', (
    tester,
  ) async {
    final start = tester.binding.clock.now();
    var changes = 0;
    final hint = ControlsHintIdleController(
      elapsed: () => tester.binding.clock.now().difference(start),
      onChanged: () => changes++,
    );
    addTearDown(hint.dispose);
    expect(hint.visible, isTrue);
    hint.recordActivity();
    await tester.pump(const Duration(seconds: 5));
    hint.recordActivity();
    await tester.pump(const Duration(seconds: 5));
    expect(hint.visible, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(hint.visible, isTrue);
    expect(changes, 2);
  });

  testWidgets('modal and background time preserve the remaining idle window', (
    tester,
  ) async {
    final start = tester.binding.clock.now();
    final hint = ControlsHintIdleController(
      elapsed: () => tester.binding.clock.now().difference(start),
      onChanged: () {},
    );
    addTearDown(hint.dispose);
    hint.recordActivity();
    await tester.pump(const Duration(seconds: 2));
    hint.setActive(false);
    await tester.pump(const Duration(minutes: 2));
    expect(hint.visible, isFalse);
    hint.setActive(true);
    await tester.pump(const Duration(seconds: 3));
    expect(hint.visible, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(hint.visible, isTrue);
  });

  testWidgets(
    'activity while paused resets idle time; reset/dispose cancel work',
    (tester) async {
      final start = tester.binding.clock.now();
      var changes = 0;
      final hint = ControlsHintIdleController(
        elapsed: () => tester.binding.clock.now().difference(start),
        onChanged: () => changes++,
      );
      hint.recordActivity();
      await tester.pump(const Duration(seconds: 4));
      hint.setActive(false);
      hint.recordActivity();
      hint.setActive(true);
      await tester.pump(const Duration(seconds: 5));
      expect(hint.visible, isFalse);
      hint.reset();
      expect(hint.visible, isTrue);
      hint.recordActivity();
      hint.dispose();
      final before = changes;
      await tester.pump(const Duration(seconds: 10));
      hint.recordActivity();
      hint.setActive(true);
      expect(changes, before);
    },
  );
}
