import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../input/game_bindings.dart';
import '../render/render_settings.dart';

export '../render/render_settings.dart' show FogPreset;

/// Compatibility name for the canonical game input control.
typedef GameInputAction = GameControl;

/// Mutable options state. Integration listens and applies values to game,
/// renderer, and audio systems; this class performs no such work itself.
final class OptionsController extends ChangeNotifier {
  factory OptionsController({
    Map<GameInputAction, LogicalKeyboardKey>? bindings,
    double mouseSensitivity = 0.4,
    bool invertMouseY = false,
    FogPreset fogPreset = FogPreset.normal,
    double masterVolume = 0.8,
    double effectsVolume = 0.9,
    double ambienceVolume = 0.65,
    bool audioMuted = false,
    bool highContrast = false,
    bool reducedMotion = false,
  }) => OptionsController._(
    bindings: <GameInputAction, LogicalKeyboardKey>{
      ...defaultBindings,
      ...?bindings,
    },
    mouseSensitivity: mouseSensitivity.clamp(0.05, 1.0),
    invertMouseY: invertMouseY,
    fogPreset: fogPreset,
    masterVolume: masterVolume.clamp(0.0, 1.0),
    effectsVolume: effectsVolume.clamp(0.0, 1.0),
    ambienceVolume: ambienceVolume.clamp(0.0, 1.0),
    audioMuted: audioMuted,
    highContrast: highContrast,
    reducedMotion: reducedMotion,
  );

  OptionsController._({
    required this._bindings,
    required this._mouseSensitivity,
    required this._invertMouseY,
    required this._fogPreset,
    required this._masterVolume,
    required this._effectsVolume,
    required this._ambienceVolume,
    required this._audioMuted,
    required this._highContrast,
    required this._reducedMotion,
  });

  static const Map<GameInputAction, LogicalKeyboardKey> defaultBindings =
      GameBindings.defaults;

  final Map<GameInputAction, LogicalKeyboardKey> _bindings;
  GameInputAction? _rebindingAction;
  double _mouseSensitivity;
  bool _invertMouseY;
  FogPreset _fogPreset;
  double _masterVolume;
  double _effectsVolume;
  double _ambienceVolume;
  bool _audioMuted;
  bool _highContrast;
  bool _reducedMotion;

  UnmodifiableMapView<GameInputAction, LogicalKeyboardKey> get bindings =>
      UnmodifiableMapView<GameInputAction, LogicalKeyboardKey>(_bindings);

  /// Immutable-by-convention snapshot for the game input boundary.
  GameBindings get gameBindings => GameBindings(_bindings);

  GameInputAction? get rebindingAction => _rebindingAction;
  double get mouseSensitivity => _mouseSensitivity;
  bool get invertMouseY => _invertMouseY;
  FogPreset get fogPreset => _fogPreset;
  double get masterVolume => _masterVolume;
  double get effectsVolume => _effectsVolume;
  double get ambienceVolume => _ambienceVolume;
  bool get audioMuted => _audioMuted;
  bool get highContrast => _highContrast;
  bool get reducedMotion => _reducedMotion;

  LogicalKeyboardKey bindingFor(GameInputAction action) => _bindings[action]!;

  String bindingLabel(GameInputAction action) => keyLabel(bindingFor(action));

  void beginRebinding(GameInputAction action) {
    if (_rebindingAction == action) return;
    _rebindingAction = action;
    notifyListeners();
  }

  void cancelRebinding() {
    if (_rebindingAction == null) return;
    _rebindingAction = null;
    notifyListeners();
  }

  /// Applies a captured key. Escape cancels. If another action owns the key,
  /// the two bindings swap so each action remains keyboard-reachable.
  void captureKey(LogicalKeyboardKey key) {
    final action = _rebindingAction;
    if (action == null) return;
    if (key == LogicalKeyboardKey.escape) {
      cancelRebinding();
      return;
    }

    final previousKey = _bindings[action]!;
    GameInputAction? conflictingAction;
    for (final entry in _bindings.entries) {
      if (entry.key != action && entry.value == key) {
        conflictingAction = entry.key;
        break;
      }
    }
    _bindings[action] = key;
    if (conflictingAction != null) {
      _bindings[conflictingAction] = previousKey;
    }
    _rebindingAction = null;
    notifyListeners();
  }

  void resetBindings() {
    if (_rebindingAction == null && mapEquals(_bindings, defaultBindings)) {
      return;
    }
    _bindings
      ..clear()
      ..addAll(defaultBindings);
    _rebindingAction = null;
    notifyListeners();
  }

  void setMouseSensitivity(double value) {
    final next = value.clamp(0.05, 1.0);
    if (_mouseSensitivity == next) return;
    _mouseSensitivity = next;
    notifyListeners();
  }

  void setInvertMouseY(bool value) {
    if (_invertMouseY == value) return;
    _invertMouseY = value;
    notifyListeners();
  }

  void setFogPreset(FogPreset value) {
    if (_fogPreset == value) return;
    _fogPreset = value;
    notifyListeners();
  }

  void cycleFog() {
    final next = (_fogPreset.index + 1) % FogPreset.values.length;
    setFogPreset(FogPreset.values[next]);
  }

  void setMasterVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    if (_masterVolume == next) return;
    _masterVolume = next;
    notifyListeners();
  }

  void setEffectsVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    if (_effectsVolume == next) return;
    _effectsVolume = next;
    notifyListeners();
  }

  void setAmbienceVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    if (_ambienceVolume == next) return;
    _ambienceVolume = next;
    notifyListeners();
  }

  void setAudioMuted(bool value) {
    if (_audioMuted == value) return;
    _audioMuted = value;
    notifyListeners();
  }

  void setHighContrast(bool value) {
    if (_highContrast == value) return;
    _highContrast = value;
    notifyListeners();
  }

  void setReducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    notifyListeners();
  }

  static String keyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.escape) return 'Escape';
    if (key == LogicalKeyboardKey.arrowUp) return 'Arrow Up';
    if (key == LogicalKeyboardKey.arrowDown) return 'Arrow Down';
    if (key == LogicalKeyboardKey.arrowLeft) return 'Arrow Left';
    if (key == LogicalKeyboardKey.arrowRight) return 'Arrow Right';
    final label = key.keyLabel.trim();
    return label.isEmpty ? 'Key ${key.keyId}' : label.toUpperCase();
  }
}
