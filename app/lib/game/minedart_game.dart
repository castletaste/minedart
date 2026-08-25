import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Canvas;

import 'package:flame/events.dart';
import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/game.dart';
import 'package:flame_3d/resources.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, MediaQuery;
import 'package:minedart_core/minedart_core.dart';

import '../assets/atlas_selection.dart';
import '../audio/audio.dart';
import '../input/browser_pointer_lock.dart';
import '../input/double_tap_sprint_detector.dart';
import '../input/game_bindings.dart';
import '../input/mouse_look.dart';
import '../input/player_input_mapper.dart';
import '../input/sprint_fov.dart';
import '../hud/hud_state.dart';
import '../interact/block_interactor.dart';
import '../pipeline/mesh_pipeline.dart';
import '../pipeline/mesh_request_queue.dart';
import '../performance/performance.dart';
import '../render/chunk_render_manager.dart';
import '../render/voxel_material.dart';
import '../showcase/render/showcase_render.dart';

/// First-person MVP shell with native relative mouse look and voxel physics.
final class MinedartGame extends FlameGame3D<World3D, FirstPersonCamera>
    with KeyboardEvents, TapCallbacks {
  factory MinedartGame({
    required VoxelWorld world,
    required MeshPipeline pipeline,
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
    final body = PlayerBody(position: initialFeet?.clone() ?? defaultFeet);
    final eyePosition = Vector3.zero();
    body.writeEyePosition(eyePosition);
    return MinedartGame._(
      world,
      pipeline,
      audio,
      body,
      eyePosition,
      body.position.clone(),
      initialYaw,
      initialPitch,
    );
  }

  MinedartGame._(
    this.voxelWorld,
    this.pipeline,
    this.audio,
    this._playerBody,
    this._eyePosition,
    this._spawnFeet,
    this._yaw,
    this._pitch,
  ) : super(
        camera: FirstPersonCamera(
          following: _eyePosition,
          fovY: basePlayerFov,
          position: _eyePosition,
        ),
      );

  static const _skyColor = Color(0xFF82C8FF);
  static const _noclipSpeed = 24.0;
  static const _keyboardLookSpeed = 1.35;
  static const defaultMouseSensitivity = 0.004;
  static const _pitchLimit = 89 * math.pi / 180;
  static const _performanceSampleCapacity = int.fromEnvironment(
    'MINEDART_PERF_SAMPLE_CAPACITY',
    defaultValue: 240,
  );
  static const _performanceSnapshotIntervalMs = int.fromEnvironment(
    'MINEDART_PERF_SNAPSHOT_INTERVAL_MS',
    defaultValue: 250,
  );

  final VoxelWorld voxelWorld;
  final MeshPipeline pipeline;
  final AudioServiceApi audio;
  final PlayerBody _playerBody;
  final Vector3 _eyePosition;
  final Vector3 _spawnFeet;
  final PhysicsSim _physics = PhysicsSim();
  final EditHistory editHistory = EditHistory();
  final WorldTickEngine worldTicks = WorldTickEngine();
  final MouseLook _mouseLook = MouseLook();
  final BrowserPointerLock _browserPointerLock = BrowserPointerLock();
  final DoubleTapSprintDetector _sprintDetector = DoubleTapSprintDetector();
  final FootstepCadence _footstepCadence = FootstepCadence();
  final Set<LogicalKeyboardKey> _keys = <LogicalKeyboardKey>{};
  int _footstepSerial = 0;
  GameBindings _bindings = GameBindings();
  double _mouseSensitivity = defaultMouseSensitivity;
  bool _invertMouseY = false;

  void Function()? onPauseRequested;
  void Function()? onFirstMovementInput;
  void Function(FogPreset preset)? onFogPresetChanged;
  bool _reportedFirstMovementInput = false;

  void setBindings(GameBindings value) {
    _bindings = value.copy();
    _keys.clear();
    _sprintDetector.reset();
  }

  void setMouseOptions({required double sensitivity, required bool invertY}) {
    _mouseSensitivity = sensitivity.clamp(0.0005, 0.02);
    _invertMouseY = invertY;
  }

  /// Monotonic mesh generation per chunk index. Guarantees stale remesh
  /// results are dropped even when a border edit dirties a neighbor chunk
  /// without bumping that chunk's own revision (see cross-review P1).
  final Map<int, int> _meshGeneration = <int, int>{};

  ChunkSnapshot _snapshotFor(Chunk chunk, int generation) {
    final raw = ChunkSnapshot.capture(voxelWorld, chunk.cx, chunk.cy, chunk.cz);
    return ChunkSnapshot.fromBuffers(
      cx: raw.cx,
      cy: raw.cy,
      cz: raw.cz,
      revision: generation,
      blocks: raw.blocks,
      skyHeight: raw.skyHeight,
    );
  }

  late final ChunkRenderManager chunks;
  late final VoxelMaterialControls voxelMaterial;
  late final TargetOutline targetOutline;
  late final BlockParticlePool particlePool;
  late final RenderLabBridge renderLab;
  final FrameMetrics frameMetrics = FrameMetrics(
    capacity: _performanceSampleCapacity,
  );
  late final _performancePublisher = frameMetrics.createPublisher(
    interval: const Duration(milliseconds: _performanceSnapshotIntervalMs),
  );
  final Stopwatch _performanceClock = Stopwatch()..start();
  StreamSubscription<ChunkMeshData>? _meshSub;
  StreamSubscription<MouseLookEvent>? _mouseSub;
  StreamSubscription<MouseLookEvent>? _browserMouseSub;
  double _yaw;
  double _pitch;
  double _pendingMouseDx = 0;
  double _pendingMouseDy = 0;
  bool _noclip = false;
  bool _mouseCaptureUnavailable = false;
  bool _hadMouseCapture = false;
  bool _mouseCapturePending = false;
  bool _uiInputCaptured = false;
  bool simulationPaused = false;
  int _renderDistanceChunks = 6;
  int _viewChunkX = -1;
  int _viewChunkZ = -1;
  final Set<int> _requestedChunks = <int>{};
  final MeshRequestQueue _pendingMeshCaptures = MeshRequestQueue();
  final Stopwatch _meshCaptureStopwatch = Stopwatch();
  final Stopwatch _meshApplyStopwatch = Stopwatch();
  double _worldTickAccumulator = 0;
  bool _suppressPrimedTickHistory = false;
  static const double _worldTickStep = 0.05;
  static const int _worldTickBudget = 256;

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
    voxelMaterial.setRenderStyle(
      debugView: debugView,
      fogDensity: fogDensity,
      ambientOcclusion: ambientOcclusion,
    );
  }

  /// HUD model shared with the Flutter overlay.
  final HudState hud = HudState();

  late final BlockInteractor interactor = BlockInteractor(
    world: voxelWorld,
    onDirty: remeshDirty,
  );

  /// Scratch look direction, reused to keep the click path allocation-free.
  final Vector3 _lookDirection = Vector3(0, 0, -1);

  /// Eye position the camera follows.
  Vector3 get eyePosition => _eyePosition;
  Vector3 get playerFeet => _playerBody.position;
  Vector3 get playerMapPosition =>
      _noclip ? _eyePosition : _playerBody.position;
  Vector3 get spawnFeet => _spawnFeet;
  double get cameraYaw => _yaw;
  double get cameraPitch => _pitch;
  bool get isSprinting => _sprintDetector.isSprinting;

  /// Look direction derived from the camera rotation quaternion.
  Vector3 get lookDirection => _lookDirection
    ..setValues(0, 0, -1)
    ..applyQuaternion(camera.rotation);

  /// Block edits are gated on pointer capture so the click that grabs the
  /// mouse does not also break a block. Platforms without the native bridge
  /// fall back to always-on interaction.
  bool get interactionEnabled =>
      !_uiInputCaptured &&
      (kIsWeb
          ? _browserPointerLock.isLocked
          : _mouseLook.isCaptured || _mouseCaptureUnavailable);

  void setUiInputCaptured(bool captured) {
    if (_uiInputCaptured == captured) return;
    _uiInputCaptured = captured;
    _keys.clear();
    _sprintDetector.reset();
    if (captured) unawaited(_releaseMouse());
  }

  /// Waits until the platform cursor is released before a modal route opens.
  ///
  /// [setUiInputCaptured] remains synchronous for widget lifecycle callbacks;
  /// modal integration uses this barrier to prevent a pending native capture
  /// from surviving into the first interactive modal frame.
  Future<void> awaitUiInputRelease() => _releaseMouse();

  /// Left click: break the block under the crosshair.
  void breakTargetBlock() {
    if (!interactionEnabled) return;
    final hit = interactor.target(eyePosition, lookDirection);
    final brokenBlockId = hit == null
        ? Blocks.air
        : Blocks.id(voxelWorld.blockAt(hit.x, hit.y, hit.z));
    if (hit != null && brokenBlockId == Blocks.tnt) {
      if (worldTicks.activateTnt(voxelWorld, hit.x, hit.y, hit.z)) {
        _beginUserCascade();
        hud.recordAction('tnt fuse ${hit.x}/${hit.y}/${hit.z}');
        unawaited(
          audio.play(
            AudioCue.tntFuse,
            seed: _editAudioSeed(hit.x, hit.y, hit.z),
          ),
        );
      }
      return;
    }
    final result = interactor.breakBlock(eyePosition, lookDirection);
    hud.recordAction(
      result.changed
          ? 'broke ${result.x}/${result.y}/${result.z}'
          : 'break none',
    );
    if (result.changed) {
      _recordUserEdit(result.changeSet);
      particlePool.emitBlock(
        blockId: brokenBlockId,
        x: result.x,
        y: result.y,
        z: result.z,
      );
      unawaited(
        audio.play(
          AudioCue.forBlock(brokenBlockId, BlockAudioAction.breakBlock),
          seed: _editAudioSeed(result.x, result.y, result.z),
        ),
      );
    }
  }

  /// Right click: place the selected hotbar block against the targeted face.
  void placeSelectedBlock() {
    if (!interactionEnabled) return;
    final result = interactor.placeBlock(
      eyePosition,
      lookDirection,
      hud.selectedBlock,
    );
    hud.recordAction(
      result.changed
          ? 'placed ${result.x}/${result.y}/${result.z}'
          : 'place none',
    );
    if (result.changed) {
      _recordUserEdit(result.changeSet);
      particlePool.emitBlock(
        blockId: result.blockId,
        x: result.x,
        y: result.y,
        z: result.z,
        count: 3,
      );
      unawaited(
        audio.play(
          AudioCue.forBlock(result.blockId, BlockAudioAction.placeBlock),
          seed: _editAudioSeed(result.x, result.y, result.z),
        ),
      );
    }
  }

  static int _editAudioSeed(int x, int y, int z) =>
      x * 73856093 ^ y * 19349663 ^ z * 83492791;

  @override
  Color backgroundColor() => _skyColor;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera
      ..resetRotation()
      ..rotate(_yaw, _pitch);
    images.prefix = 'assets/';
    final atlas = await images.loadTexture(selectedAtlas.assetPath);
    // Web uses a compact WGSL cutout material; macOS keeps fog support.
    final Material material;
    if (kIsWeb) {
      final webMaterial = WebVoxelMaterial(albedoTexture: atlas);
      voxelMaterial = webMaterial;
      material = webMaterial;
    } else {
      final nativeMaterial = VoxelMaterial(albedoTexture: atlas);
      voxelMaterial = nativeMaterial;
      material = nativeMaterial;
    }
    chunks = ChunkRenderManager(world: world, material: material);

    targetOutline = TargetOutline()..hide();
    particlePool = BlockParticlePool();
    renderLab = RenderLabBridge(
      capabilities: kIsWeb ? RenderCapabilities.web : RenderCapabilities.native,
      fogTarget: VoxelMaterialFogTarget(voxelMaterial),
      targetOutline: targetOutline,
      particlePool: particlePool,
      camera: camera,
      frameMetrics: frameMetrics,
    );

    world.addAll([
      LightComponent.ambient(intensity: 1.0),
      targetOutline,
      particlePool,
    ]);

    _meshSub = pipeline.results.listen(_applyMeshResult);
    pipeline.onMainThreadMeshTime =
        frameMetrics.telemetry.accumulateMainThreadMesh;
    if (!kIsWeb) {
      _mouseSub = _mouseLook.events.listen(
        _onMouseEvent,
        onError: (Object error) => debugPrint('Mouse input error: $error'),
      );
      _mouseLook.start();
    }
    _browserMouseSub = _browserPointerLock.events.listen(_onMouseEvent);
    worldTicks.prime(voxelWorld);
    _suppressPrimedTickHistory = !worldTicks.isIdle;
    _updateChunkView(force: true);
  }

  @override
  void onRemove() {
    _meshSub?.cancel();
    _mouseSub?.cancel();
    _browserMouseSub?.cancel();
    _browserPointerLock.dispose();
    pipeline.onMainThreadMeshTime = null;
    _pendingMeshCaptures.dispose();
    unawaited(_mouseLook.close());
    renderLab.dispose();
    hud.dispose();
    super.onRemove();
  }

  @override
  void onTapDown(TapDownEvent event) {
    requestMouseCapture();
  }

  /// Requests relative mouse input from a pointer event that hit the game.
  /// UI overlays never call this, so their clicks cannot recapture the cursor.
  void requestMouseCapture() {
    if (_uiInputCaptured || _mouseCapturePending) return;
    _mouseCapturePending = true;
    final request = kIsWeb ? _captureBrowserMouse() : _captureMouse();
    unawaited(request.whenComplete(() => _mouseCapturePending = false));
  }

  void _updateChunkView({bool force = false}) {
    final cx = (_eyePosition.x ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksX - 1,
    );
    final cz = (_eyePosition.z ~/ WorldDims.chunkSize).clamp(
      0,
      WorldDims.worldChunksZ - 1,
    );
    if (!force && cx == _viewChunkX && cz == _viewChunkZ) return;
    _viewChunkX = cx;
    _viewChunkZ = cz;
    if (kIsWeb) {
      _pendingMeshCaptures.setPriorityOrigin(x: cx, y: 0, z: cz);
    }
    chunks.updateVisibility(
      playerX: _eyePosition.x,
      playerZ: _eyePosition.z,
      renderDistanceChunks: _renderDistanceChunks,
    );
    chunks.evictOutsideView(onEvicted: _forgetRequestedChunk);

    final minX = (cx - _renderDistanceChunks).clamp(
      0,
      WorldDims.worldChunksX - 1,
    );
    final maxX = (cx + _renderDistanceChunks).clamp(
      0,
      WorldDims.worldChunksX - 1,
    );
    final minZ = (cz - _renderDistanceChunks).clamp(
      0,
      WorldDims.worldChunksZ - 1,
    );
    final maxZ = (cz + _renderDistanceChunks).clamp(
      0,
      WorldDims.worldChunksZ - 1,
    );
    for (var chunkZ = minZ; chunkZ <= maxZ; chunkZ++) {
      for (var chunkX = minX; chunkX <= maxX; chunkX++) {
        for (var chunkY = 0; chunkY < WorldDims.worldChunksY; chunkY++) {
          final index = VoxelWorld.chunkIndexOf(chunkX, chunkY, chunkZ);
          final chunk = voxelWorld.chunks[index];
          if (chunk.isEmpty || !_requestedChunks.add(index)) continue;
          _requestChunk(chunk);
        }
      }
    }
  }

  void _requestChunk(Chunk chunk) {
    final index = VoxelWorld.chunkIndexOf(chunk.cx, chunk.cy, chunk.cz);
    final generation = (_meshGeneration[index] ?? 0) + 1;
    _meshGeneration[index] = generation;
    if (kIsWeb) {
      _pendingMeshCaptures.request(
        chunkIndex: index,
        chunkX: chunk.cx,
        chunkY: chunk.cy,
        chunkZ: chunk.cz,
        generation: generation,
      );
      return;
    }
    _submitChunkSnapshot(chunk, generation);
  }

  void _submitChunkSnapshot(Chunk chunk, int generation) {
    final dx = chunk.cx * WorldDims.chunkSize + 8.0 - _eyePosition.x;
    final dy = chunk.cy * WorldDims.chunkSize + 8.0 - _eyePosition.y;
    final dz = chunk.cz * WorldDims.chunkSize + 8.0 - _eyePosition.z;
    pipeline.request(
      MeshJob(
        snapshot: _snapshotFor(chunk, generation),
        priority: dx * dx + dy * dy + dz * dz,
      ),
    );
  }

  void _applyMeshResult(ChunkMeshData data) {
    if (!chunks.isChunkInView(data.chunkIndex)) {
      _requestedChunks.remove(data.chunkIndex);
      return;
    }
    _meshApplyStopwatch
      ..reset()
      ..start();
    try {
      chunks.apply(data);
    } finally {
      _meshApplyStopwatch.stop();
      frameMetrics.telemetry.accumulateMainThreadMesh(
        _meshApplyStopwatch.elapsedMicroseconds / 1000,
      );
    }
  }

  void _drainPendingMeshCaptures() {
    if (!kIsWeb || _pendingMeshCaptures.isEmpty) return;
    final budget = pipeline.activity.budgetMicroseconds;
    _meshCaptureStopwatch
      ..reset()
      ..start();
    var attempted = false;
    try {
      while (!_pendingMeshCaptures.isEmpty &&
          (!attempted || _meshCaptureStopwatch.elapsedMicroseconds < budget)) {
        final request = _pendingMeshCaptures.takeNext();
        if (request == null) break;
        attempted = true;
        if (!_isChunkInView(request.chunkX, request.chunkZ)) {
          _pendingMeshCaptures.complete(request);
          _requestedChunks.remove(request.chunkIndex);
          continue;
        }
        try {
          _submitChunkSnapshot(
            voxelWorld.chunks[request.chunkIndex],
            request.generation,
          );
        } on Object {
          _pendingMeshCaptures.fail(request);
          continue;
        }
        _pendingMeshCaptures.complete(request);
      }
    } finally {
      _meshCaptureStopwatch.stop();
      if (attempted) {
        frameMetrics.telemetry.accumulateMainThreadMesh(
          _meshCaptureStopwatch.elapsedMicroseconds / 1000,
        );
      }
    }
  }

  int get _meshQueueCount =>
      pipeline.pendingCount + _pendingMeshCaptures.pendingCount;

  bool _isChunkInView(int chunkX, int chunkZ) =>
      (chunkX - _viewChunkX).abs() <= _renderDistanceChunks &&
      (chunkZ - _viewChunkZ).abs() <= _renderDistanceChunks;

  void _forgetRequestedChunk(int chunkIndex) {
    _requestedChunks.remove(chunkIndex);
  }

  void _updateMeshActivity() {
    final hasImmediateInput =
        _pendingMouseDx != 0 || _pendingMouseDy != 0 || _hasInteractiveKeyInput;
    if (hasImmediateInput) {
      pipeline.activity = MeshPipelineActivity.interactive;
    } else if (_playerBody.velocity.length2 > 0.01) {
      pipeline.activity = MeshPipelineActivity.moving;
    } else if (_meshQueueCount > 0) {
      pipeline.activity = MeshPipelineActivity.loading;
    } else {
      pipeline.activity = MeshPipelineActivity.idle;
    }
  }

  bool get _hasInteractiveKeyInput =>
      _keys.contains(_bindings[GameControl.moveForward]) ||
      _keys.contains(_bindings[GameControl.moveBackward]) ||
      _keys.contains(_bindings[GameControl.strafeLeft]) ||
      _keys.contains(_bindings[GameControl.strafeRight]) ||
      _keys.contains(_bindings[GameControl.jump]) ||
      _keys.contains(LogicalKeyboardKey.arrowLeft) ||
      _keys.contains(LogicalKeyboardKey.arrowRight) ||
      _keys.contains(LogicalKeyboardKey.arrowUp) ||
      _keys.contains(LogicalKeyboardKey.arrowDown);

  /// Re-mesh the given dirty chunk indices (after a block edit).
  void remeshDirty(Set<int> dirtyChunks) {
    for (final index in dirtyChunks) {
      final chunk = voxelWorld.chunks[index];
      _requestedChunks.add(index);
      _requestChunk(chunk);
    }
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (_uiInputCaptured) return KeyEventResult.ignored;
    if (event is KeyDownEvent && _isMovementKey(event.logicalKey)) {
      _reportFirstMovementInput();
    }
    _updateSprintState(event);
    // Flutter UI shortcuts live in the ancestor CallbackShortcuts. Returning
    // ignored here lets E/F3/Escape bubble out of Flame's focused game node
    // on macOS while browser Pointer Lock still handles consumed Escape.
    if (_isUiShortcut(event.logicalKey)) {
      _keys
        ..clear()
        ..addAll(keysPressed);
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
      } else if (event.logicalKey == _bindings[GameControl.storeSpawn]) {
        _setSpawnAtPlayer();
      } else if (event.logicalKey == _bindings[GameControl.respawn]) {
        _respawnAtSavedPoint();
      } else if (event.logicalKey == _bindings[GameControl.cycleFog]) {
        final update = renderLab.cycleFogPreset();
        onFogPresetChanged?.call(update.settings.fogPreset);
        setRenderDistanceChunks(switch (update.settings.fogPreset) {
          FogPreset.near => 3,
          FogPreset.normal => 6,
          FogPreset.far => 10,
          FogPreset.off => WorldDims.worldChunksX,
        });
        hud.recordAction(
          update.status == RenderLabUpdateStatus.unsupported
              ? 'fog unsupported'
              : 'fog ${update.settings.fogPreset.name}',
        );
      } else if (event.logicalKey == _bindings[GameControl.toggleNoclip]) {
        _toggleNoclip();
      } else {
        _handleHudKeyDown(event.logicalKey);
      }
    }
    _keys
      ..clear()
      ..addAll(keysPressed);
    return KeyEventResult.handled;
  }

  void _updateSprintState(KeyEvent event) {
    if (event.logicalKey != _bindings[GameControl.moveForward]) return;
    if (event is KeyRepeatEvent) {
      _sprintDetector.forwardDown(event.timeStamp, isRepeat: true);
    } else if (event is KeyDownEvent) {
      _sprintDetector.forwardDown(event.timeStamp, isRepeat: event.synthesized);
    } else if (event is KeyUpEvent) {
      _sprintDetector.forwardUp();
    }
  }

  bool _isUiShortcut(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.escape ||
      key == _bindings[GameControl.openInventory] ||
      key == _bindings[GameControl.debugOverlay];

  bool _isMovementKey(LogicalKeyboardKey key) =>
      key == _bindings[GameControl.moveForward] ||
      key == _bindings[GameControl.moveBackward] ||
      key == _bindings[GameControl.strafeLeft] ||
      key == _bindings[GameControl.strafeRight] ||
      key == _bindings[GameControl.jump];

  void _reportFirstMovementInput() {
    if (_reportedFirstMovementInput) return;
    _reportedFirstMovementInput = true;
    onFirstMovementInput?.call();
  }

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
    final telemetry = frameMetrics.telemetry;
    telemetry.recordWallFrame(dt * 1000);
    telemetry.startTiming(PerformanceMetric.update);
    try {
      _updateMeshActivity();
      _drainPendingMeshCaptures();
      _updateLook(dt);
      if (!simulationPaused) {
        if (_noclip) {
          _updateNoclip(dt);
        } else {
          _updatePhysics(dt);
        }
        _updateWorldSimulation(dt);
      }
      camera.fovY = stepSprintFov(
        current: camera.fovY,
        sprinting: isSprinting,
        reducedMotion: renderLab.settings.reducedMotion,
        dt: dt,
      );
      _updateChunkView();
      hud.recordFrame(
        dt,
        _eyePosition.x,
        _eyePosition.y,
        _eyePosition.z,
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

  @override
  void render(Canvas canvas) {
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
    final cache = world.context.device.lastBindCacheCounters;
    frameMetrics.updateSnapshotFields(
      drawCount: world.context.drawCount,
      meshQueue: _meshQueueCount,
      devicePixelRatio: devicePixelRatio,
      effectiveTargetWidth: (size.x * devicePixelRatio).toInt(),
      effectiveTargetHeight: (size.y * devicePixelRatio).toInt(),
      retainedComponentCount: chunks.retainedComponentCount,
      retainedMeshBytes: chunks.retainedMeshBytes,
      uniformUploadHits: cache?.uniformUploadHits ?? 0,
      uniformUploadMisses: cache?.uniformUploadMisses ?? 0,
      bindGroupHits: cache?.bindGroupHits ?? 0,
      bindGroupMisses: cache?.bindGroupMisses ?? 0,
    );
    final snapshot = _performancePublisher.publishIfDue(
      elapsedMicroseconds: _performanceClock.elapsedMicroseconds,
    );
    if (snapshot != null) hud.updatePerformanceSnapshot(snapshot);
  }

  void _updateTargetOutline() {
    final hit = interactor.target(eyePosition, lookDirection);
    if (hit == null) {
      targetOutline.hide();
    } else {
      targetOutline.showAt(hit.x, hit.y, hit.z);
    }
  }

  void _recordUserEdit(WorldChangeSet? changes) {
    if (changes == null || changes.isEmpty) return;
    _beginUserCascade();
    editHistory.record(changes);
    for (final change in changes.changes) {
      worldTicks.enqueueAround(change.x, change.y, change.z);
    }
  }

  void _beginUserCascade() {
    // A user edit becomes the new history boundary even if bounded load
    // reconvergence is still pending. Its consequences then remain undoable
    // as one cascade instead of leaving the edited topology half-recorded.
    _suppressPrimedTickHistory = false;
    editHistory.beginGroup();
  }

  void _updateWorldSimulation(double dt) {
    _worldTickAccumulator += dt.clamp(0, 0.25);
    var steps = 0;
    while (_worldTickAccumulator >= _worldTickStep && steps < 5) {
      _worldTickAccumulator -= _worldTickStep;
      steps++;
      final changes = worldTicks.tick(voxelWorld, _worldTickBudget);
      if (changes.isNotEmpty) {
        if (!_suppressPrimedTickHistory) editHistory.record(changes);
        remeshDirty(changes.dirtyChunks);
        final exploded = shouldPlayExplosionForWorldChanges(changes.changes);
        var removed = 0;
        for (final change in changes.changes) {
          final oldId = Blocks.id(change.oldRaw);
          if (oldId != Blocks.air && Blocks.id(change.newRaw) == Blocks.air) {
            removed++;
            particlePool.emitBlock(
              blockId: oldId,
              x: change.x,
              y: change.y,
              z: change.z,
              count: 2,
            );
          }
        }
        if (exploded) {
          unawaited(audio.play(AudioCue.explosion, seed: removed));
        }
      }
      if (worldTicks.isIdle) {
        _suppressPrimedTickHistory = false;
        editHistory.endGroup();
      }
    }
  }

  void _undoWorldEdit() {
    worldTicks.clear();
    _suppressPrimedTickHistory = false;
    final changes = editHistory.undo(voxelWorld);
    _applyHistoryResult(changes, 'undo');
  }

  void _redoWorldEdit() {
    worldTicks.clear();
    _suppressPrimedTickHistory = false;
    final changes = editHistory.redo(voxelWorld);
    _applyHistoryResult(changes, 'redo');
  }

  void _applyHistoryResult(WorldChangeSet changes, String action) {
    if (changes.isEmpty) {
      hud.recordAction('$action none');
      return;
    }
    remeshDirty(changes.dirtyChunks);
    hud.recordAction('$action ${changes.changes.length}');
  }

  void _onMouseEvent(MouseLookEvent event) {
    switch (event) {
      case MouseDelta(:final dx, :final dy):
        if (dx != 0 || dy != 0) _reportFirstMovementInput();
        _pendingMouseDx += dx;
        _pendingMouseDy += dy;
      case MouseCaptureChanged(:final captured):
        final userReleasedWebCapture =
            kIsWeb && _hadMouseCapture && !captured && !_uiInputCaptured;
        _hadMouseCapture = captured;
        if (!captured) {
          _keys.clear();
          _sprintDetector.reset();
        }
        // Browsers consume Escape while leaving Pointer Lock, so Flutter does
        // not reliably receive the key event. Treat an unexpected lock loss as
        // the web equivalent of Escape; programmatic modal releases are
        // ignored because setUiInputCaptured(true) happens first.
        if (userReleasedWebCapture) onPauseRequested?.call();
      case MousePrimaryPressed():
        breakTargetBlock();
      case MouseSecondaryPressed():
        placeSelectedBlock();
    }
  }

  Future<void> _captureMouse() async {
    if (_uiInputCaptured) return;
    try {
      final captured = await _mouseLook.capture();
      if (_uiInputCaptured && captured) {
        await _mouseLook.release();
        return;
      }
      // A successful capture proves the native bridge works.
      _mouseCaptureUnavailable = false;
    } on MissingPluginException catch (error) {
      // No native bridge on this platform: allow interaction without capture.
      _mouseCaptureUnavailable = true;
      debugPrint('Mouse capture unsupported: $error');
    } on Object catch (error) {
      // Transient failure (window not focused, CG error): keep the gate.
      debugPrint('Could not capture mouse: $error');
    }
  }

  Future<void> _captureBrowserMouse() async {
    if (_uiInputCaptured) return;
    try {
      await _browserPointerLock.capture();
      if (_uiInputCaptured) _browserPointerLock.release();
    } on Object catch (error) {
      // Pointer Lock can reject when the tab loses focus between pointer-down
      // and the async browser request. It is a recoverable missed capture: the
      // next click retries. Keep release consoles clean while retaining a
      // diagnostic in debug builds.
      if (kDebugMode) debugPrint('Could not capture browser mouse: $error');
    }
  }

  Future<void> _releaseMouse() async {
    if (kIsWeb) {
      _browserPointerLock.release();
      return;
    }
    try {
      await _mouseLook.release();
    } on Object catch (error) {
      debugPrint('Could not release mouse: $error');
    }
  }

  void _updateLook(double dt) {
    var yawDelta = -_pendingMouseDx * _mouseSensitivity;
    // Standard FPS convention: mouse up looks up (macOS deltaY grows
    // downward, so it must be negated).
    var pitchDelta =
        (_invertMouseY ? 1 : -1) * _pendingMouseDy * _mouseSensitivity;
    _pendingMouseDx = 0;
    _pendingMouseDy = 0;

    if (_keys.contains(LogicalKeyboardKey.arrowLeft)) {
      yawDelta += _keyboardLookSpeed * dt;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowRight)) {
      yawDelta -= _keyboardLookSpeed * dt;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowUp)) {
      pitchDelta += _keyboardLookSpeed * dt;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowDown)) {
      pitchDelta -= _keyboardLookSpeed * dt;
    }
    if (yawDelta == 0 && pitchDelta == 0) return;

    _yaw = (_yaw + yawDelta) % (math.pi * 2);
    _pitch = (_pitch + pitchDelta).clamp(-_pitchLimit, _pitchLimit);
    camera
      ..resetRotation()
      ..rotate(_yaw, _pitch);
  }

  void _updatePhysics(double dt) {
    final input = PlayerInputMapper.fromCameraAxes(
      yaw: _yaw,
      forward: _axis(
        _bindings[GameControl.moveForward],
        _bindings[GameControl.moveBackward],
      ),
      strafe: _axis(
        _bindings[GameControl.strafeRight],
        _bindings[GameControl.strafeLeft],
      ),
      jump: _keys.contains(_bindings[GameControl.jump]),
      sprint: _sprintDetector.isSprinting,
    );
    final previousX = _playerBody.position.x;
    final previousZ = _playerBody.position.z;
    _physics.advance(voxelWorld, _playerBody, input, dt);
    final movedX = _playerBody.position.x - previousX;
    final movedZ = _playerBody.position.z - previousZ;
    if (_footstepCadence.update(
      horizontalDistance: math.sqrt(movedX * movedX + movedZ * movedZ),
      grounded: _playerBody.onGround,
      sprinting: _sprintDetector.isSprinting,
    )) {
      _playFootstep();
    }
    _playerBody.writeEyePosition(_eyePosition);
  }

  void _playFootstep() {
    final blockX = _playerBody.position.x.floor();
    final blockY = (_playerBody.position.y - PhysicsSim.collisionEpsilon * 2)
        .floor();
    final blockZ = _playerBody.position.z.floor();
    final blockId = Blocks.id(voxelWorld.blockAt(blockX, blockY, blockZ));
    if (blockId == Blocks.air) return;

    final seed =
        _editAudioSeed(blockX, blockY, blockZ) ^
        (_footstepSerial++ * 0x1F123BB5);
    unawaited(
      audio.play(AudioCue.forBlock(blockId, BlockAudioAction.step), seed: seed),
    );
  }

  void _updateNoclip(double dt) {
    final forwardAxis = _axis(
      _bindings[GameControl.moveForward],
      _bindings[GameControl.moveBackward],
    );
    final strafeAxis = _axis(
      _bindings[GameControl.strafeRight],
      _bindings[GameControl.strafeLeft],
    );
    if (forwardAxis == 0 && strafeAxis == 0) return;

    final sinYaw = math.sin(_yaw);
    final cosYaw = math.cos(_yaw);
    final sinPitch = math.sin(_pitch);
    final cosPitch = math.cos(_pitch);
    var moveX = forwardAxis * -sinYaw * cosPitch + strafeAxis * cosYaw;
    var moveY = forwardAxis * sinPitch;
    var moveZ = forwardAxis * -cosYaw * cosPitch - strafeAxis * sinYaw;
    final length = math.sqrt(moveX * moveX + moveY * moveY + moveZ * moveZ);
    if (length > 1) {
      moveX /= length;
      moveY /= length;
      moveZ /= length;
    }
    final distance = _noclipSpeed * dt;
    _eyePosition
      ..x += moveX * distance
      ..y += moveY * distance
      ..z += moveZ * distance;
    _eyePosition.y = _eyePosition.y
        .clamp(1, WorldDims.worldBlocksY - 1)
        .toDouble();
  }

  double _axis(LogicalKeyboardKey positive, LogicalKeyboardKey negative) {
    return (_keys.contains(positive) ? 1.0 : 0.0) -
        (_keys.contains(negative) ? 1.0 : 0.0);
  }

  void _toggleNoclip() {
    _noclip = !_noclip;
    _footstepCadence.reset();
    _playerBody.velocity.setZero();
    _playerBody.onGround = false;
    if (_noclip) {
      _playerBody.writeEyePosition(_eyePosition);
    } else {
      _playerBody.position.setValues(
        _eyePosition.x,
        _eyePosition.y - PlayerBody.eyeHeight,
        _eyePosition.z,
      );
    }
  }

  void _setSpawnAtPlayer() {
    if (_noclip) {
      _spawnFeet.setValues(
        _eyePosition.x,
        _eyePosition.y - PlayerBody.eyeHeight,
        _eyePosition.z,
      );
    } else {
      _spawnFeet.setFrom(_playerBody.position);
    }
    hud.recordAction('teleport saved');
  }

  void _respawnAtSavedPoint() {
    _footstepCadence.reset();
    _playerBody.position.setFrom(_spawnFeet);
    _playerBody.velocity.setZero();
    _playerBody.onGround = false;
    _playerBody.writeEyePosition(_eyePosition);
    hud.recordAction('teleported');
  }
}
