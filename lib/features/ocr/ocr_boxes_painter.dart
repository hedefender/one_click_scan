import 'package:flutter/material.dart';

import '../../domain/entities/ocr_line.dart';

/// Draws the quads of the lines over the picture they were read from. The
/// quads are 0..1 of the image, so they scale with whatever size the picture
/// is drawn at. Filtered lines get their own colour.
class OcrBoxesPainter extends CustomPainter {
  OcrBoxesPainter({
    required this.lines,
    required this.keptColor,
    required this.filteredColor,
  });

  final List<OcrLine> lines;
  final Color keptColor;
  final Color filteredColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final path = Path()
        ..moveTo(line.quad[0].x * size.width, line.quad[0].y * size.height);
      for (final p in line.quad.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = line.filtered ? filteredColor : keptColor,
      );
    }
  }

  @override
  bool shouldRepaint(OcrBoxesPainter old) =>
      old.lines != lines ||
      old.keptColor != keptColor ||
      old.filteredColor != filteredColor;
}
