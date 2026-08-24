import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/hud/block_palette.dart';
import 'package:minedart/hud/debug_overlay.dart';
import 'package:minedart/hud/hud_state.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  group('hotbar selection', () {
    test('starts on the first slot', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      expect(hud.selectedSlot.value, 0);
      expect(hud.selectedBlock, Blocks.stone);
      expect(hud.slotCount, 9);
    });

    test('selectSlot ignores out-of-range values', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      hud.selectSlot(4);
      expect(hud.selectedSlot.value, 4);
      hud.selectSlot(9);
      hud.selectSlot(-1);
      expect(hud.selectedSlot.value, 4);
    });

    test('cycleSlot wraps in both directions', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      hud.cycleSlot(-1);
      expect(hud.selectedSlot.value, 8);
      hud.cycleSlot(1);
      expect(hud.selectedSlot.value, 0);
      hud.cycleSlot(11);
      expect(hud.selectedSlot.value, 2);
      hud.cycleSlot(0);
      expect(hud.selectedSlot.value, 2);
    });

    test('scroll down advances, scroll up goes back', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      hud.handleScroll(12);
      expect(hud.selectedSlot.value, 1);
      hud.handleScroll(-12);
      expect(hud.selectedSlot.value, 0);
      hud.handleScroll(0);
      expect(hud.selectedSlot.value, 0);
    });

    test('every hotbar slot maps to a real placeable block', () {
      expect(kHotbarBlocks, hasLength(9));
      expect(kHotbarBlocks.last, Blocks.tnt);
      expect(kHotbarBlocks, isNot(contains(Blocks.brick)));
      for (final blockId in kHotbarBlocks) {
        expect(blockId, greaterThan(Blocks.air));
        expect(blockDefs[blockId], isNotNull);
        expect(kBlockColors.containsKey(blockId), isTrue);
      }
    });
  });

  group('debug overlay state', () {
    test('toggles visibility', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      expect(hud.debugVisible.value, isFalse);
      hud.toggleDebug();
      expect(hud.debugVisible.value, isTrue);
      hud.toggleDebug();
      expect(hud.debugVisible.value, isFalse);
    });

    test('does not publish stats while hidden', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      hud.recordFrame(1 / 60, 1, 2, 3);
      expect(hud.debugStats.value, DebugStats.empty);
      expect(hud.fps, greaterThan(0));
    });

    test('publishes stats on the throttle boundary', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      hud.toggleDebug();
      hud.recordFrame(0.1, 1, 2, 3);
      expect(hud.debugStats.value, DebugStats.empty);
      hud.recordFrame(0.2, 10.5, 20.25, 30.125);
      final stats = hud.debugStats.value;
      expect(stats.x, 10.5);
      expect(stats.y, 20.25);
      expect(stats.z, 30.125);
      expect(stats.blockName, 'stone');
      expect(stats.fps, greaterThan(0));
    });

    test('formats the expanded F3 readout', () {
      const stats = DebugStats(
        fps: 59.94,
        x: 128.5,
        y: 40,
        z: -3.25,
        blockName: 'planks oak',
        lastAction: 'placed 1/2/3',
      );
      expect(
        formatDebugStats(stats),
        'fps 59.9\n'
        'xyz 128.50 / 40.00 / -3.25\n'
        'chunks 0/0  mesh queue 0  rd 0\n'
        'movement: walk\n'
        'block planks oak\n'
        'action placed 1/2/3',
      );
    });

    test('F3 readout reports the actual sprint state', () {
      const stats = DebugStats(
        fps: 60,
        x: 0,
        y: 0,
        z: 0,
        blockName: 'stone',
        lastAction: '-',
        sprinting: true,
      );

      expect(formatDebugStats(stats), contains('movement: sprint'));
    });
  });

  group('block palette labels', () {
    test('underscores become spaces', () {
      expect(blockLabel(Blocks.planksOak), 'planks oak');
      expect(blockLabel(Blocks.stone), 'stone');
      expect(blockLabel(Blocks.air), 'air');
      expect(blockLabel(999), 'air');
    });
  });
}
