import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/hud/block_palette.dart';
import 'package:minedart/hud/debug_overlay.dart';
import 'package:minedart/hud/hud_state.dart';
import 'package:minedart/performance/performance_snapshot.dart';
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

    test('formats the exact throttled performance F3 readout', () {
      const stats = DebugStats(
        fps: 60.04,
        x: 1,
        y: 2,
        z: 3,
        blockName: 'stone',
        lastAction: 'broke 4/5/6',
        visibleChunks: 8,
        loadedChunks: 12,
        meshQueue: 999,
        renderDistance: 10,
        sprinting: true,
        performance: PerformanceSnapshot(
          wallFrame: TimingPercentiles(
            sampleCount: 3,
            p50Ms: 16,
            p95Ms: 18.25,
            p99Ms: 22.5,
          ),
          update: TimingPercentiles(
            sampleCount: 3,
            p50Ms: 2,
            p95Ms: 3,
            p99Ms: 4,
          ),
          cpuRender: TimingPercentiles(
            sampleCount: 3,
            p50Ms: 6.5,
            p95Ms: 7.75,
            p99Ms: 8,
          ),
          mainThreadMesh: TimingPercentiles(
            sampleCount: 2,
            p50Ms: 0.5,
            p95Ms: 1.25,
            p99Ms: 1.25,
          ),
          drawCount: 83,
          meshQueue: 7,
          devicePixelRatio: 2,
          effectiveTargetWidth: 2560,
          effectiveTargetHeight: 1440,
          retainedComponentCount: 321,
          retainedMeshBytes: 987654,
          webCache: WebCacheCountersSnapshot(
            uniformUploadHits: 45,
            uniformUploadMisses: 3,
            bindGroupHits: 42,
            bindGroupMisses: 6,
          ),
        ),
      );

      expect(
        formatDebugStats(stats),
        'fps 60.0\n'
        'xyz 1.00 / 2.00 / 3.00\n'
        'chunks 8/12  mesh queue 7  rd 10\n'
        'movement: sprint\n'
        'wall frame p50 16.0  p95 18.3  p99 22.5 ms\n'
        'update p50 2.0  p95 3.0  p99 4.0 ms\n'
        'cpu render p50 6.5  p95 7.8  p99 8.0 ms\n'
        'cpu mesh drain p50 0.5  p95 1.3  p99 1.3 ms\n'
        'draws 83  target 2560x1440 px @ dpr 2.00\n'
        'retained components 321  mesh bytes 987654\n'
        'web uniform upload hit/miss 45/3  '
        'bind-group hit/miss 42/6\n'
        'block stone\n'
        'action broke 4/5/6',
      );
      expect(formatDebugStats(stats), isNot(contains('GPU')));
    });

    test('publishes the retained performance snapshot on the HUD boundary', () {
      final hud = HudState();
      addTearDown(hud.dispose);
      hud.toggleDebug();
      hud.updatePerformanceSnapshot(PerformanceSnapshot.empty);

      hud.recordFrame(0.249, 1, 2, 3);
      expect(hud.debugStats.value.performance, isNull);
      hud.recordFrame(0.001, 4, 5, 6);
      expect(hud.debugStats.value.performance, same(PerformanceSnapshot.empty));
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
