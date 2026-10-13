import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/controller/options_controller.dart';
import 'package:minedart/showcase/ui/pause_options.dart';

void main() {
  testWidgets('pause surface golden', (tester) async {
    final options = OptionsController();
    addTearDown(options.dispose);
    await tester.pumpWidget(
      _surface(
        PauseOptionsView(
          controller: options,
          callbacks: PauseMenuCallbacks(
            onResume: () {},
            onOpenWorldLibrary: () {},
            onOpenRenderLab: () {},
            onSaveAndQuit: () {},
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(PauseOptionsView),
      matchesGoldenFile('goldens/pause_options.png'),
    );
  });

}

Widget _surface(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: ColoredBox(
    color: const Color(0xFF101418),
    child: SizedBox(width: 900, height: 700, child: child),
  ),
);
