import 'dart:async';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../game/minedart_game.dart';
import '../../hud/hud_overlay.dart';
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
  const GameRuntimeHost({required this.controller, super.key});
  final GameRuntimeHostController controller;

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
    );
  }
}

/// Tracks actual element ownership separately from the host's desired set.
final class _RuntimeView extends StatefulWidget {
  const _RuntimeView({
    required this.controller,
    required this.runtime,
    required this.active,
    super.key,
  });

  final GameRuntimeHostController controller;
  final WorldRuntime runtime;
  final bool active;

  @override
  State<_RuntimeView> createState() => _RuntimeViewState();
}

final class _RuntimeViewState extends State<_RuntimeView> {
  @override
  void initState() {
    super.initState();
    widget.controller._mounted.add(widget.runtime);
  }

  @override
  void didUpdateWidget(_RuntimeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller) &&
        identical(oldWidget.runtime, widget.runtime)) {
      return;
    }
    oldWidget.controller._mounted.remove(oldWidget.runtime);
    widget.controller._mounted.add(widget.runtime);
  }

  @override
  void dispose() {
    widget.controller._mounted.remove(widget.runtime);
    super.dispose();
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
          autofocus: false,
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
              onCapture: game.requestMouseCapture,
              onPrimary: kIsWeb ? () {} : game.breakTargetBlock,
              onSecondary: kIsWeb ? () {} : game.placeSelectedBlock,
            ),
          },
        ),
      ),
    ),
  );
}
