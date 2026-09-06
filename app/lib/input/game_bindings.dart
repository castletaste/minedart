import 'package:flutter/services.dart';

enum GameControl {
  moveForward('Move forward'),
  moveBackward('Move backward'),
  strafeLeft('Strafe left'),
  strafeRight('Strafe right'),
  jump('Jump'),
  openInventory('Open inventory'),
  cycleFog('Cycle fog'),
  storeSpawn('Save Teleport'),
  respawn('Teleport'),
  toggleNoclip('Toggle noclip'),
  debugOverlay('Debug overlay');

  const GameControl(this.label);

  final String label;
}

final class GameBindings {
  GameBindings([Map<GameControl, LogicalKeyboardKey>? values])
    : _values = <GameControl, LogicalKeyboardKey>{...defaults, ...?values};

  static const Map<GameControl, LogicalKeyboardKey> defaults = {
    GameControl.moveForward: LogicalKeyboardKey.keyW,
    GameControl.moveBackward: LogicalKeyboardKey.keyS,
    GameControl.strafeLeft: LogicalKeyboardKey.keyA,
    GameControl.strafeRight: LogicalKeyboardKey.keyD,
    GameControl.jump: LogicalKeyboardKey.space,
    GameControl.openInventory: LogicalKeyboardKey.keyE,
    GameControl.cycleFog: LogicalKeyboardKey.keyF,
    GameControl.storeSpawn: LogicalKeyboardKey.enter,
    GameControl.respawn: LogicalKeyboardKey.keyR,
    GameControl.toggleNoclip: LogicalKeyboardKey.keyN,
    GameControl.debugOverlay: LogicalKeyboardKey.f3,
  };

  final Map<GameControl, LogicalKeyboardKey> _values;

  LogicalKeyboardKey operator [](GameControl control) => _values[control]!;

  GameBindings copy() => GameBindings(_values);
}
