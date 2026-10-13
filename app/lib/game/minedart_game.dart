import 'dart:async';
import 'dart:ui' show Canvas;

import 'package:flame/events.dart';
// Flame host binding: the game loop, lifecycle and input come from Flame;
// all rendering goes through the engine-neutral [VoxelRenderer] port.
import 'package:flame_3d/camera.dart' show FirstPersonCamera, World3D;
import 'package:flame_3d/game.dart' show FlameGame3D;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, MediaQuery;
import 'package:minedart_core/minedart_core.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../assets/atlas_selection.dart';
import '../audio/audio.dart';
import '../diagnostics/diagnostics.dart';
import '../input/game_bindings.dart';
import '../input/game_input_service.dart';
import '../input/mouse_look.dart';
import '../input/sprint_fov.dart';
import '../input/touch_input_state.dart';
import '../hud/hud_state.dart';
import '../pipeline/mesh_pipeline.dart';
import '../performance/performance.dart';
import '../render/chunk_render_manager.dart';
import '../render/flame3d/flame3d_voxel_renderer.dart';
import '../render/voxel_renderer.dart';
import '../showcase/render/showcase_render.dart';
import 'chunk_mesh_coordinator.dart';
import 'game_host_port.dart';
import 'player_motion_controller.dart';
import 'world_effects.dart';
import 'world_interaction_controller.dart';

