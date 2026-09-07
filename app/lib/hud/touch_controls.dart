import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

abstract final class TouchControlsKeys {
  static const look = ValueKey('touch-look');
  static const joystick = ValueKey('touch-joystick');
  static const jump = ValueKey('touch-jump');
  static const breakBlock = ValueKey('touch-break');
  static const placeBlock = ValueKey('touch-place');
  static const pause = ValueKey('touch-pause');
  static const inventory = ValueKey('touch-inventory');
}

/// Gesture ownership stays here; gameplay state belongs to the active game.
/// Only the joystick rebuilds during a drag. The scene and HUD do not.
final class TouchControls extends StatefulWidget {
  const TouchControls({
    required this.onMovement,
    required this.onLook,
    required this.onJump,
    required this.onJumpPressed,
    required this.onSprint,
    required this.onBreak,
    required this.onPlace,
    required this.onPause,
    required this.onInventory,
    required this.onReset,
    super.key,
  });

  final ValueChanged<Offset> onMovement;
  final ValueChanged<Offset> onLook;
  final ValueChanged<bool> onJump;
  final VoidCallback onJumpPressed;
  final ValueChanged<bool> onSprint;
  final VoidCallback onBreak;
  final VoidCallback onPlace;
  final VoidCallback onPause;
  final VoidCallback onInventory;
  final VoidCallback onReset;

  @override
  State<TouchControls> createState() => _TouchControlsState();
}

final class _TouchControlsState extends State<TouchControls>
    with WidgetsBindingObserver {
  int? _lookPointer;
  int _gestureEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _reset() {
    _lookPointer = null;
    widget.onReset();
    // Recreate held controls so an old finger cannot resume after a modal or
    // background transition, even when the browser omits pointercancel.
    setState(() => _gestureEpoch++);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lookPointer = null;
    widget.onReset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Listener(
        key: TouchControlsKeys.look,
        // Mouse events continue to the desktop HUD behind this layer.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.touch) {
            _lookPointer ??= event.pointer;
          }
        },
        onPointerMove: (event) {
          if (_lookPointer == event.pointer) widget.onLook(event.delta);
        },
        onPointerUp: _endLook,
        onPointerCancel: _endLook,
        child: const SizedBox.expand(),
      ),
      SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TouchButton(
                    key: TouchControlsKeys.pause,
                    icon: Icons.pause,
                    label: 'Pause',
                    onPressed: () {
                      _reset();
                      widget.onPause();
                    },
                  ),
                  const SizedBox(width: 8),
                  _TouchButton(
                    key: TouchControlsKeys.inventory,
                    icon: Icons.inventory_2_outlined,
                    label: 'Inventory',
                    onPressed: () {
                      _reset();
                      widget.onInventory();
                    },
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: _TouchJoystick(
                key: ValueKey(_gestureEpoch),
                onChanged: (offset) {
                  widget.onMovement(offset);
                  widget.onSprint(offset.dy < -0.85);
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TouchButton(
                        key: TouchControlsKeys.breakBlock,
                        icon: Icons.remove,
                        label: 'Break',
                        onPressed: widget.onBreak,
                      ),
                      const SizedBox(width: 8),
                      _TouchButton(
                        key: TouchControlsKeys.placeBlock,
                        icon: Icons.add,
                        label: 'Place',
                        onPressed: widget.onPlace,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _JumpButton(
                    key: ValueKey(_gestureEpoch),
                    onChanged: widget.onJump,
                    onPressed: widget.onJumpPressed,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  void _endLook(PointerEvent event) {
    if (_lookPointer == event.pointer) _lookPointer = null;
  }
}

final class _TouchJoystick extends StatefulWidget {
  const _TouchJoystick({required this.onChanged, super.key});
  final ValueChanged<Offset> onChanged;

  @override
  State<_TouchJoystick> createState() => _TouchJoystickState();
}

final class _TouchJoystickState extends State<_TouchJoystick> {
  static const double _size = 120;
  static const double _radius = 42;
  int? _pointer;
  Offset _position = Offset.zero;

  @override
  void dispose() {
    _pointer = null;
    super.dispose();
  }

  void _move(PointerEvent event) {
    if (_pointer != event.pointer) return;
    final delta =
        (event.localPosition - const Offset(_size / 2, _size / 2)) / _radius;
    final position = delta.distance > 1 ? delta / delta.distance : delta;
    setState(() => _position = position);
    widget.onChanged(position.distance < 0.12 ? Offset.zero : position);
  }

  void _release(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    setState(() => _position = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Movement stick. Push fully forward to sprint.',
      child: Listener(
        key: TouchControlsKeys.joystick,
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.kind != PointerDeviceKind.touch || _pointer != null) return;
          _pointer = event.pointer;
          _move(event);
        },
        onPointerMove: _move,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: RepaintBoundary(
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface.withValues(alpha: 0.65),
              border: Border.all(color: colors.outline),
            ),
            child: Center(
              child: Transform.translate(
                offset: _position * _radius,
                child: Icon(Icons.open_with, size: 36, color: colors.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _TouchButton extends StatelessWidget {
  const _TouchButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon),
    ),
  );
}

final class _JumpButton extends StatefulWidget {
  const _JumpButton({
    required this.onChanged,
    required this.onPressed,
    super.key,
  });
  final ValueChanged<bool> onChanged;
  final VoidCallback onPressed;

  @override
  State<_JumpButton> createState() => _JumpButtonState();
}

final class _JumpButtonState extends State<_JumpButton> {
  final Set<int> _pointers = {};

  @override
  void dispose() {
    _pointers.clear();
    super.dispose();
  }

  void _release(PointerEvent event) {
    if (_pointers.remove(event.pointer) && _pointers.isEmpty) {
      widget.onChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'Jump',
    onTap: widget.onPressed,
    excludeSemantics: true,
    child: Listener(
      key: TouchControlsKeys.jump,
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.touch) return;
        if (_pointers.add(event.pointer) && _pointers.length == 1) {
          widget.onChanged(true);
        }
      },
      onPointerUp: _release,
      onPointerCancel: _release,
      child: _TouchButton(
        icon: Icons.arrow_upward,
        label: 'Jump',
        onPressed: () {},
      ),
    ),
  );
}
