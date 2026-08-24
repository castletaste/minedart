import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/controller/options_controller.dart';
import 'package:minedart/showcase/ui/pause_options.dart';

void main() {
  testWidgets(
    'settings controls and keyboard rebinding update the controller',
    (tester) async {
      _setViewport(tester, width: 800);
      final controller = OptionsController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: PauseOptionsView(
              controller: controller,
              callbacks: PauseMenuCallbacks(
                onResume: () {},
                onOpenWorldLibrary: () {},
                onOpenRenderLab: () {},
                onSaveAndQuit: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(PauseOptionsKeys.section(PauseOptionsSection.controls)),
      );
      await tester.pump();
      await tester.tap(find.byKey(PauseOptionsKeys.invertMouse));
      await tester.pump();
      expect(controller.invertMouseY, isTrue);

      final binding = find.byKey(
        PauseOptionsKeys.binding(GameInputAction.openInventory),
      );
      await tester.ensureVisible(binding);
      await tester.tap(binding);
      await tester.pump();
      expect(controller.rebindingAction, GameInputAction.openInventory);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(
        controller.bindingFor(GameInputAction.openInventory),
        LogicalKeyboardKey.keyK,
      );
      expect(controller.rebindingAction, isNull);

      await tester.tap(
        find.byKey(PauseOptionsKeys.section(PauseOptionsSection.graphics)),
      );
      await tester.pump();
      await tester.tap(find.byKey(PauseOptionsKeys.fog(FogPreset.far)));
      await tester.pump();
      expect(controller.fogPreset, FogPreset.far);

      await tester.tap(
        find.byKey(PauseOptionsKeys.section(PauseOptionsSection.audio)),
      );
      await tester.pump();
      await tester.tap(find.byKey(PauseOptionsKeys.audioMuted));
      await tester.pump();
      expect(controller.audioMuted, isTrue);

      await tester.tap(
        find.byKey(PauseOptionsKeys.section(PauseOptionsSection.accessibility)),
      );
      await tester.pump();
      await tester.tap(find.byKey(PauseOptionsKeys.highContrast));
      await tester.tap(find.byKey(PauseOptionsKeys.reducedMotion));
      await tester.pump();
      expect(controller.highContrast, isTrue);
      expect(controller.reducedMotion, isTrue);
    },
  );

  testWidgets('Escape cancels rebinding before resuming the game', (
    tester,
  ) async {
    _setViewport(tester, width: 480);
    final controller = OptionsController();
    addTearDown(controller.dispose);
    var resumes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PauseOptionsView(
            controller: controller,
            callbacks: PauseMenuCallbacks(
              onResume: () => resumes++,
              onOpenWorldLibrary: () {},
              onOpenRenderLab: () {},
              onSaveAndQuit: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(PauseOptionsKeys.compact), findsOneWidget);

    controller.beginRebinding(GameInputAction.toggleNoclip);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.rebindingAction, isNull);
    expect(resumes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(resumes, 1);
  });
}

void _setViewport(
  WidgetTester tester, {
  required double width,
  double height = 900,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
