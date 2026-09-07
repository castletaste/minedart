import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';

import '../../audio/audio.dart';
import '../../data/worlds/worlds.dart';
import '../../game/minedart_game.dart';
import '../../input/touch_capabilities.dart';
import '../controller/showcase_controllers.dart';
import '../render/showcase_render.dart' as renderer;
import '../ui/controls_hint.dart';
import '../ui/showcase_ui.dart';
import 'controls_hint_idle.dart';
import 'input_capture_coordinator.dart';
import 'game_runtime_host.dart';
import 'world_session_coordinator.dart';
import 'world_library_actions.dart';
import 'minimap_widgets.dart';
import 'world_runtime.dart';

final class GameShell extends StatefulWidget {
  const GameShell({
    required this.repository,
    required this.audio,
    required this.initialRuntime,
    required this.options,
    super.key,
  });

  final WorldRepository repository;
  final AudioServiceApi audio;
  final WorldRuntime initialRuntime;
  final OptionsController options;

  @override
  State<GameShell> createState() => _GameShellState();
}

final class _GameShellState extends State<GameShell>
    with WidgetsBindingObserver {
  late WorldRuntime _runtime = widget.initialRuntime;
  late final BuilderStudioController _builder = BuilderStudioController(
    initialHotbar: _runtime.game.hud.blocks,
  );
  OptionsController get _options => widget.options;
  late final GameRuntimeHostController _host;
  late final WorldSessionCoordinator _session;
  late final WorldLibraryActions _libraryActions;
  late final RenderLabController _renderUi = RenderLabController(
    onChanged: _applyRenderUi,
  );
  final WorldLibraryController _worldLibrary = WorldLibraryController();
  late final ValueNotifier<MinimapViewState> _minimap;
  Timer? _minimapTimer;
  int _minimapTicks = 0;

  final ValueNotifier<bool> _touchControls = ValueNotifier(
    prefersTouchControls,
  );
  bool _touchModeOverridden = false;
  bool _gameLoaded = false;
  bool _modalOpen = false;
  bool get _switchingWorld => _session.isBusy;
  bool _savingAndQuitting = false;
  static const Duration _uiPollInterval = Duration(milliseconds: 250);
  final ControlsHintIdleState _controlsHintIdle = ControlsHintIdleState();
  FogPreset? _lastAppliedOptionsFog;
  bool _syncingRenderDistance = false;
  late final InputCaptureCoordinator _inputCapture = InputCaptureCoordinator((
    captured,
  ) {
    _runtime.game.setUiInputCaptured(captured);
    // Removing touch widgets drops their pointer IDs across modal routes.
    if (mounted) setState(() {});
  });

  BuildContext? get _navigatorContext => mounted ? context : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _host = GameRuntimeHostController(_runtime);
    _session = WorldSessionCoordinator(
      initialRuntime: _runtime,
      repository: widget.repository,
      host: _host,
      createRuntime: (document) async {
        final next = await WorldRuntime.create(
          repository: widget.repository,
          document: document,
          audio: widget.audio,
          input: widget.initialRuntime.input,
        );
        next.game
          ..setUiInputCaptured(_inputCapture.isCaptured)
          ..setBindings(_options.gameBindings);
        next.game.hud.replaceHotbar(
          _builder.hotbar,
          selectedSlot: _builder.selectedHotbarSlot,
        );
        return next;
      },
    )..addListener(_sessionChanged);
    _libraryActions = WorldLibraryActions(
      session: _session,
      refresh: _refreshWorlds,
    );
    _builder.addListener(_syncBuilderToGame);
    _options.addListener(_applyOptions);
    _minimap = ValueNotifier(_createMinimapState());
    _minimapTimer = Timer.periodic(_uiPollInterval, (_) {
      _updateControlsHint();
      _updateMinimap();
    });
    _attachGame(_runtime.game, activate: true);
    _launch(_refreshWorlds());
  }

  void _attachGame(MinedartGame game, {bool activate = false}) {
    game.hud.selectedSlot.addListener(_syncGameSlotToBuilder);
    game.onPauseRequested = () => _launch(_showPauseOptions());
    game.onMovementActivity = _recordMovementActivity;
    game.setUiInputCaptured(_inputCapture.isCaptured);
    game.onFogPresetChanged = (preset) {
      _options.setFogPreset(preset);
    };
    _syncBuilderToGame();
    _gameLoaded = false;
    _lastAppliedOptionsFog = null;
    _launch(
      game.mountedReady.then((error) {
        if (!mounted || game != _runtime.game) return;
        if (error != null) {
          _reportUiError(error, StackTrace.current);
          return;
        }
        if (activate && !_session.isBusy && !_session.isFaulted) {
          _runtime.resume();
        }
        _gameLoaded = true;
        _applyOptions();
        _applyRenderUi(_renderUi.settings);
      }),
    );
  }

  void _detachGame(MinedartGame game) {
    game.hud.selectedSlot.removeListener(_syncGameSlotToBuilder);
    game
      ..onPauseRequested = null
      ..onMovementActivity = null
      ..onFogPresetChanged = null;
  }

  void _syncBuilderToGame() {
    _runtime.game.hud.replaceHotbar(
      _builder.hotbar,
      selectedSlot: _builder.selectedHotbarSlot,
    );
  }

  void _syncGameSlotToBuilder() {
    _builder.selectHotbarSlot(_runtime.game.hud.selectedSlot.value);
  }

  void _onModalInputCaptureChanged(bool captured) {
    _inputCapture.update(captured);
  }

  Future<void> _acquireModalInput() async {
    _recordMovementActivity();
    _inputCapture.update(true);
    await _runtime.game.awaitUiInputRelease();
  }

  void _releaseModalInput() {
    _inputCapture.update(false);
    _recordMovementActivity();
  }

  void _recordMovementActivity() {
    if (!_controlsHintIdle.recordActivity() || !mounted) return;
    setState(() {});
  }

  void _updateControlsHint() {
    if (!mounted || _inputCapture.isCaptured || _switchingWorld) return;
    if (_controlsHintIdle.advance(_uiPollInterval)) setState(() {});
  }

  MinimapViewState _createMinimapState({renderer.MinimapSnapshot? snapshot}) {
    final game = _runtime.game;
    return MinimapViewState(
      snapshot: snapshot ?? renderer.MinimapSnapshot.fromWorld(game.voxelWorld),
      playerX: game.playerMapPosition.x,
      playerZ: game.playerMapPosition.z,
      heading: game.cameraYaw,
    );
  }

  void _updateMinimap() {
    if (!mounted) return;
    final previous = _minimap.value;
    _minimapTicks++;
    if (_minimapTicks % 8 != 0) {
      _minimap.value = _createMinimapState(snapshot: previous.snapshot);
      return;
    }
    final world = _runtime.game.voxelWorld;
    final revision = renderer.MinimapSnapshot.revisionOf(world);
    _minimap.value = _createMinimapState(
      snapshot: previous.snapshot.sourceRevision == revision
          ? previous.snapshot
          : renderer.MinimapSnapshot.fromWorld(world, sourceRevision: revision),
    );
  }

  void _applyOptions() {
    final game = _runtime.game;
    game
      ..setBindings(_options.gameBindings)
      ..setMouseOptions(
        sensitivity: _options.mouseSensitivity * 0.01,
        invertY: _options.invertMouseY,
      );
    _launch(
      widget.audio.setSfxVolume(_options.masterVolume * _options.effectsVolume),
    );
    _launch(widget.audio.setMusicVolume(_options.ambienceVolume));
    _launch(widget.audio.setMuted(_options.audioMuted));
    if (!_gameLoaded) return;
    final fog = _options.fogPreset;
    game.renderLab
      ..setHighContrast(_options.highContrast)
      ..setReducedMotion(_options.reducedMotion);
    if (_lastAppliedOptionsFog != _options.fogPreset) {
      _lastAppliedOptionsFog = _options.fogPreset;
      final distance = fog.renderDistanceChunks;
      game
        ..renderLab.setFogPreset(fog)
        ..setRenderDistanceChunks(distance);
      if (_renderUi.settings.renderDistance != distance) {
        // The synchronous UI callback also reapplies its custom fog density;
        // syncing the preset radius must not trigger that unrelated override.
        _syncingRenderDistance = true;
        _renderUi.setRenderDistance(distance.toDouble());
        _syncingRenderDistance = false;
      }
    }
  }

  void _applyRenderUi(RenderLabSettings settings) {
    if (!_gameLoaded || _syncingRenderDistance) return;
    final bridge = _runtime.game.renderLab;
    bridge
      ..setTargetOutlineEnabled(settings.targetOutline)
      ..setBlockParticlesEnabled(settings.blockParticles);
    _runtime.game
      ..setRenderDistanceChunks(settings.renderDistance)
      ..setRenderStyle(
        debugView: settings.debugView.shaderCode,
        fogDensity: settings.fogDensity,
        ambientOcclusion: settings.ambientOcclusion,
      );
  }

  Future<void> _showBuilder() async {
    final modalContext = _navigatorContext;
    if (_modalOpen || !mounted || modalContext == null) return;
    _modalOpen = true;
    try {
      await _acquireModalInput();
      if (!mounted || !modalContext.mounted) return;
      await showBuilderStudio(
        modalContext,
        controller: _builder,
        closeKey: _options.bindingFor(GameInputAction.openInventory),
        onInputCaptureChanged: _onModalInputCaptureChanged,
      );
    } finally {
      _releaseModalInput();
      _modalOpen = false;
    }
  }

  Future<void> _showPauseOptions() async {
    final modalContext = _navigatorContext;
    if (_modalOpen || !mounted || modalContext == null) return;
    _modalOpen = true;
    _runtime.game.simulationPaused = true;
    try {
      await _acquireModalInput();
      if (!mounted || !modalContext.mounted) return;
      await showDialog<void>(
        context: modalContext,
        barrierDismissible: false,
        requestFocus: true,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: ValueListenableBuilder<bool>(
            valueListenable: _touchControls,
            builder: (context, touchControls, _) => PauseOptionsView(
              controller: _options,
              touchControls: touchControls,
              onTouchControlsChanged: (enabled) {
                _touchModeOverridden = true;
                _touchControls.value = enabled;
              },
              onInputCaptureChanged: _onModalInputCaptureChanged,
              callbacks: PauseMenuCallbacks(
                onResume: () => Navigator.of(dialogContext).pop(),
                onOpenWorldLibrary: () =>
                    _transitionModal(dialogContext, _showWorldLibrary),
                onOpenRenderLab: () =>
                    _transitionModal(dialogContext, _showRenderLab),
                onSaveAndQuit: () =>
                    _launch(_saveAndOpenLibrary(dialogContext)),
              ),
            ),
          ),
        ),
      );
    } finally {
      _releaseModalInput();
      _modalOpen = false;
      _runtime.game.simulationPaused = false;
    }
  }

  void _transitionModal(
    BuildContext dialogContext,
    Future<void> Function() to,
  ) {
    Navigator.of(dialogContext).pop();
    _modalOpen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _launch(to());
    });
  }

  Future<void> _saveAndOpenLibrary(BuildContext dialogContext) async {
    if (_savingAndQuitting) return;
    _savingAndQuitting = true;
    try {
      final result = await _session.saveCurrent();
      if (result is WorldSessionFailure<void>) throw result;
      if (result is WorldSessionSuccess<void> &&
          mounted &&
          dialogContext.mounted) {
        _transitionModal(dialogContext, _showWorldLibrary);
      }
    } finally {
      _savingAndQuitting = false;
    }
  }

  Future<void> _showRenderLab() => _showPanel(
    title: 'Render Lab',
    child: RenderLabPanel(controller: _renderUi),
  );

  Future<void> _showPanel({
    required String title,
    required Widget child,
  }) async {
    final modalContext = _navigatorContext;
    if (_modalOpen || !mounted || modalContext == null) return;
    _modalOpen = true;
    try {
      await _acquireModalInput();
      if (!mounted || !modalContext.mounted) return;
      await showDialog<void>(
        context: modalContext,
        requestFocus: true,
        builder: (dialogContext) => ModalInputRegion(
          onInputCaptureChanged: _onModalInputCaptureChanged,
          child: Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
              child: Column(
                children: [
                  ListTile(
                    title: Text(title),
                    trailing: IconButton(
                      tooltip: 'Close $title',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      _releaseModalInput();
      _modalOpen = false;
    }
  }

  Future<void> _showWorldLibrary() async {
    if (_modalOpen || !mounted || _navigatorContext == null) return;
    _modalOpen = true;
    try {
      await _acquireModalInput();
      if (!mounted) return;
      await _refreshWorlds();
      final modalContext = _navigatorContext;
      if (modalContext == null || !modalContext.mounted) return;
      await showDialog<void>(
        context: modalContext,
        barrierDismissible: false,
        requestFocus: true,
        builder: (dialogContext) => Dialog.fullscreen(
          child: WorldLibraryView(
            controller: _worldLibrary,
            autofocusSearch: !_touchControls.value,
            callbacks: _libraryActions.callbacks(
              onActivated: () {
                if (mounted && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
            ),
            onClose: () => Navigator.of(dialogContext).pop(),
            onInputCaptureChanged: _onModalInputCaptureChanged,
          ),
        ),
      );
    } finally {
      _releaseModalInput();
      _modalOpen = false;
    }
  }

  Future<void> _refreshWorlds() async {
    final summaries = await widget.repository.list();
    if (!mounted) return;
    _worldLibrary.replaceWorlds([
      for (final summary in summaries)
        WorldLibraryEntry(
          id: summary.id,
          name: summary.name,
          seed: summary.seed,
          updatedAt: summary.updatedAt,
          formatVersion: summary.metadata.formatVersion,
          isCurrent: summary.id == _runtime.worldId,
        ),
    ]);
  }

  void _sessionChanged() {
    if (!mounted) return;
    final next = _session.current as WorldRuntime;
    if (!identical(next, _runtime)) {
      _detachGame(_runtime.game);
      _runtime = next;
      _controlsHintIdle.reset();
      _minimap.value = _createMinimapState();
      _attachGame(next.game);
    }
    setState(() {});
  }

  void _launch(Future<void> action) {
    unawaited(action.catchError(_reportUiError));
  }

  void _reportUiError(Object error, StackTrace stack) {
    debugPrint('Game UI operation failed: $error\n$stack');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _host.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _host.detach();
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_sessionChanged);
    _session.dispose();
    _detachGame(_runtime.game);
    _builder
      ..removeListener(_syncBuilderToGame)
      ..dispose();
    _options.removeListener(_applyOptions);
    _renderUi.dispose();
    _worldLibrary.dispose();
    _minimapTimer?.cancel();
    _minimap.dispose();
    _touchControls.dispose();
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    for (final cleanup in <Future<void> Function()>[
      _session.close,
      widget.initialRuntime.input.close,
      widget.audio.dispose,
    ]) {
      try {
        await cleanup();
      } catch (error, stack) {
        debugPrint('Game shutdown failed: $error\n$stack');
      }
    }
    _host.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _touchControls,
    builder: (context, touchControls, _) => Scaffold(
      backgroundColor: const Color(0xFF82C8FF),
      body: Stack(
        children: [
          ListenableBuilder(
            listenable: _options,
            child: Listener(
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.touch &&
                    !touchControls &&
                    !_touchModeOverridden) {
                  _touchControls.value = true;
                }
              },
              child: GameRuntimeHost(
                controller: _host,
                touchControls:
                    touchControls &&
                    !_inputCapture.isCaptured &&
                    !_switchingWorld,
                onPause: () => _launch(_showPauseOptions()),
                onInventory: () => _launch(_showBuilder()),
              ),
            ),
            builder: (context, child) => CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _launch(_showPauseOptions()),
                SingleActivator(
                  _options.bindingFor(GameInputAction.openInventory),
                ): () =>
                    _launch(_showBuilder()),
                SingleActivator(
                  _options.bindingFor(GameInputAction.debugOverlay),
                ): _runtime.game.hud.toggleDebug,
              },
              child: Focus(autofocus: true, child: child!),
            ),
          ),
          MinimapOverlay(state: _minimap, compact: touchControls),
          if (_controlsHintIdle.visible)
            _StartupControlsOverlay(
              options: _options,
              touchControls: touchControls,
            ),
          if (_switchingWorld)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x99000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    ),
  );
}

final class _StartupControlsOverlay extends StatelessWidget {
  const _StartupControlsOverlay({
    required this.options,
    required this.touchControls,
  });
  final OptionsController options;
  final bool touchControls;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (touchControls) {
              return Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 118, 16, 0),
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Left stick to move · Drag to look',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              );
            }
            final compact = constraints.maxWidth < 700;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, compact ? 176 : 16, 16, 16),
              child: Align(
                alignment: compact ? Alignment.topCenter : Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Material(
                    color: const Color(0xCC121812),
                    elevation: 8,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ControlsHint(
                        title: 'Controls',
                        controller: options,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
