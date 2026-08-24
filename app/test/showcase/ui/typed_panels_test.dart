import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/controller/render_lab_controller.dart';
import 'package:minedart/showcase/ui/render_lab.dart';

void main() {
  testWidgets('Render Lab panel writes typed controller settings', (
    tester,
  ) async {
    RenderLabSettings? emitted;
    final controller = RenderLabController(
      onChanged: (settings) => emitted = settings,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(RenderLabPanel(controller: controller)));
    final outline = find.byKey(RenderLabKeys.targetOutline);
    await tester.ensureVisible(outline);
    await tester.tap(outline);
    await tester.pump();

    expect(controller.settings.targetOutline, isFalse);
    expect(emitted, same(controller.settings));
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(body: child),
);
