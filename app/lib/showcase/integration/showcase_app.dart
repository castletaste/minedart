import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minedart_core/minedart_core.dart';

import '../../audio/audio.dart';
import '../../data/worlds/worlds.dart';
import '../../game/minedart_game.dart';
import '../../hud/hud_overlay.dart';
import '../../input/game_bindings.dart';
import '../controller/showcase_controllers.dart';
import '../render/showcase_render.dart' as renderer;
import '../ui/controls_hint.dart';
import '../ui/showcase_ui.dart';
import 'launch_config.dart';
import 'input_capture_coordinator.dart';
import 'minimap_widgets.dart';
import 'world_runtime.dart';
import 'world_presets.dart';

final class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({
    required this.repository,
    required this.audio,
    required this.initialRuntime,
    super.key,
  });

  final WorldRepository repository;
  final AudioServiceApi audio;
  final WorldRuntime initialRuntime;

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

final class _ShowcaseAppState extends State<ShowcaseApp> {
  late WorldRuntime _runtime = widget.initialRuntime;
  late final BuilderStudioController _builder = BuilderStudioController(
    initialHotbar: _runtime.game.hud.blocks,
  );
  late final OptionsController _options = OptionsController();
  late final RenderLabController _renderUi = RenderLabController(
    onChanged: _applyRenderUi,
  );
  final WorldLibraryController _worldLibrary = WorldLibraryController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final ValueNotifier<MinimapViewState> _minimap;
  Timer? _minimapTimer;
  int _minimapTicks = 0;

  bool _gameLoaded = false;
  bool _modalOpen = false;
  bool _switchingWorld = false;
  bool _showStartupControls = true;
  FogPreset? _lastAppliedOptionsFog;
  bool _syncingRenderDistance = false;
  late final InputCaptureCoordinator _inputCapture = InputCaptureCoordinator(
    (captured) => _runtime.game.setUiInputCaptured(captured),
  );

  BuildContext? get _navigatorContext =>
      _navigatorKey.currentState?.overlay?.context;

