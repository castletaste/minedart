import 'package:flutter/foundation.dart';

import '../../game/minedart_game.dart';
import '../render/showcase_render.dart' as renderer;
import 'minimap_widgets.dart';

/// Bridges game view/world events to the minimap without polling the game.
final class GameShellMinimapController {
  factory GameShellMinimapController({
    required MinedartGame Function() currentGame,
    required bool Function() isMounted,
  }) => GameShellMinimapController._(currentGame, isMounted);

  GameShellMinimapController._(this._currentGame, this._isMounted)
    : state = ValueNotifier<MinimapViewState>(_createState(_currentGame()));

  final MinedartGame Function() _currentGame;
  final bool Function() _isMounted;
  final ValueNotifier<MinimapViewState> state;

  void playerViewChanged() => _update();

  void worldChanged() => _update(worldChanged: true);

  void reset() {
    if (!_isMounted()) return;
    state.value = _createState(_currentGame());
  }

  void dispose() => state.dispose();

  void _update({bool worldChanged = false}) {
    if (!_isMounted()) return;
    final previous = state.value;
    final snapshot = worldChanged
        ? _worldSnapshot(previous.snapshot)
        : previous.snapshot;
    final next = _createState(_currentGame(), snapshot: snapshot);
    if (next.playerX == previous.playerX &&
        next.playerZ == previous.playerZ &&
        next.heading == previous.heading &&
        identical(next.snapshot, previous.snapshot)) {
      return;
    }
    state.value = next;
  }

  renderer.MinimapSnapshot _worldSnapshot(renderer.MinimapSnapshot previous) {
    final world = _currentGame().voxelWorld;
    final revision = renderer.MinimapSnapshot.revisionOf(world);
    return previous.sourceRevision == revision
        ? previous
        : renderer.MinimapSnapshot.fromWorld(world, sourceRevision: revision);
  }

  static MinimapViewState _createState(
    MinedartGame game, {
    renderer.MinimapSnapshot? snapshot,
  }) => MinimapViewState(
    snapshot: snapshot ?? renderer.MinimapSnapshot.fromWorld(game.voxelWorld),
    playerX: game.playerMapPosition.x,
    playerZ: game.playerMapPosition.z,
    heading: game.cameraYaw,
  );
}