/// First-person MVP shell with native relative mouse look and voxel physics.
final class MinedartGame extends FlameGame3D<World3D, FirstPersonCamera>
    with KeyboardEvents, TapCallbacks {
  factory MinedartGame({
    required VoxelWorld world,
    required MeshPipelineBase pipeline,
    GameInputService? input,
    required AudioServiceApi audio,
    Vector3? initialFeet,
    double initialYaw = 0,
    double initialPitch = 0,
  }) {
    final spawnBlockX = WorldDims.worldBlocksX ~/ 2;
    final spawnBlockZ = WorldDims.worldBlocksZ ~/ 2;
    final ground =
        world.skyHeight[spawnBlockX + spawnBlockZ * WorldDims.worldBlocksX];
    final defaultFeet = Vector3(
      spawnBlockX + 0.5,
      ground + 2.0,
      spawnBlockZ + 0.5,
    );
    final player = PlayerMotionController(
      world: world,
      initialFeet: initialFeet ?? defaultFeet,
      initialYaw: initialYaw,
      initialPitch: initialPitch,
    );
    return MinedartGame._(
      world,
      pipeline,
      audio,
      player,
      input ?? GameInputService(),
      input == null,
    );
  }

  MinedartGame._(
    this.voxelWorld,
    this.pipeline,
    this.audio,
    this._player,
    this.input,
    this._ownsInput,
  ) : super(
        camera: FirstPersonCamera(
          following: _player.eyePosition,
          fovY: basePlayerFov,
          position: _player.eyePosition,
        ),
      ) {
    _player.onFootstep = (blockId, seed) => _playAudio(
      AudioCue.forBlock(blockId, BlockAudioAction.step),
      seed: seed,
    );
    diagnostics = DiagnosticsCollector();
  }

  static const _skyColor = Color(0xFF82C8FF);
  static const defaultMouseSensitivity =
      PlayerMotionController.defaultMouseSensitivity;
  static const _performanceSampleCapacity = int.fromEnvironment(
    'MINEDART_PERF_SAMPLE_CAPACITY',
    defaultValue: 240,
  );
  static const _performanceSnapshotIntervalMs = int.fromEnvironment(
    'MINEDART_PERF_SNAPSHOT_INTERVAL_MS',
    defaultValue: 250,
  );

  final VoxelWorld voxelWorld;
  final MeshPipelineBase pipeline;
  final AudioServiceApi audio;
  final PlayerMotionController _player;
  late final WorldInteractionController _interaction =
      WorldInteractionController(
        world: voxelWorld,
        hud: hud,
        effects: CallbackWorldEffects(
          onRemesh: remeshDirty,
          onParticle:
              ({
                required blockId,
                required x,
                required y,
                required z,
                count = 8,
              }) {
                renderer.particles.emitBlock(
                  blockId: blockId,
                  x: x,
                  y: y,
                  z: z,
                  count: count,
                );
              },
          onAudio: (cue, {seed = 0}) => _playAudio(cue, seed: seed),
        ),
      );
  EditHistory get editHistory => _interaction.editHistory;
  WorldTickEngine get worldTicks => _interaction.worldTicks;
  final GameInputService input;
  final bool _ownsInput;
  late final GameInputClient _inputClient = input.createClient(_onMouseEvent);
  final Completer<Object?> _ready = Completer<Object?>();
  final Completer<void> _removed = Completer<void>();
  _GameLifecycle _lifecycle = _GameLifecycle.created;
  ChunkMeshCoordinator? _meshes;
  Future<void> _meshCleanup = Future<void>.value();

  /// Completes on mounted readiness, load failure, or removal during loading.
  Future<Object?> get mountedReady => _ready.future;
  @override
  Future<void> get removed => _removed.future;
  Future<void> get meshCleanup => _meshCleanup;
  bool get isSessionDisposed => _terminal;

  bool get _terminal => switch (_lifecycle) {
    _GameLifecycle.failed ||
    _GameLifecycle.removing ||
    _GameLifecycle.removed => true,
    _ => false,
  };
  bool get _resourcesReady => _lifecycle == _GameLifecycle.ready;

  void activateInput() => _inputClient.activate();

  void resumeSession() {
    if (_terminal) throw StateError('Game has been removed');
    if (!_uiInputCaptured) _inputClient.resume();
    resumeEngine();
  }

  Future<void> quiesceSession() {
    pauseEngine();
    _player.clearInput();
    return _inputClient.suspend();
  }

  MinedartGameHostPort? hostPort;

  void setBindings(GameBindings value) {
    _player.setBindings(value);
  }

  void setMouseOptions({required double sensitivity, required bool invertY}) {
    _player.setMouseOptions(sensitivity: sensitivity, invertY: invertY);
  }

  late final VoxelRenderer renderer;
  late final ChunkRenderManager chunks;
  late final Flame3dCameraControls _cameraControls = Flame3dCameraControls(
    camera,
  );
  RenderLabBridge? _renderLab;
  RenderLabBridge get renderLab => _renderLab!;
  final FrameMetrics frameMetrics = FrameMetrics(
    capacity: _performanceSampleCapacity,
  );
  late final _performancePublisher = frameMetrics.createPublisher(
    interval: const Duration(milliseconds: _performanceSnapshotIntervalMs),
  );
  final Stopwatch _performanceClock = Stopwatch()..start();
  bool _mouseCaptureUnavailable = false;
  bool _hadMouseCapture = false;
  bool _mouseCapturePending = false;
  bool _uiInputCaptured = false;
  bool _appForeground = true;
  bool _simulationPaused = false;
  int _renderDistanceChunks = 6;

  bool get simulationPaused => _simulationPaused;
  set simulationPaused(bool paused) {
    if (_simulationPaused == paused) return;
    _simulationPaused = paused;
    if (paused) _player.touchInput.reset();
  }

  void setRenderDistanceChunks(int chunks) {
    final next = chunks.clamp(2, WorldDims.worldChunksX);
    if (_renderDistanceChunks == next) return;
    _renderDistanceChunks = next;
    if (isLoaded) _updateChunkView(force: true);
  }

  void setRenderStyle({
    required int debugView,
    required double fogDensity,
    required bool ambientOcclusion,
  }) {
    renderer.material.setRenderStyle(
      debugView: debugView,
      fogDensity: fogDensity,
      ambientOcclusion: ambientOcclusion,
    );
  }

  /// HUD model shared with the Flutter overlay.
  final HudState hud = HudState();
  late final DiagnosticsCollector diagnostics;

  /// Scratch look direction, reused to keep the click path allocation-free.
  final Vector3 _lookDirection = Vector3(0, 0, -1);

  /// Eye position the camera follows.
  Vector3 get eyePosition => _player.eyePosition;
  Vector3 get playerFeet => _player.body.position;
  Vector3 get playerMapPosition =>
      _player.noclip ? _player.eyePosition : _player.body.position;
  Vector3 get spawnFeet => _player.spawnFeet;
  double get cameraYaw => _player.yaw;
  double get cameraPitch => _player.pitch;
  bool get isSprinting => _player.isSprinting;

  /// Enables the touch source without changing desktop pointer-lock input.
  void setTouchControlsEnabled(bool enabled) {
    if (_terminal) {
      _player.touchInput.setEnabled(false);
      return;
    }
    _player.touchInput.setEnabled(enabled);
  }

  void setTouchMovement({required double forward, required double strafe}) {
    if (_acceptsTouchInput) {
      _player.touchInput.setMovement(forward: forward, strafe: strafe);
    }
  }

  void setTouchJumpHeld(bool held) {
    if (_acceptsTouchInput) _player.touchInput.setJumpHeld(held);
  }

  void requestTouchJump() {
    if (_acceptsTouchInput) _player.touchInput.requestJump();
  }

  void setTouchSprintHeld(bool held) {
    if (_acceptsTouchInput) _player.touchInput.setSprintHeld(held);
  }

  void addTouchLookDelta(double dx, double dy) {
    if (_acceptsTouchInput) _player.touchInput.addLookDelta(dx, dy);
  }

  void requestTouchBreak() {
    if (_acceptsTouchInput) _player.touchInput.requestBreak();
  }

  void requestTouchPlace() {
    if (_acceptsTouchInput) _player.touchInput.requestPlace();
  }

  void resetTouchInput() => _player.touchInput.reset();

  /// Clears held input before a browser tab can suspend this game loop.
  void setAppForeground(bool foreground) {
    _appForeground = foreground;
    if (!foreground) _player.touchInput.reset();
  }

  bool get _acceptsTouchInput =>
      !_terminal &&
      _resourcesReady &&
      _player.touchInput.enabled &&
      _inputClient.isActive &&
      _appForeground &&
      !_uiInputCaptured &&
      !simulationPaused &&
      !paused;

  /// Look direction derived from the camera orientation.
  Vector3 get lookDirection =>
      _cameraControls.lookDirectionInto(_lookDirection);

  /// Block edits are gated on pointer capture so the click that grabs the
  /// mouse does not also break a block. Platforms without the native bridge
  /// fall back to always-on interaction.
  bool get interactionEnabled =>
      _canInteract(_WorldInteractionSource.capturedPointer);

  bool _canInteract(_WorldInteractionSource source) => switch (source) {
    _WorldInteractionSource.capturedPointer =>
      !_terminal &&
          _inputClient.isActive &&
          !_uiInputCaptured &&
          (_inputClient.isCaptured || _mouseCaptureUnavailable),
    _WorldInteractionSource.touchControls => _acceptsTouchInput,
  };

  void setUiInputCaptured(bool captured) {
    if (_uiInputCaptured == captured) return;
    _uiInputCaptured = captured;
    _player.keys.clear();
    if (captured) _player.touchInput.reset();
    _player.sprintDetector.reset();
    if (captured) {
      unawaited(_releaseMouse().catchError(_reportInputError));
    } else if (!paused && !_terminal) {
      try {
        _inputClient.resume();
      } catch (error, stack) {
        _reportInputError(error, stack);
      }
    }
  }

  /// Waits until the platform cursor is released before a modal route opens.
  ///
  /// [setUiInputCaptured] remains synchronous for widget lifecycle callbacks;
  /// modal integration uses this barrier to prevent a pending native capture
  /// from surviving into the first interactive modal frame.
  Future<void> awaitUiInputRelease() => _releaseMouse();

  /// Left click: break the block under the crosshair.
  void breakTargetBlock() {
    _breakTargetBlock(_WorldInteractionSource.capturedPointer);
  }

  void _breakTargetBlock(_WorldInteractionSource source) {
    if (!_canInteract(source)) return;
    _interaction.breakTarget(eyePosition, lookDirection);
  }

  /// Right click: place the selected hotbar block against the targeted face.
  void placeSelectedBlock() {
    _placeSelectedBlock(_WorldInteractionSource.capturedPointer);
  }

  void _placeSelectedBlock(_WorldInteractionSource source) {
    if (!_canInteract(source)) return;
    _interaction.placeSelected(eyePosition, lookDirection, hud.selectedBlock);
  }

  @override
  Color backgroundColor() => _skyColor;

  @override
  Future<void> onLoad() async {
    if (_terminal) return;
    _lifecycle = _GameLifecycle.loading;
    try {
      await super.onLoad();
      if (_terminal) return;
      _cameraControls.setOrientation(_player.yaw, _player.pitch);
      images.prefix = 'assets/';
      final renderer = await Flame3dVoxelRenderer.load(
        world: world,
        camera: _cameraControls,
        images: images,
        atlasAssetPath: selectedAtlas.assetPath,
      );
      if (_terminal) return;
      this.renderer = renderer;
      chunks = ChunkRenderManager(
        passes: renderer.chunkPasses,
        resourceBudget: diagnostics.budget,
      );
      _renderLab = RenderLabBridge(
        capabilities: renderer.capabilities,
        fogTarget: VoxelMaterialFogTarget(renderer.material),
        targetOutline: renderer.targetOutline,
        particlePool: renderer.particles,
        camera: renderer.camera,
        frameMetrics: frameMetrics,
      );
      renderer.attach();

      _meshes = ChunkMeshCoordinator(
        world: voxelWorld,
        pipeline: pipeline,
        chunks: chunks,
        deferSnapshotCapture: kIsWeb,
        onMainThreadMeshTime: frameMetrics.telemetry.accumulateMainThreadMesh,
        onFailure: _reportMeshFailure,
      )..start();
      _lifecycle = _GameLifecycle.ready;
      diagnostics.updateState(
        rendererReady: true,
        inputActive: _inputClient.isActive,
      );
      diagnostics.updatePerformance(frameMetrics.snapshot());
      diagnostics.publish();
      _interaction.initialize();
      _updateChunkView(force: true);
    } catch (error) {
      if (_lifecycle != _GameLifecycle.removing &&
          _lifecycle != _GameLifecycle.removed) {
        _lifecycle = _GameLifecycle.failed;
      }
      if (!_ready.isCompleted) _ready.complete(error);
      rethrow;
    }
  }

  @override
  void onMount() {
    if (_terminal) return;
    super.onMount();
    if (_ownsInput) {
      activateInput();
      resumeSession();
    }
    if (!_ready.isCompleted) _ready.complete(null);
  }

  @override
  void onRemove() {
    disposeSessionResources();
    super.onRemove();
    if (!_removed.isCompleted) _removed.complete();
  }

  /// Safe for factory failure before mounting and for repeated host teardown.
  void disposeSessionResources() {
    if (_lifecycle == _GameLifecycle.removing ||
        _lifecycle == _GameLifecycle.removed) {
      return;
    }
    _lifecycle = _GameLifecycle.removing;
    pauseEngine();
    _player.touchInput
      ..reset()
      ..setEnabled(false);
    if (!_ready.isCompleted) _ready.complete(StateError('Game was removed'));
    _meshCleanup = _meshes?.close() ?? Future<void>.value();
    _inputClient.dispose();
    _renderLab?.dispose();
    hud.dispose();
    diagnostics.dispose();
    if (_ownsInput) unawaited(input.close().catchError(_reportInputError));
    _lifecycle = _GameLifecycle.removed;
  }

  void _reportMeshFailure(Object error, StackTrace stack) {
    if (_terminal) return;
    if (error is MeshPipelineFailure) {
      hud.recordAction('mesh failed: ${error.chunkIndex}');
    }
    debugPrint('Chunk meshing failed: $error\n$stack');
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (event.deviceKind == PointerDeviceKind.mouse) requestMouseCapture();
  }

  /// Requests relative mouse input from a pointer event that hit the game.
  /// UI overlays never call this, so their clicks cannot recapture the cursor.
  void requestMouseCapture() {
    if (_terminal || _uiInputCaptured || _mouseCapturePending) return;
    _mouseCapturePending = true;
    final request = _captureMouse();
    unawaited(request.whenComplete(() => _mouseCapturePending = false));
  }

  void _updateChunkView({bool force = false}) => _meshes?.updateView(
    playerX: _player.eyePosition.x,
    playerY: _player.eyePosition.y,
    playerZ: _player.eyePosition.z,
    renderDistanceChunks: _renderDistanceChunks,
    force: force,
  );

  int get _meshQueueCount => _meshes?.pendingCount ?? pipeline.pendingCount;

  void _updateMeshActivity(TouchInputFrame touch) {
    final hasImmediateInput =
        _player.hasPendingLook ||
        _hasInteractiveKeyInput ||
        touch.hasImmediateInput;
    if (hasImmediateInput) {
      pipeline.activity = MeshPipelineActivity.interactive;
    } else if (_player.body.velocity.length2 > 0.01) {
      pipeline.activity = MeshPipelineActivity.moving;
    } else if (_meshQueueCount > 0) {
      pipeline.activity = MeshPipelineActivity.loading;
    } else {
      pipeline.activity = MeshPipelineActivity.idle;
    }
  }

  bool get _hasInteractiveKeyInput => _player.hasInteractiveKeyInput;

  /// Re-mesh the given dirty chunk indices (after a block edit).
  void remeshDirty(Set<int> dirtyChunks) {
    _meshes?.remeshDirty(
      dirtyChunks,
      playerX: _player.eyePosition.x,
      playerY: _player.eyePosition.y,
      playerZ: _player.eyePosition.z,
    );
    hostPort?.worldChanged();
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (_uiInputCaptured) return KeyEventResult.ignored;
    if (event is KeyDownEvent && _isMovementKey(event.logicalKey)) {
      _reportMovementActivity();
    }
    _player.updateKeyState(event, keysPressed);
    // Flutter UI shortcuts live in the ancestor CallbackShortcuts. Returning
    // ignored here lets E/F3/Escape bubble out of Flame's focused game node
    // on macOS while browser Pointer Lock still handles consumed Escape.
    if (_isUiShortcut(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      final command = _hasCommandModifier(keysPressed);
      final shift =
          keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          keysPressed.contains(LogicalKeyboardKey.shiftRight);
      if (command && event.logicalKey == LogicalKeyboardKey.keyZ) {
        shift ? _redoWorldEdit() : _undoWorldEdit();
      } else if (command && event.logicalKey == LogicalKeyboardKey.keyY) {
        _redoWorldEdit();
      } else if (event.logicalKey == _player.binding(GameControl.storeSpawn)) {
        _setSpawnAtPlayer();
      } else if (event.logicalKey == _player.binding(GameControl.respawn)) {
        _respawnAtSavedPoint();
      } else if (event.logicalKey == _player.binding(GameControl.cycleFog)) {
        final update = renderLab.cycleFogPreset();
        hostPort?.fogPresetChanged(update.settings.fogPreset);
        setRenderDistanceChunks(update.settings.fogPreset.renderDistanceChunks);
        hud.recordAction(
          update.status == RenderLabUpdateStatus.unsupported
              ? 'fog unsupported'
              : 'fog ${update.settings.fogPreset.name}',
        );
      } else if (event.logicalKey ==
          _player.binding(GameControl.toggleNoclip)) {
        _toggleNoclip();
      } else {
        _handleHudKeyDown(event.logicalKey);
      }
    }
    return KeyEventResult.handled;
  }

  bool _isUiShortcut(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.escape ||
      key == _player.binding(GameControl.openInventory) ||
      key == _player.binding(GameControl.debugOverlay);

  bool _isMovementKey(LogicalKeyboardKey key) => _player.isMovementKey(key);

  void _reportMovementActivity() => hostPort?.movementActivity();

  static bool _hasCommandModifier(Set<LogicalKeyboardKey> keys) =>
      keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight) ||
      keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);

  void _handleHudKeyDown(LogicalKeyboardKey key) {
    final slot = hotbarSlotForKey(key);
    if (slot != null) hud.selectSlot(slot);
  }

  /// Maps digit keys 1-9 to hotbar slots 0-8; null for anything else.
  static int? hotbarSlotForKey(LogicalKeyboardKey key) {
    const digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final index = digits.indexOf(key);
    return index < 0 ? null : index;
  }

  @override
  void update(double dt) {
    if (_terminal || !_resourcesReady) return;
    final touch = _player.consumeTouchFrame();
    final telemetry = frameMetrics.telemetry;
    telemetry.recordWallFrame(dt * 1000);
    telemetry.startTiming(PerformanceMetric.update);
    try {
      _updateMeshActivity(touch);
      _meshes?.drainPendingCaptures();
      if (_player.updateLook(dt, touch)) {
        _reportMovementActivity();
        _cameraControls.setOrientation(_player.yaw, _player.pitch);
      }
      _applyTouchActions(touch);
      if (!simulationPaused) {
        _player.updateMovement(dt, touch);
        if (touch.hasImmediateInput ||
            _player.hasInteractiveKeyInput ||
            _player.body.velocity.length2 > 0.01) {
          _reportMovementActivity();
        }
        _interaction.advance(dt);
      }
      _cameraControls.fovY = stepSprintFov(
        current: _cameraControls.fovY,
        sprinting: isSprinting,
        reducedMotion: renderLab.settings.reducedMotion,
        dt: dt,
      );
      _updateChunkView();
      _publishPlayerViewIfChanged();
      hud.recordFrame(
        dt,
        _player.eyePosition.x,
        _player.eyePosition.y,
        _player.eyePosition.z,
        visibleChunks: chunks.visibleChunkCount,
        loadedChunks: chunks.loadedChunkCount,
        meshQueue: _meshQueueCount,
        renderDistance: _renderDistanceChunks,
        sprinting: isSprinting,
      );
      _updateTargetOutline();
      super.update(dt);
      if (telemetry.pendingMainThreadMeshMs > 0) {
        telemetry.consumeMainThreadMesh();
      }
    } finally {
      telemetry.stopAndRecordTiming(PerformanceMetric.update);
    }
  }

  double _lastViewX = double.nan;
  double _lastViewZ = double.nan;
  double _lastViewHeading = double.nan;

  void _publishPlayerViewIfChanged() {
    final x = playerMapPosition.x;
    final z = playerMapPosition.z;
    final heading = cameraYaw;
    if (x == _lastViewX && z == _lastViewZ && heading == _lastViewHeading) {
      return;
    }
    _lastViewX = x;
    _lastViewZ = z;
    _lastViewHeading = heading;
    hostPort?.playerViewChanged();
  }

  @override
  void render(Canvas canvas) {
    if (_terminal || !_resourcesReady) return;
    final telemetry = frameMetrics.telemetry;
    telemetry.startTiming(PerformanceMetric.cpuRender);
    try {
      super.render(canvas);
    } finally {
      telemetry.stopAndRecordTiming(PerformanceMetric.cpuRender);
    }
    if (isLoaded) _publishPerformanceSnapshot();
  }

  void _publishPerformanceSnapshot() {
    final context = buildContext;
    final devicePixelRatio = context == null
        ? 0.0
        : MediaQuery.devicePixelRatioOf(context);
    final counters = renderer.frameCounters;
    frameMetrics.updateSnapshotFields(
      drawCount: counters.drawCount,
      meshQueue: _meshQueueCount,
      devicePixelRatio: devicePixelRatio,
      effectiveTargetWidth: (size.x * devicePixelRatio).toInt(),
      effectiveTargetHeight: (size.y * devicePixelRatio).toInt(),
      retainedComponentCount: chunks.retainedComponentCount,
      retainedMeshBytes: chunks.retainedMeshBytes,
      uniformUploadHits: counters.uniformUploadHits ?? 0,
      uniformUploadMisses: counters.uniformUploadMisses ?? 0,
      bindGroupHits: counters.bindGroupHits ?? 0,
      bindGroupMisses: counters.bindGroupMisses ?? 0,
    );
    diagnostics.updateState(
      inputActive: _inputClient.isActive,
      rendererReady: _resourcesReady,
      activeChunks: chunks.loadedChunkCount,
    );
    final snapshot = _performancePublisher.publishIfDue(
      elapsedMicroseconds: _performanceClock.elapsedMicroseconds,
    );
    if (snapshot != null) {
      hud.updatePerformanceSnapshot(snapshot);
      diagnostics.updatePerformance(snapshot);
      diagnostics.publish();
    }
  }

  void _updateTargetOutline() {
    final hit = _interaction.interactor.target(eyePosition, lookDirection);
    if (hit == null) {
      renderer.targetOutline.hide();
    } else {
      renderer.targetOutline.showAt(hit.x, hit.y, hit.z);
    }
  }

  void _undoWorldEdit() {
    _interaction.undo();
  }

  void _redoWorldEdit() {
    _interaction.redo();
  }

  void _applyTouchActions(TouchInputFrame touch) {
    for (var request = 0; request < touch.breakRequests; request++) {
      _breakTargetBlock(_WorldInteractionSource.touchControls);
    }
    for (var request = 0; request < touch.placeRequests; request++) {
      _placeSelectedBlock(_WorldInteractionSource.touchControls);
    }
  }

  void _onMouseEvent(MouseLookEvent event) {
    if (_terminal) return;
    switch (event) {
      case MouseDelta(:final dx, :final dy):
        if (dx != 0 || dy != 0) _reportMovementActivity();
        _player.addMouseDelta(dx, dy);
      case MouseCaptureChanged(:final captured):
        final userReleasedWebCapture =
            kIsWeb && _hadMouseCapture && !captured && !_uiInputCaptured;
        _hadMouseCapture = captured;
        if (!captured) {
          _player.keys.clear();
          _player.sprintDetector.reset();
        }
        // Browsers consume Escape while leaving Pointer Lock, so Flutter does
        // not reliably receive the key event. Treat an unexpected lock loss as
        // the web equivalent of Escape; programmatic modal releases are
        // ignored because setUiInputCaptured(true) happens first.
        if (userReleasedWebCapture) hostPort?.pauseRequested();
      case MousePrimaryPressed():
        breakTargetBlock();
      case MouseSecondaryPressed():
        placeSelectedBlock();
    }
  }

  Future<void> _captureMouse() async {
    try {
      await _inputClient.capture();
      if (!_terminal) _mouseCaptureUnavailable = false;
    } on MissingPluginException catch (error) {
      if (!_terminal) _mouseCaptureUnavailable = true;
      debugPrint('Mouse capture unsupported: $error');
    } catch (error, stack) {
      _reportInputError(error, stack);
    }
  }

  Future<void> _releaseMouse() => _inputClient.suspend();

  static void _reportInputError(Object error, StackTrace stack) {
    debugPrint('Mouse input failed: $error\n$stack');
  }

  void _playAudio(AudioCue cue, {int seed = 0}) {
    try {
      unawaited(audio.play(cue, seed: seed).catchError(_reportAudioError));
    } catch (error, stack) {
      _reportAudioError(error, stack);
    }
  }

  static void _reportAudioError(Object error, StackTrace stack) {
    debugPrint('Audio playback failed: $error\n$stack');
  }

  void _toggleNoclip() {
    _player.toggleNoclip();
    hud.recordAction(_player.noclip ? 'noclip on' : 'noclip off');
  }

  void _setSpawnAtPlayer() {
    _player.setSpawnAtPlayer();
    hud.recordAction('teleport saved');
  }

  void _respawnAtSavedPoint() {
    _player.respawnAtSavedPoint();
    hud.recordAction('teleported');
  }
}

enum _WorldInteractionSource { capturedPointer, touchControls }

enum _GameLifecycle { created, loading, ready, failed, removing, removed }