  @override
  void initState() {
    super.initState();
    _builder.addListener(_syncBuilderToGame);
    _options.addListener(_applyOptions);
    _minimap = ValueNotifier(_createMinimapState());
    _minimapTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _updateMinimap(),
    );
    _attachGame(_runtime.game);
    unawaited(_refreshWorlds());
  }

  void _attachGame(MinedartGame game) {
    game.hud.selectedSlot.addListener(_syncGameSlotToBuilder);
    game.onPauseRequested = () => unawaited(_showPauseOptions());
    game.onFirstMovementInput = () {
      if (!mounted || !_showStartupControls) return;
      setState(() => _showStartupControls = false);
    };
    game.setUiInputCaptured(_inputCapture.isCaptured);
    game.onFogPresetChanged = (preset) {
      _options.setFogPreset(
        FogPreset.values.firstWhere((value) => value.name == preset.name),
      );
    };
    _syncBuilderToGame();
    _gameLoaded = false;
    _lastAppliedOptionsFog = null;
    game.loaded.then((_) {
      if (!mounted || game != _runtime.game) return;
      _gameLoaded = true;
      _applyOptions();
      _applyRenderUi(_renderUi.settings);
    });
  }

  void _detachGame(MinedartGame game) {
    game.hud.selectedSlot.removeListener(_syncGameSlotToBuilder);
    game
      ..onPauseRequested = null
      ..onFirstMovementInput = null
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
      ..setBindings(_gameBindingsFromOptions(_options))
      ..setMouseOptions(
        sensitivity: _options.mouseSensitivity * 0.01,
        invertY: _options.invertMouseY,
      );
    unawaited(
      widget.audio.setSfxVolume(_options.masterVolume * _options.effectsVolume),
    );
    unawaited(widget.audio.setMusicVolume(_options.ambienceVolume));
    unawaited(widget.audio.setMuted(_options.audioMuted));
    if (!_gameLoaded) return;
    final fog = renderer.FogPreset.values.firstWhere(
      (preset) => preset.name == _options.fogPreset.name,
    );
    game.renderLab
      ..setHighContrast(_options.highContrast)
      ..setReducedMotion(_options.reducedMotion);
    if (_lastAppliedOptionsFog != _options.fogPreset) {
      _lastAppliedOptionsFog = _options.fogPreset;
      final distance = _distanceForFog(fog);
      game
        ..renderLab.setFogPreset(fog)
        ..setRenderDistanceChunks(distance);
      if (_renderUi.settings.renderDistance != distance) {
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
      await showBuilderStudio(
        modalContext,
        controller: _builder,
        onInputCaptureChanged: _onModalInputCaptureChanged,
      );
    } finally {
      _modalOpen = false;
    }
  }

  Future<void> _showPauseOptions() async {
    final modalContext = _navigatorContext;
    if (_modalOpen || !mounted || modalContext == null) return;
    _modalOpen = true;
    _runtime.game.simulationPaused = true;
    try {
      await showDialog<void>(
        context: modalContext,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: PauseOptionsView(
            controller: _options,
            onInputCaptureChanged: _onModalInputCaptureChanged,
            callbacks: PauseMenuCallbacks(
              onResume: () => Navigator.of(dialogContext).pop(),
              onOpenWorldLibrary: () =>
                  _transitionModal(dialogContext, _showWorldLibrary),
              onOpenRenderLab: () =>
                  _transitionModal(dialogContext, _showRenderLab),
              onSaveAndQuit: () =>
                  unawaited(_saveAndOpenLibrary(dialogContext)),
            ),
          ),
        ),
      );
    } finally {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(to()));
  }

  Future<void> _saveAndOpenLibrary(BuildContext dialogContext) async {
    await _runtime.autosaver.saveNow();
    if (dialogContext.mounted) {
      _transitionModal(dialogContext, _showWorldLibrary);
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
      await showDialog<void>(
        context: modalContext,
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
      _modalOpen = false;
    }
  }

  Future<void> _showWorldLibrary() async {
    if (_modalOpen || !mounted || _navigatorContext == null) return;
    _modalOpen = true;
    try {
      await _refreshWorlds();
      final modalContext = _navigatorContext;
      if (modalContext == null || !modalContext.mounted) return;
      await showDialog<void>(
        context: modalContext,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog.fullscreen(
          child: WorldLibraryView(
            controller: _worldLibrary,
            callbacks: _worldCallbacks(dialogContext),
            onClose: () => Navigator.of(dialogContext).pop(),
            onInputCaptureChanged: _onModalInputCaptureChanged,
          ),
        ),
      );
    } finally {
      _modalOpen = false;
    }
  }

  Future<void> _showMinimapEditor() async {
    final modalContext = _navigatorContext;
    if (_modalOpen || !mounted || modalContext == null) return;
    _modalOpen = true;
    try {
      await showDialog<void>(
        context: modalContext,
        builder: (dialogContext) => ModalInputRegion(
          onInputCaptureChanged: _onModalInputCaptureChanged,
          child: MinimapEditorDialog(
            state: _minimap,
            blockId:
                _builder.selectedBlockId ?? _runtime.game.hud.selectedBlock,
            onPaintSurface: (x, z, blockId, radius) {
              _runtime.game.paintSurface(x, z, blockId, radius);
              _minimap.value = _createMinimapState();
            },
          ),
        ),
      );
    } finally {
      _modalOpen = false;
    }
  }

  WorldLibraryCallbacks _worldCallbacks(
    BuildContext dialogContext,
  ) => WorldLibraryCallbacks(
    onCreate: (name, seed, presetChoice) async {
      final preset = switch (presetChoice) {
        WorldLibraryPreset.classic => LaunchWorldPreset.classic,
        WorldLibraryPreset.flat => LaunchWorldPreset.flat,
        WorldLibraryPreset.islands => LaunchWorldPreset.islands,
      };
      final document = await _createWorld(
        name,
        seed ?? kDefaultWorldSeed,
        preset: preset,
      );
      await _refreshWorlds();
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      await _switchWorld(document);
    },
    onImport: () async {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Minedart world', extensions: ['mdrt']),
        ],
      );
      if (file == null) return;
      final importedAt = DateTime.now().toUtc();
      await widget.repository.importBytes(
        Uint8List.fromList(await file.readAsBytes()),
        legacyMetadata: WorldMetadata(
          id: _newWorldId(importedAt),
          name: importedWorldName(file.name),
          seed: 0,
          createdAt: importedAt,
          updatedAt: importedAt,
          spawn: const WorldSpawn.origin(),
        ),
      );
      await _refreshWorlds();
    },
    onLoad: (entry) async {
      final document = await widget.repository.load(entry.id);
      if (document == null) return;
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      await _switchWorld(document);
    },
    onRename: (entry, name) async {
      final isCurrent = entry.id == _runtime.worldId;
      if (isCurrent) await _runtime.autosaver.saveNow();
      final renamed = await widget.repository.rename(entry.id, name);
      if (isCurrent && renamed != null) {
        _runtime.autosaver.replaceMetadata(renamed.metadata);
      }
      await _refreshWorlds();
    },
    onDuplicate: (entry) async {
      if (entry.id == _runtime.worldId) {
        await _runtime.autosaver.saveNow();
      }
      final now = DateTime.now().toUtc();
      final source = await widget.repository.load(entry.id);
      if (source == null) return;
      await widget.repository.duplicate(
        entry.id,
        WorldMetadata(
          id: duplicateWorldId(
            sourceId: entry.id,
            seed: entry.seed,
            nonce: now.microsecondsSinceEpoch,
          ),
          name: '${entry.name} Copy',
          seed: entry.seed,
          createdAt: now,
          updatedAt: now,
          spawn: source.metadata.spawn,
        ),
      );
      await _refreshWorlds();
    },
    onDelete: (entry) async {
      final deletingCurrent = entry.id == _runtime.worldId;
      if (deletingCurrent) {
        final remaining = (await widget.repository.list())
            .where((summary) => summary.id != entry.id)
            .toList();
        var replacement = remaining.isEmpty
            ? await _createWorld('Classic World', kDefaultWorldSeed)
            : await widget.repository.load(remaining.first.id);
        replacement ??= await _createWorld('Classic World', kDefaultWorldSeed);
        await _switchWorld(replacement, saveCurrent: false);
      }
      await widget.repository.delete(entry.id);
      await _refreshWorlds();
      if (deletingCurrent && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    },
    onReset: (entry) async {
      final world = generatePresetWorld(entry.seed, presetForWorldId(entry.id));
      final resettingCurrent = entry.id == _runtime.worldId;
      final oldRuntime = _runtime;
      if (resettingCurrent) await oldRuntime.autosaver.saveNow();
      final current = await widget.repository.load(entry.id);
      if (current == null) return;
      final reset = WorldDocument.fromWorld(
        metadata: current.metadata.copyWith(
          updatedAt: DateTime.now().toUtc(),
          spawn: defaultWorldSpawn(world),
        ),
        world: world,
      );
      try {
        if (resettingCurrent) {
          await oldRuntime.autosaver.stopAndWait();
        }
        await widget.repository.save(reset);
        await _refreshWorlds();
        if (resettingCurrent) {
          await _switchWorld(reset, force: true, saveCurrent: false);
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        }
      } on Object {
        if (resettingCurrent && identical(_runtime, oldRuntime)) {
          await widget.repository.save(current);
          oldRuntime.autosaver.start();
        }
        rethrow;
      }
    },
    onExport: (entry) async {
      if (entry.id == _runtime.worldId) {
        await _runtime.autosaver.saveNow();
      }
      final bytes = await widget.repository.exportBytes(entry.id);
      final location = await getSaveLocation(
        suggestedName: '${_safeFileName(entry.name)}.mdrt',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Minedart world', extensions: ['mdrt']),
        ],
      );
      if (location == null) return;
      await XFile.fromData(
        bytes,
        mimeType: 'application/octet-stream',
        name: '${_safeFileName(entry.name)}.mdrt',
      ).saveTo(location.path);
    },
    onShareSeed: (entry) async {
      final uri = ShowcaseLaunchConfig(
        seed: entry.seed,
        preset: presetForWorldId(entry.id),
      ).shareUri(Uri.base);
      await Clipboard.setData(ClipboardData(text: uri.toString()));
    },
  );

  Future<WorldDocument> _createWorld(
    String name,
    int seed, {
    LaunchWorldPreset preset = LaunchWorldPreset.classic,
  }) async {
    final world = generatePresetWorld(seed, preset);
    final now = DateTime.now().toUtc();
    final document = WorldDocument.fromWorld(
      metadata: WorldMetadata(
        id: preset == LaunchWorldPreset.classic
            ? _newWorldId(now)
            : sharedWorldId(seed, preset, nonce: now.microsecondsSinceEpoch),
        name: name.trim().isEmpty ? 'Classic World' : name.trim(),
        seed: seed,
        createdAt: now,
        updatedAt: now,
        spawn: defaultWorldSpawn(world),
      ),
      world: world,
    );
    await widget.repository.create(document);
    return document;
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

  Future<void> _switchWorld(
    WorldDocument document, {
    bool force = false,
    bool saveCurrent = true,
  }) async {
    if (_switchingWorld ||
        (!force && document.metadata.id == _runtime.worldId)) {
      return;
    }
    setState(() => _switchingWorld = true);
    final old = _runtime;
    try {
      if (saveCurrent) await old.autosaver.saveNow();
      final next = await WorldRuntime.create(
        repository: widget.repository,
        document: document,
        audio: widget.audio,
      );
      if (!mounted) {
        await next.close(save: false);
        return;
      }
      _detachGame(old.game);
      setState(() {
        _runtime = next;
        _showStartupControls = true;
      });
      _minimap.value = _createMinimapState();
      _attachGame(next.game);
      _syncBuilderToGame();
      await old.close(save: false);
      await _refreshWorlds();
    } finally {
      if (mounted) setState(() => _switchingWorld = false);
    }
  }

  @override
  void dispose() {
    _detachGame(_runtime.game);
    _builder
      ..removeListener(_syncBuilderToGame)
      ..dispose();
    _options
      ..removeListener(_applyOptions)
      ..dispose();
    _renderUi.dispose();
    _worldLibrary.dispose();
    _minimapTimer?.cancel();
    _minimap.dispose();
    unawaited(
      _runtime.close().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Final world save failed: $error\n$stackTrace');
      }),
    );
    unawaited(
      widget.audio.dispose().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Audio disposal failed: $error\n$stackTrace');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _runtime.game;
    final gameWidget = GameWidget<MinedartGame>(
      key: ValueKey<String>(_runtime.worldId),
      game: game,
      backgroundBuilder: (_) => const ColoredBox(color: Color(0xFF82C8FF)),
      initialActiveOverlays: const [kHudOverlayId],
      overlayBuilderMap: {
        kHudOverlayId: (context, game) => HudOverlay(
          hud: game.hud,
          frameMetrics: game.frameMetrics,
          onPrimary: kIsWeb ? () {} : game.breakTargetBlock,
          onSecondary: kIsWeb ? () {} : game.placeSelectedBlock,
        ),
      },
    );
    return AnimatedBuilder(
      animation: _options,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Minedart Classic Showcase',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B9D42),
            brightness: Brightness.dark,
            contrastLevel: _options.highContrast ? 1 : 0,
          ),
          useMaterial3: true,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: _options.reducedMotion),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF82C8FF),
          body: Stack(
            children: [
              CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      unawaited(_showPauseOptions()),
                  SingleActivator(
                    _options.bindingFor(GameInputAction.openInventory),
                  ): () =>
                      unawaited(_showBuilder()),
                  SingleActivator(
                    _options.bindingFor(GameInputAction.debugOverlay),
                  ): game.hud.toggleDebug,
                },
                child: Focus(autofocus: true, child: gameWidget),
              ),
              MinimapOverlay(state: _minimap, onOpen: _showMinimapEditor),
              if (_showStartupControls) const _StartupControlsOverlay(),
              if (_switchingWorld)
                const ColoredBox(
                  color: Color(0x99000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _StartupControlsOverlay extends StatelessWidget {
  const _StartupControlsOverlay();

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
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
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: ControlsHint(title: 'Controls'),
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

GameBindings _gameBindingsFromOptions(OptionsController options) =>
    GameBindings({
      for (final pair in _bindingPairs) pair.$2: options.bindingFor(pair.$1),
    });

const _bindingPairs = <(GameInputAction, GameControl)>[
  (GameInputAction.moveForward, GameControl.moveForward),
  (GameInputAction.moveBackward, GameControl.moveBackward),
  (GameInputAction.strafeLeft, GameControl.strafeLeft),
  (GameInputAction.strafeRight, GameControl.strafeRight),
  (GameInputAction.jump, GameControl.jump),
  (GameInputAction.openInventory, GameControl.openInventory),
  (GameInputAction.cycleFog, GameControl.cycleFog),
  (GameInputAction.storeSpawn, GameControl.storeSpawn),
  (GameInputAction.respawn, GameControl.respawn),
  (GameInputAction.toggleNoclip, GameControl.toggleNoclip),
  (GameInputAction.debugOverlay, GameControl.debugOverlay),
];

String _newWorldId(DateTime now) =>
    'world-${now.microsecondsSinceEpoch.toRadixString(36)}';

String _safeFileName(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
  return safe.isEmpty ? 'minedart-world' : safe;
}

String importedWorldName(String fileName) {
  final rawName = fileName.replaceFirst(
    RegExp(r'\.mdrt$', caseSensitive: false),
    '',
  );
  return rawName.trim().isEmpty ? 'Imported Classic World' : rawName.trim();
}

WorldSpawn defaultWorldSpawn(VoxelWorld world) {
  final centerX = WorldDims.worldBlocksX ~/ 2;
  final centerZ = WorldDims.worldBlocksZ ~/ 2;
  var bestX = centerX;
  var bestZ = centerZ;
  var bestY = world.skyHeight[centerX + centerZ * WorldDims.worldBlocksX];
  var bestDistance = 1 << 30;
  for (var z = 0; z < WorldDims.worldBlocksZ; z++) {
    for (var x = 0; x < WorldDims.worldBlocksX; x++) {
      final height = world.skyHeight[x + z * WorldDims.worldBlocksX];
      if (height <= 1 || height + 1 >= WorldDims.worldBlocksY) continue;
      final topId = Blocks.id(world.blockAt(x, height - 1, z));
      final definition = topId < blockDefs.length ? blockDefs[topId] : null;
      if (definition == null ||
          !definition.solid ||
          topId == Blocks.bedrock ||
          topId == Blocks.logOak ||
          topId == Blocks.leavesOak) {
        continue;
      }
      final dx = x - centerX;
      final dz = z - centerZ;
      final distance = dx * dx + dz * dz;
      if (distance < bestDistance ||
          (distance == bestDistance && height > bestY)) {
        bestX = x;
        bestZ = z;
        bestY = height;
        bestDistance = distance;
      }
    }
  }
  return WorldSpawn(x: bestX + 0.5, y: bestY.toDouble(), z: bestZ + 0.5);
}

int _distanceForFog(renderer.FogPreset fog) => switch (fog) {
  renderer.FogPreset.near => 3,
  renderer.FogPreset.normal => 6,
  renderer.FogPreset.far => 10,
  renderer.FogPreset.off => WorldDims.worldChunksX,
};
