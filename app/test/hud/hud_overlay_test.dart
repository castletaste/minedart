import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/hud/hotbar.dart';
import 'package:minedart/hud/hud_overlay.dart';
import 'package:minedart/hud/hud_state.dart';

void main() {
  testWidgets('routes mouse buttons and scroll without touching movement', (
    tester,
  ) async {
    final hud = HudState();
    addTearDown(hud.dispose);
    var captures = 0;
    var primary = 0;
    var secondary = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HudOverlay(
          hud: hud,
          onCapture: () => captures++,
          onPrimary: () => primary++,
          onSecondary: () => secondary++,
        ),
      ),
    );

    final center = tester.getCenter(find.byType(HudOverlay));

    final left = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await left.up();
    expect(primary, 1);
    expect(secondary, 0);
    expect(captures, 1);

    final right = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await right.up();
    expect(primary, 1);
    expect(secondary, 1);
    expect(captures, 2);

    final scroll = TestPointer(4, PointerDeviceKind.mouse);
    scroll.hover(center);
    await tester.sendEventToBinding(scroll.scroll(const Offset(0, 12)));
    await tester.pump();
    expect(hud.selectedSlot.value, 1);

    await tester.sendEventToBinding(scroll.scroll(const Offset(0, -12)));
    await tester.pump();
    expect(hud.selectedSlot.value, 0);
  });

  testWidgets('debug overlay appears only when toggled on', (tester) async {
    final hud = HudState();
    addTearDown(hud.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HudOverlay(
          hud: hud,
          onCapture: () {},
          onPrimary: () {},
          onSecondary: () {},
        ),
      ),
    );
    expect(find.textContaining('fps'), findsNothing);

    hud.toggleDebug();
    await tester.pump();
    expect(find.textContaining('fps'), findsOneWidget);
  });

  testWidgets(
    'hotbar slots are semantic, focusable, and do not trigger actions',
    (tester) async {
      final hud = HudState();
      addTearDown(hud.dispose);
      var primary = 0;
      var secondary = 0;
      var captures = 0;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HudOverlay(
            hud: hud,
            onCapture: () => captures++,
            onPrimary: () => primary++,
            onSecondary: () => secondary++,
          ),
        ),
      );

      final slot = find.byKey(HotbarKeys.slot(2));
      final node = tester.getSemantics(slot);
      expect(node.label, 'Hotbar slot 3: grass');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      final click = await tester.startGesture(
        tester.getCenter(slot),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await click.up();
      await tester.pump();

      expect(hud.selectedSlot.value, 2);
      expect(primary, 0);
      expect(secondary, 0);
      expect(captures, 0);

      await tester.tap(slot);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(hud.selectedSlot.value, 2);
      semantics.dispose();
    },
  );

  testWidgets('hotbar number backplates stay attached across viewport resize', (
    tester,
  ) async {
    final hud = HudState();
    addTearDown(hud.dispose);

    Future<void> pumpAt(Size size) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HudOverlay(
            hud: hud,
            onCapture: () {},
            onPrimary: () {},
            onSecondary: () {},
          ),
        ),
      );
      await tester.pump();
    }

    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in <Size>[
      const Size(800, 600),
      const Size(360, 420),
      const Size(1440, 900),
    ]) {
      await pumpAt(size);
      for (var index = 0; index < 9; index++) {
        final slotRect = tester.getRect(find.byKey(HotbarKeys.slot(index)));
        final numberFinder = find.byKey(HotbarKeys.number(index));
        final numberRect = tester.getRect(numberFinder);
        expect(slotRect.contains(numberRect.center), isTrue);
        expect(numberRect.center.dx, lessThan(slotRect.center.dx));
        expect(numberRect.center.dy, lessThan(slotRect.center.dy));
        expect(
          find.descendant(of: numberFinder, matching: find.byType(Text)),
          findsNothing,
        );
        expect(
          find.descendant(of: numberFinder, matching: find.byType(CustomPaint)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(HotbarKeys.slot(index)),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      }
    }
  });
}
