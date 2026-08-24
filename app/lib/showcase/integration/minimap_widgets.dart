import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

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
  const MinimapOverlay({required this.state, super.key});

  final ValueListenable<MinimapViewState> state;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 14,
    top: 14,
    child: Semantics(
      key: const ValueKey<String>('minimap-overlay'),
      image: true,
      label: 'World minimap',
      child: AbsorbPointer(
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
