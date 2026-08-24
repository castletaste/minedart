import 'package:flutter/widgets.dart';

/// Announces that a modal editing surface owns keyboard focus so integration
/// can suspend game input for the lifetime of the surface.
final class ModalInputRegion extends StatefulWidget {
  const ModalInputRegion({
    required this.child,
    this.onInputCaptureChanged,
    super.key,
  });

  final Widget child;
  final ValueChanged<bool>? onInputCaptureChanged;

  @override
  State<ModalInputRegion> createState() => _ModalInputRegionState();
}

final class _ModalInputRegionState extends State<ModalInputRegion> {
  @override
  void initState() {
    super.initState();
    widget.onInputCaptureChanged?.call(true);
  }

  @override
  void didUpdateWidget(ModalInputRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onInputCaptureChanged == widget.onInputCaptureChanged) {
      return;
    }
    oldWidget.onInputCaptureChanged?.call(false);
    widget.onInputCaptureChanged?.call(true);
  }

  @override
  void dispose() {
    widget.onInputCaptureChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: ReadingOrderTraversalPolicy(),
    child: Focus(autofocus: true, child: widget.child),
  );
}
