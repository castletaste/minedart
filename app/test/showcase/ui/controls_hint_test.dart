import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
