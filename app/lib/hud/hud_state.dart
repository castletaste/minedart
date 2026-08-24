/// Shared HUD state: hotbar selection, debug toggle, throttled debug stats.
///
/// Per-frame data (fps, player position) is accumulated without notifying so
/// the widget tree only rebuilds a few times per second, and only while the
/// debug overlay is visible.
library;

import 'package:flutter/foundation.dart';

import 'block_palette.dart';

/// Snapshot rendered by the debug overlay.
@immutable
final class DebugStats {
  const DebugStats({
    required this.fps,
    required this.x,
    required this.y,
    required this.z,
    required this.blockName,
    required this.lastAction,
    this.visibleChunks = 0,
    this.loadedChunks = 0,
    this.meshQueue = 0,
    this.renderDistance = 0,
    this.sprinting = false,
  });

  static const DebugStats empty = DebugStats(
    fps: 0,
    x: 0,
    y: 0,
    z: 0,
    blockName: '-',
    lastAction: '-',
  );

  final double fps;
  final double x;
  final double y;
  final double z;
  final String blockName;
  final String lastAction;
  final int visibleChunks;
  final int loadedChunks;
  final int meshQueue;
  final int renderDistance;
  final bool sprinting;

  @override
  bool operator ==(Object other) =>
      other is DebugStats &&
      other.fps == fps &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.blockName == blockName &&
      other.lastAction == lastAction &&
      other.visibleChunks == visibleChunks &&
      other.loadedChunks == loadedChunks &&
      other.meshQueue == meshQueue &&
      other.renderDistance == renderDistance &&
      other.sprinting == sprinting;

  @override
  int get hashCode => Object.hash(
    fps,
    x,
    y,
    z,
    blockName,
    lastAction,
    visibleChunks,
    loadedChunks,
    meshQueue,
    renderDistance,
    sprinting,
  );
}

final class HudState {
  HudState({List<int>? blocks})
    : blocks = List<int>.of(blocks ?? kHotbarBlocks, growable: false);

  /// Smoothing factor for the frame-rate EMA.
  static const double _fpsAlpha = 0.1;

  /// Debug stats are republished at most this often.
  static const Duration statsInterval = Duration(milliseconds: 250);

  final List<int> blocks;

  final ValueNotifier<int> selectedSlot = ValueNotifier<int>(0);
  final ValueNotifier<int> hotbarRevision = ValueNotifier<int>(0);
  final ValueNotifier<bool> debugVisible = ValueNotifier<bool>(false);
  final ValueNotifier<DebugStats> debugStats = ValueNotifier<DebugStats>(
    DebugStats.empty,
  );

  double _fps = 0;
  double _statsAge = 0;
  String _lastAction = '-';

  /// Frame-rate EMA; 0 until the first frame is recorded.
  double get fps => _fps;

  int get slotCount => blocks.length;

  /// Block id of the active slot.
  int get selectedBlock => blocks[selectedSlot.value];

  /// Selects [slot], ignoring out-of-range values.
  void selectSlot(int slot) {
    if (slot < 0 || slot >= blocks.length) return;
    selectedSlot.value = slot;
  }

  void replaceHotbar(List<int> next, {int? selectedSlot}) {
    if (next.length != blocks.length) {
      throw ArgumentError.value(next.length, 'next.length', blocks.length);
    }
    var changed = false;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i] != next[i]) {
        changed = true;
        break;
      }
    }
    if (changed) blocks.setAll(0, next);
    final oldSelected = this.selectedSlot.value;
    if (selectedSlot != null &&
        selectedSlot >= 0 &&
        selectedSlot < blocks.length) {
      this.selectedSlot.value = selectedSlot;
    }
    if (changed || this.selectedSlot.value != oldSelected) {
      hotbarRevision.value++;
    }
  }

  /// Moves the selection by [steps], wrapping around both ends.
  void cycleSlot(int steps) {
    if (steps == 0) return;
    final count = blocks.length;
    selectedSlot.value = ((selectedSlot.value + steps) % count + count) % count;
  }

  /// Maps a vertical scroll delta to a slot change (scroll down = next slot).
  void handleScroll(double scrollDeltaY) {
    if (scrollDeltaY > 0) {
      cycleSlot(1);
    } else if (scrollDeltaY < 0) {
      cycleSlot(-1);
    }
  }

  void toggleDebug() => debugVisible.value = !debugVisible.value;

  void recordAction(String action) {
    _lastAction = action;
  }

  /// Feeds one rendered frame; publishes stats on [statsInterval] boundaries.
  void recordFrame(
    double dt,
    double x,
    double y,
    double z, {
    int visibleChunks = 0,
    int loadedChunks = 0,
    int meshQueue = 0,
    int renderDistance = 0,
    bool sprinting = false,
  }) {
    if (dt > 0) {
      final instant = 1 / dt;
      _fps = _fps == 0 ? instant : _fps + (instant - _fps) * _fpsAlpha;
    }
    if (!debugVisible.value) return;
    _statsAge += dt;
    if (_statsAge < statsInterval.inMilliseconds / 1000) return;
    _statsAge = 0;
    debugStats.value = DebugStats(
      fps: _fps,
      x: x,
      y: y,
      z: z,
      blockName: blockLabel(selectedBlock),
      lastAction: _lastAction,
      visibleChunks: visibleChunks,
      loadedChunks: loadedChunks,
      meshQueue: meshQueue,
      renderDistance: renderDistance,
      sprinting: sprinting,
    );
  }

  void dispose() {
    selectedSlot.dispose();
    hotbarRevision.dispose();
    debugVisible.dispose();
    debugStats.dispose();
  }
}
