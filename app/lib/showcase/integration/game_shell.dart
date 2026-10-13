import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';

import '../../audio/audio.dart';
import '../../data/worlds/worlds.dart';
import '../../game/game_host_port.dart';
import '../../game/minedart_game.dart';
import '../../input/touch_capabilities.dart';
import '../controller/showcase_controllers.dart';
import '../render/showcase_render.dart' as renderer;
import '../ui/controls_hint.dart';
import 'controls_hint_idle.dart';
import 'game_shell_minimap_controller.dart';
import 'input_capture_coordinator.dart';
import 'game_runtime_host.dart';
import 'game_shell_modal_controller.dart';
import 'game_shell_options_bridge.dart';
import 'modal_input_controller.dart';
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
  late final GameShellModalController _modals;
  late final MinedartGameHostPort _gameHostPort = _GameShellHostPort(
    onPauseRequested: () => _launch(_modals.showPauseOptions()),
    onMovementActivity: _recordMovementActivity,
    onPlayerViewChanged: () => _minimapController.playerViewChanged(),
    onWorldChanged: () => _minimapController.worldChanged(),
    onFogPresetChanged: _options.setFogPreset,
  );
  late final GameShellOptionsBridge _optionsBridge = GameShellOptionsBridge(
    currentGame: () => _runtime.game,
    options: _options,
    audio: widget.audio,
    launch: _launch,
  );
  final WorldLibraryController _worldLibrary = WorldLibraryController();
  late final GameShellMinimapController _minimapController;
  late final ValueNotifier<MinimapViewState> _minimap;
  bool _foreground = true;

  final ValueNotifier<bool> _touchControls = ValueNotifier(
    prefersTouchControls,
  );
  bool _touchModeOverridden = false;
  bool get _switchingWorld => _session.isBusy;
  late final ControlsHintIdleController _controlsHintIdle =
      ControlsHintIdleController(
        onChanged: () {
          if (mounted) setState(() {});
        },
      );
  late final InputCaptureCoordinator _inputCapture = InputCaptureCoordinator((
    captured,
  ) {
    _runtime.game.setUiInputCaptured(captured);
    _syncControlsHintTimer();
    // Removing touch widgets drops their pointer IDs across modal routes.
    // ModalInputRegion can release ownership from dispose while the element
    // tree is locked. The input gate above changes immediately; defer only UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  });
  late final ModalInputController _modalInput = ModalInputController(
    currentGame: () => _runtime.game,
    onActivity: _recordMovementActivity,
    capture: _inputCapture,
  );

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
      onChanged: _sessionChanged,
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
    );
    _libraryActions = WorldLibraryActions(
      session: _session,
      refresh: _refreshWorlds,
    );
    _modals = GameShellModalController(
      navigatorContext: () => _navigatorContext,
      modalInput: _modalInput,
      builder: _builder,
      options: _options,
      renderLab: _optionsBridge.renderUi,
      touchControls: _touchControls,
      worldLibrary: _worldLibrary,
      libraryActions: _libraryActions,
      session: _session,
      refreshWorlds: _refreshWorlds,
      launch: _launch,
      onTouchControlsChanged: (enabled) {
        _touchModeOverridden = true;
        _touchControls.value = enabled;
      },
    );
    _builder.addListener(_syncBuilderToGame);
    _options.addListener(_optionsBridge.applyOptions);
    _minimapController = GameShellMinimapController(
      currentGame: () => _runtime.game,
      isMounted: () => mounted,
    );
    _minimap = _minimapController.state;
    _attachGame(_runtime.game, activate: true);
    _launch(_refreshWorlds());
  }

  void _attachGame(MinedartGame game, {bool activate = false}) {
    game.diagnostics.updateState(
      sessionEpoch: _session.operationEpoch,
      sessionBusy: _session.isBusy,
      sessionFaulted: _session.isFaulted,
    );
    game.hud.selectedSlot.addListener(_syncGameSlotToBuilder);
    game.hostPort = _gameHostPort;
    game.setUiInputCaptured(_inputCapture.isCaptured);
    _syncBuilderToGame();
    _optionsBridge.attach();
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
        _optionsBridge.ready();
      }),
    );
  }

  void _detachGame(MinedartGame game) {
    game.hud.selectedSlot.removeListener(_syncGameSlotToBuilder);
    game.hostPort = null;
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

  void _recordMovementActivity() => _controlsHintIdle.recordActivity();

  void _syncControlsHintTimer() => _controlsHintIdle.setActive(
    _foreground && !_inputCapture.isCaptured && !_switchingWorld,
  );

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
      _minimapController.reset();
      _attachGame(next.game);
    }
    _syncControlsHintTimer();
    _syncDiagnostics();
    setState(() {});
  }

  void _syncDiagnostics() {
    if (_runtime.game.isSessionDisposed) return;
    _runtime.game.diagnostics.updateState(
      sessionEpoch: _session.operationEpoch,
      sessionBusy: _session.isBusy,
      sessionFaulted: _session.isFaulted,
    );
    _runtime.game.diagnostics.publish();
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
    _foreground = state == AppLifecycleState.resumed;
    _host.setForeground(_foreground);
    _syncControlsHintTimer();
  }

  @override
  void dispose() {
    _host.detach();
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    _detachGame(_runtime.game);
    _builder
      ..removeListener(_syncBuilderToGame)
      ..dispose();
    _options.removeListener(_optionsBridge.applyOptions);
    _optionsBridge.dispose();
    _worldLibrary.dispose();
    _controlsHintIdle.dispose();
    _minimapController.dispose();
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
                    !_modalInput.isCaptured &&
                    !_switchingWorld,
                onPause: () => _launch(_modals.showPauseOptions()),
                onInventory: () => _launch(_modals.showBuilder()),
              ),
            ),
            builder: (context, child) => CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _launch(_modals.showPauseOptions()),
                SingleActivator(
                  _options.bindingFor(GameInputAction.openInventory),
                ): () =>
                    _launch(_modals.showBuilder()),
                SingleActivator(
                  _options.bindingFor(GameInputAction.debugOverlay),
                ): _runtime.game.hud.toggleDebug,
              },
              child: child!,
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

final class _GameShellHostPort implements MinedartGameHostPort {
  const _GameShellHostPort({
    required this.onPauseRequested,
    required this.onMovementActivity,
    required this.onPlayerViewChanged,
    required this.onWorldChanged,
    required this.onFogPresetChanged,
  });

  final VoidCallback onPauseRequested;
  final VoidCallback onMovementActivity;
  final VoidCallback onPlayerViewChanged;
  final VoidCallback onWorldChanged;
  final ValueChanged<renderer.FogPreset> onFogPresetChanged;

  @override
  void pauseRequested() => onPauseRequested();

  @override
  void movementActivity() => onMovementActivity();

  @override
  void playerViewChanged() => onPlayerViewChanged();

  @override
  void worldChanged() => onWorldChanged();

  @override
  void fogPresetChanged(renderer.FogPreset preset) =>
      onFogPresetChanged(preset);
}
