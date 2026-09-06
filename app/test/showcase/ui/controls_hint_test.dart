import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:minedart/showcase/controller/options_controller.dart';
import 'package:minedart/showcase/ui/controls_hint.dart';

void main() {
  testWidgets('shows the existing N noclip control in the shared legend', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: ControlsHint())),
      ),
    );

    expect(find.text('N'), findsOneWidget);
    expect(find.text('Noclip'), findsOneWidget);
    expect(ControlsHint.semanticsSummary, contains('N noclip'));
  });

  testWidgets('follows custom bindings without changing default entries', (
    tester,
  ) async {
    final controller = OptionsController();
    addTearDown(controller.dispose);
    controller.beginRebinding(GameInputAction.openInventory);
    controller.captureKey(LogicalKeyboardKey.keyK);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ControlsHint(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('K'), findsOneWidget);
    expect(find.text('E'), findsNothing);
    expect(ControlsHint.entries[6].keys, 'E');
    expect(
      tester.getSemantics(find.byKey(ControlsHintKeys.root)).label,
      contains('K inventory'),
    );
  });
}
