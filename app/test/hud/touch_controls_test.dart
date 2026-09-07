import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/hud/hotbar.dart';
import 'package:minedart/hud/hud_overlay.dart';
import 'package:minedart/hud/hud_state.dart';
import 'package:minedart/hud/touch_controls.dart';

void main() {
  testWidgets('move, look, jump and edit coexist without mouse capture', (
    tester,
  ) async {
    final input = _Input();
    await _pump(tester, input);
    final stick = await tester.startGesture(
      tester.getCenter(find.byKey(TouchControlsKeys.joystick)),
      pointer: 1,
    );
    await stick.moveBy(const Offset(0, -42));
    expect(input.movement.dy, -1);
    expect(input.sprint, isTrue);

    final look = await tester.startGesture(const Offset(210, 270), pointer: 2);
    await look.moveBy(const Offset(24, -12));
    expect(input.look, const Offset(24, -12));
    final jump = await tester.startGesture(
      tester.getCenter(find.byKey(TouchControlsKeys.jump)),
      pointer: 3,
    );
    expect(input.jump, isTrue);
    await tester.tap(find.byKey(TouchControlsKeys.breakBlock), pointer: 4);
    await tester.tap(find.byKey(TouchControlsKeys.placeBlock), pointer: 5);
    expect(input.breaks, 1);
    expect(input.places, 1);
    expect(input.captures, 0);
    expect(input.jump, isTrue);

    await stick.cancel();
    expect(input.movement, Offset.zero);
    expect(input.sprint, isFalse);
    await look.moveBy(const Offset(10, 2));
    expect(input.look, const Offset(34, -10));
    await jump.cancel();
    expect(input.jump, isFalse);
    await look.up();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background and menu transitions discard old held gestures', (
    tester,
  ) async {
    final input = _Input();
    await _pump(tester, input);
    final stick = await tester.startGesture(
      tester.getCenter(find.byKey(TouchControlsKeys.joystick)),
      pointer: 1,
    );
    await stick.moveBy(const Offset(20, -30));
    final look = await tester.startGesture(const Offset(210, 270), pointer: 2);
    final jump = await tester.startGesture(
      tester.getCenter(find.byKey(TouchControlsKeys.jump)),
      pointer: 3,
    );
    expect(input.jump, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(input.movement, Offset.zero);
    expect(input.jump, isFalse);
    await stick.moveBy(const Offset(10, 0));
    await look.moveBy(const Offset(10, 0));
    expect(input.movement, Offset.zero);
    expect(input.look, Offset.zero);
    await stick.up();
    await look.up();
    await jump.up();

    final held = await tester.startGesture(
      tester.getCenter(find.byKey(TouchControlsKeys.joystick)),
      pointer: 4,
    );
    await held.moveBy(const Offset(20, 0));
    await tester.tap(find.byKey(TouchControlsKeys.inventory), pointer: 5);
    await tester.pump();
    expect(input.inventories, 1);
    expect(input.movement, Offset.zero);
    await held.moveBy(const Offset(20, 0));
    expect(input.movement, Offset.zero);
    await held.up();
    await tester.tap(find.byKey(TouchControlsKeys.pause));
    expect(input.pauses, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'desktop surface still receives mouse, buttons and hotbar do not',
    (tester) async {
      final input = _Input();
      await _pump(tester, input);
      final mouse = await tester.startGesture(
        const Offset(210, 270),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();
      expect(input.captures, 1);
      expect(input.mouseBreaks, 1);
      final button = await tester.startGesture(
        tester.getCenter(find.byKey(TouchControlsKeys.pause)),
        kind: PointerDeviceKind.mouse,
      );
      await button.up();
      await tester.pump();
      expect(input.pauses, 1);
      final slot = await tester.startGesture(
        tester.getCenter(find.byKey(HotbarKeys.slot(1))),
        kind: PointerDeviceKind.mouse,
      );
      await slot.up();
      expect(input.captures, 1);
      expect(input.mouseBreaks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(640, 360),
  ]) {
    testWidgets('touch targets stay usable with safe insets at $size', (
      tester,
    ) async {
      final input = _Input();
      await _pump(
        tester,
        input,
        size: size,
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
      );
      expect(tester.takeException(), isNull);
      final safeRect = Rect.fromLTRB(20, 30, size.width - 20, size.height - 24);
      for (final key in [
        TouchControlsKeys.joystick,
        TouchControlsKeys.jump,
        TouchControlsKeys.breakBlock,
        TouchControlsKeys.placeBlock,
        TouchControlsKeys.pause,
        TouchControlsKeys.inventory,
      ]) {
        final rect = tester.getRect(find.byKey(key));
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.intersect(safeRect), rect, reason: key.toString());
      }
      final first = tester.getRect(find.byKey(HotbarKeys.slot(0)));
      expect(first.width, 48);
      final scroll = find.descendant(
        of: find.byType(Hotbar),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(scroll, const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HotbarKeys.slot(8)));
      await tester.pump();
      expect(
        tester.widget<Hotbar>(find.byType(Hotbar)).hud.selectedSlot.value,
        8,
      );
      expect(input.captures, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Input input, {
  Size size = const Size(360, 640),
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final hud = HudState();
  addTearDown(hud.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, padding: padding),
        child: HudOverlay(
          hud: hud,
          onCapture: () => input.captures++,
          onPrimary: () => input.mouseBreaks++,
          onSecondary: () {},
          touchControls: TouchControls(
            onMovement: (value) => input.movement = value,
            onLook: (value) => input.look += value,
            onJump: (value) => input.jump = value,
            onJumpPressed: () => input.jump = true,
            onSprint: (value) => input.sprint = value,
            onBreak: () => input.breaks++,
            onPlace: () => input.places++,
            onPause: () => input.pauses++,
            onInventory: () => input.inventories++,
            onReset: input.reset,
          ),
        ),
      ),
    ),
  );
}

final class _Input {
  Offset movement = Offset.zero;
  Offset look = Offset.zero;
  bool jump = false;
  bool sprint = false;
  int breaks = 0;
  int places = 0;
  int captures = 0;
  int mouseBreaks = 0;
  int pauses = 0;
  int inventories = 0;
  void reset() {
    movement = Offset.zero;
    look = Offset.zero;
    jump = false;
    sprint = false;
  }
}
