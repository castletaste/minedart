import 'package:flutter/services.dart';

enum GameControl {
  moveForward,
  moveBackward,
  strafeLeft,
  strafeRight,
  jump,
  openInventory,
  cycleFog,
  storeSpawn,
  respawn,
  toggleNoclip,
  debugOverlay,
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
