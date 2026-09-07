import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/controller/builder_studio_controller.dart';
import 'package:minedart/showcase/ui/builder_studio.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  testWidgets('is centered, compact, and overflow-free at 360 px', (
    tester,
  ) async {
    _setViewport(tester, width: 360, height: 640);
    final controller = BuilderStudioController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(BuilderStudioView(controller: controller, onClose: () {})),
    );
    await tester.pump();

    final surface = find.byKey(BuilderStudioKeys.compact);
    final rect = tester.getRect(surface);
    expect(surface, findsOneWidget);
    expect(rect.width, closeTo(336, 0.1));
    expect(rect.height, closeTo(430, 0.1));
    expect(rect.center.dx, closeTo(180, 0.1));
    expect(rect.center.dy, closeTo(320, 0.1));
    expect(find.text('Block inventory'), findsOneWidget);
    expect(find.byKey(BuilderStudioKeys.search), findsNothing);
    expect(find.byKey(BuilderStudioKeys.assign), findsNothing);
    expect(find.byKey(BuilderStudioKeys.hotbar(0)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays at 440 by 430 and centered on desktop', (tester) async {
    _setViewport(tester, width: 1280, height: 900);
    final controller = BuilderStudioController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(BuilderStudioView(controller: controller, onClose: () {})),
    );
    await tester.pump();

    final rect = tester.getRect(find.byKey(BuilderStudioKeys.expanded));
    expect(rect.size, const Size(440, 430));
    expect(rect.center, const Offset(640, 450));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows only blocks missing from the current hotbar', (
    tester,
  ) async {
    _setViewport(tester, width: 800, height: 700);
    final controller = BuilderStudioController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(BuilderStudioView(controller: controller, onClose: () {})),
    );
    await tester.pump();

    expect(find.byKey(BuilderStudioKeys.medium), findsOneWidget);
    expect(find.byKey(BuilderStudioKeys.block(Blocks.stone)), findsNothing);
    expect(find.byKey(BuilderStudioKeys.block(Blocks.tnt)), findsNothing);
    expect(find.byKey(BuilderStudioKeys.block(Blocks.brick)), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('digits choose the target and Enter replaces then closes', (
    tester,
  ) async {
    _setViewport(tester, width: 800, height: 700);
    final controller = BuilderStudioController();
    addTearDown(controller.dispose);
    var closeCount = 0;
    final chosen = controller.visibleBlocks.first;

    await tester.pumpWidget(
      _app(
        BuilderStudioView(controller: controller, onClose: () => closeCount++),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    expect(controller.selectedHotbarSlot, 4);
    expect(find.textContaining('Replace slot 5'), findsOneWidget);
    final displaced = controller.hotbar[4];

    final button = find.byKey(BuilderStudioKeys.block(chosen.id));
    await _focusWithTab(tester, button);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(closeCount, 1);
    expect(controller.hotbar[4], chosen.id);
    expect(
      controller.visibleBlocks.map((entry) => entry.id),
      isNot(contains(chosen.id)),
    );
    expect(
      controller.visibleBlocks.map((entry) => entry.id),
      contains(displaced),
    );
  });

  testWidgets('E and Escape both close the inventory', (tester) async {
    _setViewport(tester, width: 800, height: 700);
    final controller = BuilderStudioController();
    addTearDown(controller.dispose);
    var closeCount = 0;

    await tester.pumpWidget(
      _app(
        BuilderStudioView(controller: controller, onClose: () => closeCount++),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(closeCount, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closeCount, 2);
  });

  testWidgets('custom inventory binding replaces E as the close shortcut', (
    tester,
  ) async {
    _setViewport(tester, width: 800, height: 700);
    final controller = BuilderStudioController();
    addTearDown(controller.dispose);
    var closeCount = 0;

    await tester.pumpWidget(
      _app(
        BuilderStudioView(
          controller: controller,
          onClose: () => closeCount++,
          closeKey: LogicalKeyboardKey.keyK,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(closeCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(closeCount, 1);
    expect(find.textContaining('K / Esc close'), findsOneWidget);
  });

  testWidgets('block semantics expose its label and activation action', (
    tester,
  ) async {
    _setViewport(tester, width: 800, height: 700);
    final semantics = tester.ensureSemantics();
    final controller = BuilderStudioController();
    addTearDown(controller.dispose);
    final entry = controller.visibleBlocks.first;

    await tester.pumpWidget(
      _app(BuilderStudioView(controller: controller, onClose: () {})),
    );
    await tester.pump();

    final node = tester.getSemantics(
      find.byKey(BuilderStudioKeys.blockSemantics(entry.id)),
    );
    final data = node.getSemanticsData();
    expect(node.label, entry.semanticsLabel);
    expect(node.hint, contains('Replace the selected hotbar slot'));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });
}

Future<void> _focusWithTab(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) continue;
    final focused = find.byElementPredicate(
      (element) => identical(element, focusContext),
    );
    if (find.ancestor(of: focused, matching: target).evaluate().isNotEmpty) {
      return;
    }
  }
  fail(
    'Could not focus ${target.describeMatch(Plurality.one)} '
    'with keyboard traversal',
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(body: child),
);

void _setViewport(
  WidgetTester tester, {
  required double width,
  required double height,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
