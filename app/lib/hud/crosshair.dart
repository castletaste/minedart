/// Screen-center crosshair.
library;

import 'package:flutter/widgets.dart';

class Crosshair extends StatelessWidget {
  const Crosshair({super.key, this.size = 18, this.thickness = 2});

  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: CustomPaint(
          size: Size.square(size),
          painter: _CrosshairPainter(thickness: thickness),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter({required this.thickness});

  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final half = thickness / 2;
    final outline = Paint()..color = const Color(0x99000000);
    final line = Paint()..color = const Color(0xF2FFFFFF);
    final horizontal = Rect.fromLTRB(0, cy - half, size.width, cy + half);
    final vertical = Rect.fromLTRB(cx - half, 0, cx + half, size.height);
    canvas.drawRect(horizontal.inflate(1), outline);
    canvas.drawRect(vertical.inflate(1), outline);
    canvas.drawRect(horizontal, line);
    canvas.drawRect(vertical, line);
  }

  @override
  bool shouldRepaint(_CrosshairPainter oldDelegate) =>
      oldDelegate.thickness != thickness;
}
