import 'package:minedart/game/minedart_game.dart';

import 'input_capture_coordinator.dart';

/// Coordinates modal routes with gameplay input ownership.
///
/// A modal acquires the shared capture gate before it is shown and releases it
/// exactly once after the route completes. The game reference is resolved at
/// acquisition time so a session replacement cannot retain an old runtime.
final class ModalInputController {
  ModalInputController({
    required this.currentGame,
    required this.onActivity,
    required this.capture,
  });

  final MinedartGame Function() currentGame;
  final void Function() onActivity;
  final InputCaptureCoordinator capture;
  bool _open = false;

  bool get isCaptured => capture.isCaptured;
  bool get isOpen => _open;

  void inputCaptureChanged(bool captured) => capture.update(captured);

  Future<void> run(
    Future<void> Function() action, {
    bool pauseSimulation = false,
  }) async {
    if (_open) return;
    _open = true;
    final game = currentGame();
    if (pauseSimulation) game.simulationPaused = true;
    try {
      onActivity();
      capture.update(true);
      await game.awaitUiInputRelease();
      await action();
    } finally {
      capture.update(false);
      onActivity();
      if (pauseSimulation) game.simulationPaused = false;
      _open = false;
    }
  }
}
