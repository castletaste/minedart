/// Root HUD overlay: mouse buttons + scroll input, crosshair, hotbar, debug.
///
/// Mouse buttons and the scroll wheel are handled here with a [Listener],
/// which keeps working while the native layer holds the pointer captured.
/// Pointer movement and Esc are deliberately untouched: mouse-look capture is
/// owned by the platform channel side.
library;

import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        PointerPanZoomStartEvent,
        PointerPanZoomUpdateEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        kPrimaryMouseButton,
        kSecondaryMouseButton;
import 'package:flutter/widgets.dart';

import 'crosshair.dart';
import 'debug_overlay.dart';
import 'hud_state.dart';
import 'hotbar.dart';
import '../showcase/render/frame_metrics.dart';

/// Overlay key registered with [GameWidget.overlayBuilderMap].
const String kHudOverlayId = 'hud';

class HudOverlay extends StatefulWidget {
  const HudOverlay({
    required this.hud,
    required this.onCapture,
    required this.onPrimary,
    required this.onSecondary,
    this.frameMetrics,
    super.key,
  });

  final HudState hud;

  /// Requests pointer lock/native relative mouse only for the game surface.
  final VoidCallback onCapture;

  /// Left click: break the targeted block.
  final VoidCallback onPrimary;

  /// Right click: place the selected block.
  final VoidCallback onSecondary;
  final FrameMetrics? frameMetrics;

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay> {
  /// Accumulated two-finger trackpad scroll; a slot switch fires per step.
  double _panAccum = 0;
  static const double _panStep = 48;
  final GlobalKey _hotbarKey = GlobalKey(debugLabel: 'interactive hotbar');

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerSignal: _handlePointerSignal,
      onPointerPanZoomStart: _handlePanZoomStart,
      onPointerPanZoomUpdate: _handlePanZoomUpdate,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Crosshair(),
          Hotbar(hud: widget.hud, interactionKey: _hotbarKey),
          IgnorePointer(
            child: DebugOverlay(
              hud: widget.hud,
              frameMetrics: widget.frameMetrics,
            ),
          ),
        ],
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (_isOverHotbar(event.position)) return;
    widget.onCapture();
    if (event.buttons & kPrimaryMouseButton != 0) {
      widget.onPrimary();
    } else if (event.buttons & kSecondaryMouseButton != 0) {
      widget.onSecondary();
    }
  }

  bool _isOverHotbar(Offset globalPosition) {
    final renderObject = _hotbarKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    return (Offset.zero & renderObject.size).contains(
      renderObject.globalToLocal(globalPosition),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    widget.hud.handleScroll(event.scrollDelta.dy);
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    _panAccum = 0;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _panAccum += event.panDelta.dy;
    while (_panAccum >= _panStep) {
      widget.hud.handleScroll(1);
      _panAccum -= _panStep;
    }
    while (_panAccum <= -_panStep) {
      widget.hud.handleScroll(-1);
      _panAccum += _panStep;
    }
  }
}
