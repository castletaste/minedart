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
    var primary = 0;
    var secondary = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HudOverlay(
          hud: hud,
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

    final right = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await right.up();
    expect(primary, 1);
    expect(secondary, 1);

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
        child: HudOverlay(hud: hud, onPrimary: () {}, onSecondary: () {}),
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
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HudOverlay(
            hud: hud,
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

      await tester.tap(slot);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(hud.selectedSlot.value, 2);
      semantics.dispose();
    },
  );
}
