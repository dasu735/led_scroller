// lib/widgets/led_background.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Draws a dotted LED-style background (fills backgroundColor then paints dots).
class LedBackgroundPainter extends CustomPainter {
  final Color backgroundColor;
  final Color dotColor;
  final double spacing;
  final double dotRadius;

  const LedBackgroundPainter({
    required this.backgroundColor,
    required this.dotColor,
    this.spacing = 12.0,
    this.dotRadius = 1.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background (painter must draw the solid color so child doesn't hide dots)
    final Paint fill = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, fill);

    // Dot grid
    final Paint dotPaint = Paint()..color = dotColor;
    final double step = math.max(6.0, spacing);
    final double offset = step / 2.0;

    for (double y = offset; y < size.height + step; y += step) {
      for (double x = offset; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), math.max(0.5, dotRadius), dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LedBackgroundPainter old) {
    return old.backgroundColor != backgroundColor ||
        old.dotColor != dotColor ||
        old.spacing != spacing ||
        old.dotRadius != dotRadius;
  }
}
