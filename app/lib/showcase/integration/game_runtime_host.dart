import 'dart:async';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../game/minedart_game.dart';
import '../../hud/hud_overlay.dart';
import '../../hud/touch_controls.dart';
import 'world_runtime.dart';
import 'world_session_coordinator.dart';

/// Mounting acknowledgements live here; the session never retains a context.
final class GameRuntimeHostController extends ChangeNotifier
    implements WorldSessionHost {
  GameRuntimeHostController(WorldRuntime initial) : current = initial {
    _visible.add(initial);
  }

  WorldRuntime current;
  final Set<WorldRuntime> _visible = {};
  final Set<WorldRuntime> _mounted = {};
  bool _attached = true;
  bool _foreground = true;

  void setForeground(bool foreground) {
    _foreground = foreground;
    for (final runtime in _visible) {
      runtime.game.setAppForeground(foreground);
      if (foreground) {
        runtime.pipeline.resumeDeadlines();
      } else {
        runtime.pipeline.pauseDeadlines();
      }
    }
  }

  @override
  bool get isAttached => _attached;

  @override
  Future<void> stage(WorldSessionRuntime candidate) async {
    if (!_attached) throw StateError('Game host is detached');
    final runtime = candidate as WorldRuntime;
    runtime.game.pauseEngine();
    runtime.game.setAppForeground(_foreground);
    if (!_foreground) runtime.pipeline.pauseDeadlines();
    _visible.add(runtime);
    notifyListeners();
    final error = await runtime.game.mountedReady;
    if (error != null) throw error;
    if (!_attached) throw StateError('Game host detached during loading');
  }

  @override
  void commit(WorldSessionRuntime candidate) {
    current = candidate as WorldRuntime;
    _visible.removeWhere((runtime) => !identical(runtime, current));
    if (_attached) notifyListeners();
  }

  @override
  Future<void> remove(WorldSessionRuntime runtime) async {
    final concrete = runtime as WorldRuntime;
    if (_visible.remove(concrete) && _attached) notifyListeners();
    if (_mounted.contains(concrete)) {
      await concrete.game.removed;
    } else {
      concrete.game.disposeSessionResources();
    }
    _mounted.remove(concrete);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    for (final runtime in _visible) {
      if (!_mounted.contains(runtime)) runtime.game.disposeSessionResources();
    }
  }
}

final class GameRuntimeHost extends StatefulWidget {
  const GameRuntimeHost({
    required this.controller,
    this.touchControls = false,
    this.onPause,
    this.onInventory,
    super.key,
  });
  final GameRuntimeHostController controller;
  final bool touchControls;
  final VoidCallback? onPause;
  final VoidCallback? onInventory;

  @override
  State<GameRuntimeHost> createState() => _GameRuntimeHostState();
}

final class _GameRuntimeHostState extends State<GameRuntimeHost> {
  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Stack(
      children: [
        for (final runtime in widget.controller._visible)
          _game(runtime, active: identical(runtime, widget.controller.current)),
      ],
    ),
  );

  Widget _game(WorldRuntime runtime, {required bool active}) {
    return _RuntimeView(
      key: ObjectKey(runtime),
      controller: widget.controller,
      runtime: runtime,
      active: active,
      touchControls: widget.touchControls,
      onPause: widget.onPause,
      onInventory: widget.onInventory,
    );
  }
}

/// Tracks actual element ownership separately from the host's desired set.
final class _RuntimeView extends StatefulWidget {
  const _RuntimeView({
    required this.controller,
    required this.runtime,
    required this.active,
    required this.touchControls,
    this.onPause,
    this.onInventory,
    super.key,
  });

  final GameRuntimeHostController controller;
  final WorldRuntime runtime;
  final bool active;
  final bool touchControls;
  final VoidCallback? onPause;
  final VoidCallback? onInventory;

  @override
  State<_RuntimeView> createState() => _RuntimeViewState();
}

final class _RuntimeViewState extends State<_RuntimeView> {
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'Game keyboard');

  @override
  void initState() {
    super.initState();
    widget.controller._mounted.add(widget.runtime);
    _syncTouchMode();
  }

  @override
  void didUpdateWidget(_RuntimeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTouchMode();
    if (identical(oldWidget.controller, widget.controller) &&
        identical(oldWidget.runtime, widget.runtime)) {
      return;
    }
    oldWidget.controller._mounted.remove(oldWidget.runtime);
    widget.controller._mounted.add(widget.runtime);
  }

  void _syncTouchMode() => widget.runtime.game.setTouchControlsEnabled(
    widget.active && widget.touchControls,
  );

  @override
  void dispose() {
    widget.runtime.game.setTouchControlsEnabled(false);
    widget.controller._mounted.remove(widget.runtime);
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _captureInput() {
    if (!widget.active || !(ModalRoute.isCurrentOf(context) ?? true)) return;
    _keyboardFocus.requestFocus();
    widget.runtime.game.requestMouseCapture();
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !widget.active,
    child: ExcludeFocus(
      excluding: !widget.active,
      child: IgnorePointer(
        ignoring: !widget.active,
        child: GameWidget<MinedartGame>(
          game: widget.runtime.game,
          focusNode: _keyboardFocus,
          // A staged world must wait until it is active and its route is
          // current, otherwise its initial focus can steal a modal's keys.
          autofocus: widget.active && (ModalRoute.isCurrentOf(context) ?? true),
          backgroundBuilder: (_) => const ColoredBox(color: Color(0xFF82C8FF)),
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText('Could not load world: $error'),
            ),
          ),
          initialActiveOverlays: const [kHudOverlayId],
          overlayBuilderMap: {
            kHudOverlayId: (_, game) => HudOverlay(
              hud: game.hud,
              frameMetrics: game.frameMetrics,
              touchControls: widget.active && widget.touchControls
                  ? TouchControls(
                      onMovement: (offset) => game.setTouchMovement(
                        forward: -offset.dy,
                        strafe: offset.dx,
                      ),
                      onLook: (delta) =>
                          game.addTouchLookDelta(delta.dx, delta.dy),
                      onJump: game.setTouchJumpHeld,
                      onJumpPressed: game.requestTouchJump,
                      onSprint: game.setTouchSprintHeld,
                      onBreak: game.requestTouchBreak,
                      onPlace: game.requestTouchPlace,
                      onPause: widget.onPause ?? () {},
                      onInventory: widget.onInventory ?? () {},
                      onReset: game.resetTouchInput,
                    )
                  : null,
              onCapture: _captureInput,
              onPrimary: kIsWeb ? () {} : game.breakTargetBlock,
              onSecondary: kIsWeb ? () {} : game.placeSelectedBlock,
            ),
          },
        ),
      ),
    ),
  );
}
