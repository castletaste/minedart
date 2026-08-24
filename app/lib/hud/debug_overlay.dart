/// Top-left debug readout (F3): fps EMA, player position, selected block.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'hud_state.dart';
import '../showcase/render/frame_metrics.dart';

class DebugOverlay extends StatelessWidget {
  const DebugOverlay({required this.hud, this.frameMetrics, super.key});

  final HudState hud;
  final FrameMetrics? frameMetrics;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: hud.debugVisible,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x77000000),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: ValueListenableBuilder<DebugStats>(
                  valueListenable: hud.debugStats,
                  builder: (context, stats, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDebugStats(stats),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Color(0xFFEFEFEF),
                          fontFamily: 'monospace',
                          fontFamilyFallback: <String>['Menlo', 'Courier'],
                        ),
                      ),
                      if (frameMetrics case final metrics?) ...[
                        Text(
                          'frame p50 ${metrics.p50.toStringAsFixed(1)} ms  '
                          'p95 ${metrics.p95.toStringAsFixed(1)} ms',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFD6FAD0),
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 190,
                          height: 48,
                          child: CustomPaint(
                            painter: _FrameGraphPainter(metrics),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _FrameGraphPainter extends CustomPainter {
  _FrameGraphPainter(this.metrics);

  final FrameMetrics metrics;
  final Float64List _samples = Float64List(240);

  @override
  void paint(Canvas canvas, Size size) {
    final count = metrics.copyTo(_samples);
    if (count < 2) return;
    final guidePaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    final frame16Y = size.height * (1 - 16.67 / 40);
    canvas.drawLine(
      Offset(0, frame16Y),
      Offset(size.width, frame16Y),
      guidePaint,
    );
    final path = Path();
    for (var i = 0; i < count; i++) {
      final x = i * size.width / (count - 1);
      final ms = _samples[i].clamp(0.0, 40.0);
      final y = size.height * (1 - ms / 40);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF8DFF74)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _FrameGraphPainter oldDelegate) => true;
}

/// Text body of the debug overlay; pure so it can be unit tested.
String formatDebugStats(DebugStats stats) {
  final fps = stats.fps.toStringAsFixed(1);
  final x = stats.x.toStringAsFixed(2);
  final y = stats.y.toStringAsFixed(2);
  final z = stats.z.toStringAsFixed(2);
  return 'fps $fps\n'
      'xyz $x / $y / $z\n'
      'chunks ${stats.visibleChunks}/${stats.loadedChunks}  '
      'mesh queue ${stats.meshQueue}  rd ${stats.renderDistance}\n'
      'movement: ${stats.sprinting ? 'sprint' : 'walk'}\n'
      'block ${stats.blockName}\n'
      'action ${stats.lastAction}';
}
