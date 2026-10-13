import '../../audio/audio.dart';
import '../../game/minedart_game.dart';
import '../controller/options_controller.dart';
import '../controller/render_lab_controller.dart';

/// Applies options and Render Lab changes to the current ready game.
final class GameShellOptionsBridge {
  GameShellOptionsBridge({
    required this.currentGame,
    required this.options,
    required this.audio,
    required this.launch,
  });

  final MinedartGame Function() currentGame;
  final OptionsController options;
  final AudioServiceApi audio;
  final void Function(Future<void>) launch;
  late final RenderLabController renderUi = RenderLabController(
    onChanged: applyRenderUi,
  );
  bool _gameLoaded = false;
  FogPreset? _lastAppliedOptionsFog;
  bool _syncingRenderDistance = false;

  void attach() {
    _gameLoaded = false;
    _lastAppliedOptionsFog = null;
  }

  void ready() {
    _gameLoaded = true;
    applyOptions();
    applyRenderUi(renderUi.settings);
  }

  void dispose() => renderUi.dispose();

  void applyOptions() {
    final game = currentGame();
    game
      ..setBindings(options.gameBindings)
      ..setMouseOptions(
        sensitivity: options.mouseSensitivity * 0.01,
        invertY: options.invertMouseY,
      );
    launch(audio.setSfxVolume(options.masterVolume * options.effectsVolume));
    launch(audio.setMusicVolume(options.ambienceVolume));
    launch(audio.setMuted(options.audioMuted));
    if (!_gameLoaded) return;
    final fog = options.fogPreset;
    game.renderLab
      ..setHighContrast(options.highContrast)
      ..setReducedMotion(options.reducedMotion);
    if (_lastAppliedOptionsFog != options.fogPreset) {
      _lastAppliedOptionsFog = options.fogPreset;
      final distance = fog.renderDistanceChunks;
      game
        ..renderLab.setFogPreset(fog)
        ..setRenderDistanceChunks(distance);
      if (renderUi.settings.renderDistance != distance) {
        // The synchronous UI callback also reapplies its custom fog density;
        // syncing the preset radius must not trigger that unrelated override.
        _syncingRenderDistance = true;
        try {
          renderUi.setRenderDistance(distance.toDouble());
        } finally {
          _syncingRenderDistance = false;
        }
      }
    }
  }

  void applyRenderUi(RenderLabSettings settings) {
    if (!_gameLoaded || _syncingRenderDistance) return;
    final bridge = currentGame().renderLab;
    bridge
      ..setTargetOutlineEnabled(settings.targetOutline)
      ..setBlockParticlesEnabled(settings.blockParticles);
    currentGame()
      ..setRenderDistanceChunks(settings.renderDistance)
      ..setRenderStyle(
        debugView: settings.debugView.shaderCode,
        fogDensity: settings.fogDensity,
        ambientOcclusion: settings.ambientOcclusion,
      );
  }
}
