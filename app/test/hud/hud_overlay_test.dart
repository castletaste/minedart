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

  for (final touchControls in [false, true]) {
    for (final overSlot in [false, true]) {
      for (final trackpad in [false, true]) {
        testWidgets(
          '${trackpad ? 'trackpad' : 'wheel'} cycles slots over '
          '${overSlot ? 'hotbar' : 'game surface'} with touch=$touchControls',
          (tester) async {
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
                  touchControls: touchControls ? const SizedBox.shrink() : null,
                ),
              ),
            );
            final position = tester.getCenter(
              overSlot
                  ? find.byKey(HotbarKeys.slot(2))
                  : find.byType(HudOverlay),
            );
            if (trackpad) {
              final gesture = await tester.createGesture(
                kind: PointerDeviceKind.trackpad,
              );
              await gesture.panZoomStart(position);
              await gesture.panZoomUpdate(position, pan: const Offset(0, 48));
              await tester.pump();
              expect(hud.selectedSlot.value, 1);
              await gesture.panZoomUpdate(position, pan: Offset.zero);
              await gesture.panZoomEnd();
            } else {
              final pointer = TestPointer(4, PointerDeviceKind.mouse);
              pointer.hover(position);
              await tester.sendEventToBinding(
                pointer.scroll(const Offset(0, 12)),
              );
              await tester.pump();
              expect(hud.selectedSlot.value, 1);
              await tester.sendEventToBinding(
                pointer.scroll(const Offset(0, -12)),
              );
            }
            await tester.pump();
            expect(hud.selectedSlot.value, 0);
            expect(captures, 0);
            expect(primary, 0);
            expect(secondary, 0);
          },
        );
      }
    }
  }

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.trackpad]) {
    testWidgets(
      'horizontal $kind scrolls mobile hotbar without cycling slots',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 640);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final hud = HudState();
        addTearDown(hud.dispose);
        var gameActions = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: HudOverlay(
              hud: hud,
              onCapture: () => gameActions++,
              onPrimary: () => gameActions++,
              onSecondary: () => gameActions++,
              touchControls: const SizedBox.shrink(),
            ),
          ),
        );
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable),
        );
        final position = tester.getCenter(find.byKey(HotbarKeys.slot(2)));
        final gesture = await tester.startGesture(position, kind: kind);
        await gesture.moveBy(const Offset(-80, 0));
        await gesture.moveBy(const Offset(-40, 0));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
        expect(hud.selectedSlot.value, 0);
        expect(gameActions, 0);
      },
    );
  }

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
      expect(node.label, 'Hotbar slot 3: dirt');
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
