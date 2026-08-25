import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/controller/showcase_controllers.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('BuilderStudioController', () {
    test('projects every non-air blockDef without changing IDs', () {
      final controller = BuilderStudioController();
      addTearDown(controller.dispose);

      final expectedIds = <int>[
        for (var id = 1; id < blockDefs.length; id++)
          if (blockDefs[id] != null) id,
      ];
      expect(controller.catalog.map((entry) => entry.id), expectedIds);
      expect(controller.catalog, hasLength(expectedIds.length));
      expect(
        controller.catalog
            .where((entry) => entry.id <= 21)
            .map((entry) => entry.id),
        List<int>.generate(21, (index) => index + 1),
      );
      expect(controller.catalog, isNotEmpty);
    });

    test('shows only blocks absent from the default nine-slot hotbar', () {
      final controller = BuilderStudioController();
      addTearDown(controller.dispose);

      expect(controller.hotbar, hasLength(9));
      expect(controller.hotbar.first, Blocks.tnt);
      expect(controller.hotbar, isNot(contains(Blocks.brick)));
      expect(
        controller.visibleBlocks,
        hasLength(controller.catalog.length - controller.hotbar.length),
      );
      expect(
        controller.visibleBlocks
            .map((entry) => entry.id)
            .toSet()
            .intersection(controller.hotbar.toSet()),
        isEmpty,
      );
      expect(
        controller.visibleBlocks.map((entry) => entry.id),
        contains(Blocks.brick),
      );
    });

    test('replaces the selected slot and refreshes available blocks', () {
      final controller = BuilderStudioController();
      addTearDown(controller.dispose);

      controller.selectHotbarSlot(3);
      final displaced = controller.hotbar[3];
      controller.assignBlockToHotbar(Blocks.glass, 3);

      expect(controller.hotbar[3], Blocks.glass);
      expect(controller.selectedHotbarSlot, 3);
      expect(controller.selectedBlockId, Blocks.glass);
      expect(
        controller.visibleBlocks.map((entry) => entry.id),
        isNot(contains(Blocks.glass)),
      );
      expect(
        controller.visibleBlocks.map((entry) => entry.id),
        contains(displaced),
      );
    });
  });

  group('OptionsController', () {
    test('keeps gameplay keys and makes noclip independently rebindable', () {
      final controller = OptionsController();
      addTearDown(controller.dispose);

      expect(
        controller.bindingFor(GameInputAction.openInventory),
        LogicalKeyboardKey.keyE,
      );
      expect(
        OptionsController.defaultBindings.values,
        isNot(contains(LogicalKeyboardKey.keyQ)),
      );
      expect(
        controller.bindingFor(GameInputAction.cycleFog),
        LogicalKeyboardKey.keyF,
      );
      expect(
        controller.bindingFor(GameInputAction.storeSpawn),
        LogicalKeyboardKey.enter,
      );
      expect(
        controller.bindingFor(GameInputAction.respawn),
        LogicalKeyboardKey.keyR,
      );
      expect(
        controller.bindingFor(GameInputAction.toggleNoclip),
        LogicalKeyboardKey.keyN,
      );
    });

    test('swaps conflicting bindings and updates settings', () {
      final controller = OptionsController();
      addTearDown(controller.dispose);

      controller.beginRebinding(GameInputAction.toggleNoclip);
      controller.captureKey(LogicalKeyboardKey.keyF);
      expect(
        controller.bindingFor(GameInputAction.toggleNoclip),
        LogicalKeyboardKey.keyF,
      );
      expect(
        controller.bindingFor(GameInputAction.cycleFog),
        LogicalKeyboardKey.keyN,
      );

      controller
        ..setMouseSensitivity(5)
        ..setInvertMouseY(true)
        ..setFogPreset(FogPreset.far)
        ..setMasterVolume(-1)
        ..setAudioMuted(true)
        ..setHighContrast(true)
        ..setReducedMotion(true);
      expect(controller.mouseSensitivity, 1);
      expect(controller.invertMouseY, isTrue);
      expect(controller.fogPreset, FogPreset.far);
      expect(controller.masterVolume, 0);
      expect(controller.audioMuted, isTrue);
      expect(controller.highContrast, isTrue);
      expect(controller.reducedMotion, isTrue);
    });
  });

  group('WorldLibraryController', () {
    test('filters and sorts summaries while callbacks remain external', () {
      final controller = WorldLibraryController(
        worlds: <WorldLibraryEntry>[
          WorldLibraryEntry(
            id: 'old',
            name: 'Old valley',
            seed: 10,
            updatedAt: DateTime.utc(2026),
          ),
          WorldLibraryEntry(
            id: 'new',
            name: 'New ridge',
            seed: 20,
            updatedAt: DateTime.utc(2026, 2),
          ),
        ],
      );
      addTearDown(controller.dispose);

      expect(controller.visibleWorlds.first.id, 'new');
      controller.setQuery('10');
      expect(controller.visibleWorlds.single.id, 'old');
    });

    test('tracks one operation and exposes callback failures', () async {
      final controller = WorldLibraryController();
      addTearDown(controller.dispose);
      final gate = Completer<void>();

      final operation = controller.run('world', () => gate.future);
      expect(controller.busyWorldId, 'world');
      gate.complete();
      await operation;
      expect(controller.busyWorldId, isNull);

      await controller.run('world', () async => throw StateError('broken'));
      expect(controller.errorMessage, contains('broken'));
    });
  });

  group('typed Render Lab controller', () {
    test('emits typed render settings', () {
      RenderLabSettings? emitted;
      final controller = RenderLabController(
        onChanged: (settings) => emitted = settings,
      );
      addTearDown(controller.dispose);

      controller
        ..setDebugView(RenderDebugView.normals)
        ..setRenderDistance(99)
        ..setFogDensity(-1);
      expect(emitted, same(controller.settings));
      expect(controller.settings.debugView, RenderDebugView.normals);
      expect(controller.settings.renderDistance, 16);
      expect(controller.settings.fogDensity, 0);
    });
  });
}
