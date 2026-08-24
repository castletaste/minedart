import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../hud/block_palette.dart';
import '../render/minimap_snapshot.dart';

@immutable
final class MinimapViewState {
  const MinimapViewState({
    required this.snapshot,
    required this.playerX,
    required this.playerZ,
    required this.heading,
  });

  final MinimapSnapshot snapshot;
  final double playerX;
  final double playerZ;
  final double heading;
}

final class MinimapOverlay extends StatelessWidget {
  const MinimapOverlay({required this.state, required this.onOpen, super.key});

  final ValueListenable<MinimapViewState> state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 14,
    top: 14,
    child: Semantics(
      button: true,
      label: 'Open world minimap editor',
      child: GestureDetector(
        onTap: onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            border: Border.all(color: const Color(0x88FFFFFF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox(
            width: 150,
            height: 150,
            child: ValueListenableBuilder<MinimapViewState>(
              valueListenable: state,
              builder: (context, value, _) => Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    isComplex: true,
                    painter: MinimapTerrainPainter(
                      value.snapshot,
                      sampleStep: 2,
                    ),
                  ),
                  CustomPaint(painter: MinimapMarkerPainter(value)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class MinimapEditorDialog extends StatefulWidget {
  const MinimapEditorDialog({
    required this.state,
    required this.blockId,
    required this.onPaintSurface,
    super.key,
  });

  final ValueListenable<MinimapViewState> state;
  final int blockId;
  final void Function(int x, int z, int blockId, int radius) onPaintSurface;

  @override
  State<MinimapEditorDialog> createState() => _MinimapEditorDialogState();
}

final class _MinimapEditorDialogState extends State<MinimapEditorDialog> {
  double _radius = 0;
  final FocusNode _mapFocusNode = FocusNode(debugLabel: 'minimap editor map');
  int _selectedX = 0;
  int _selectedZ = 0;

  @override
  void dispose() {
    _mapFocusNode.dispose();
    super.dispose();
  }

  void _moveSelection(MinimapSnapshot snapshot, int dx, int dz) {
    setState(() {
      _selectedX = (_selectedX + dx).clamp(0, snapshot.width - 1).toInt();
      _selectedZ = (_selectedZ + dz).clamp(0, snapshot.depth - 1).toInt();
    });
  }

  void _paintSelection(MinimapSnapshot snapshot) {
    widget.onPaintSurface(
      _selectedX.clamp(0, snapshot.width - 1).toInt(),
      _selectedZ.clamp(0, snapshot.depth - 1).toInt(),
      widget.blockId,
      _radius.round(),
    );
  }

  KeyEventResult _handleMapKeyEvent(KeyEvent event, MinimapSnapshot snapshot) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _moveSelection(snapshot, -1, 0);
      case LogicalKeyboardKey.arrowRight:
        _moveSelection(snapshot, 1, 0);
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(snapshot, 0, -1);
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(snapshot, 0, 1);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        _paintSelection(snapshot);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _selectAndPaint(MinimapSnapshot snapshot, Offset position, Size size) {
    final x = (position.dx / size.width * snapshot.width)
        .floor()
        .clamp(0, snapshot.width - 1)
        .toInt();
    final z = (position.dy / size.height * snapshot.depth)
        .floor()
        .clamp(0, snapshot.depth - 1)
        .toInt();
    setState(() {
      _selectedX = x;
      _selectedZ = z;
    });
    _paintSelection(snapshot);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Minimap editor',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close minimap editor',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text('Paint ${blockLabel(widget.blockId)} on the terrain surface'),
            Row(
              children: [
                const Text('Brush radius'),
                Expanded(
                  child: Slider(
                    value: _radius,
                    min: 0,
                    max: 4,
                    divisions: 4,
                    label: _radius.round().toString(),
                    onChanged: (value) => setState(() => _radius = value),
                  ),
                ),
              ],
            ),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: ValueListenableBuilder<MinimapViewState>(
                  valueListenable: widget.state,
                  builder: (context, value, _) => LayoutBuilder(
                    builder: (context, constraints) {
                      final snapshot = value.snapshot;
                      final selectedX = _selectedX
                          .clamp(0, snapshot.width - 1)
                          .toInt();
                      final selectedZ = _selectedZ
                          .clamp(0, snapshot.depth - 1)
                          .toInt();
                      return Focus(
                        focusNode: _mapFocusNode,
                        autofocus: true,
                        onKeyEvent: (_, event) =>
                            _handleMapKeyEvent(event, snapshot),
                        child: Semantics(
                          key: const ValueKey<String>('minimap-editor-map'),
                          button: true,
                          focusable: true,
                          label:
                              'Terrain map. Selected cell ${selectedX + 1}, ${selectedZ + 1}',
                          hint:
                              'Use arrow keys to move. Press Enter or Space to paint.',
                          onTap: () => _paintSelection(snapshot),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) {
                              FocusScope.of(
                                context,
                              ).requestFocus(_mapFocusNode);
                              _selectAndPaint(
                                snapshot,
                                details.localPosition,
                                constraints.biggest,
                              );
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomPaint(
                                  isComplex: true,
                                  painter: MinimapTerrainPainter(snapshot),
                                ),
                                CustomPaint(
                                  painter: MinimapMarkerPainter(value),
                                ),
                                CustomPaint(
                                  painter: MinimapSelectionPainter(
                                    x: selectedX,
                                    z: selectedZ,
                                    width: snapshot.width,
                                    depth: snapshot.depth,
                                  ),
                                ),
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: ExcludeSemantics(
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        color: Color(0xAA000000),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Text(
                                          'Selected cell: ${selectedX + 1}, ${selectedZ + 1}',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const Text(
              'Click the map to paint. Arrow keys move the selected cell; '
              'Enter or Space paints it. Cmd/Ctrl+Z undoes the stroke.',
            ),
          ],
        ),
      ),
    ),
  );
}

final class MinimapTerrainPainter extends CustomPainter {
  const MinimapTerrainPainter(this.snapshot, {this.sampleStep = 1});

  final MinimapSnapshot snapshot;
  final int sampleStep;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / snapshot.width;
    final cellH = size.height / snapshot.depth;
    final paint = Paint();
    for (var z = 0; z < snapshot.depth; z += sampleStep) {
      for (var x = 0; x < snapshot.width; x += sampleStep) {
        final block = snapshot.surfaceBlockAt(x, z);
        final elevation = snapshot.normalizedElevationAt(x, z);
        paint.color = Color.lerp(
          const Color(0xFF17221A),
          blockColor(block),
          0.55 + elevation * 0.45,
        )!;
        canvas.drawRect(
          Rect.fromLTWH(
            x * cellW,
            z * cellH,
            cellW * sampleStep + 0.5,
            cellH * sampleStep + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant MinimapTerrainPainter oldDelegate) =>
      !identical(oldDelegate.snapshot, snapshot) ||
      oldDelegate.sampleStep != sampleStep;
}

final class MinimapMarkerPainter extends CustomPainter {
  const MinimapMarkerPainter(this.state);

  final MinimapViewState state;

  @override
  void paint(Canvas canvas, Size size) {
    final px = state.playerX / state.snapshot.width * size.width;
    final pz = state.playerZ / state.snapshot.depth * size.height;
    canvas.save();
    canvas.translate(px, pz);
    canvas.rotate(-state.heading);
    final marker = Path()
      ..moveTo(0, -7)
      ..lineTo(5, 6)
      ..lineTo(0, 3)
      ..lineTo(-5, 6)
      ..close();
    canvas.drawPath(marker, Paint()..color = const Color(0xFFFFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MinimapMarkerPainter oldDelegate) =>
      oldDelegate.state.playerX != state.playerX ||
      oldDelegate.state.playerZ != state.playerZ ||
      oldDelegate.state.heading != state.heading ||
      !identical(oldDelegate.state.snapshot, state.snapshot);
}

final class MinimapSelectionPainter extends CustomPainter {
  const MinimapSelectionPainter({
    required this.x,
    required this.z,
    required this.width,
    required this.depth,
  });

  final int x;
  final int z;
  final int width;
  final int depth;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / width;
    final cellH = size.height / depth;
    canvas.drawRect(
      Rect.fromLTWH(x * cellW, z * cellH, cellW, cellH),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant MinimapSelectionPainter oldDelegate) =>
      oldDelegate.x != x ||
      oldDelegate.z != z ||
      oldDelegate.width != width ||
      oldDelegate.depth != depth;
}
