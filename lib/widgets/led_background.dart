// lib/widgets/led_background.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Draws a dotted LED-style background.
/// If patternWidth/patternHeight are provided the dot grid is drawn with that
/// fixed logical size and centered — this prevents the LED pattern from
/// changing layout when the canvas size changes.
class LedBackgroundPainter extends CustomPainter {
  final Color backgroundColor;
  final Color dotColor;
  final double spacing;
  final double dotRadius;

  /// Optional: logical pattern size to keep the LED grid stable.
  /// If null, the painter fills the whole canvas (previous behavior).
  final double? patternWidth;
  final double? patternHeight;

  const LedBackgroundPainter({
    required this.backgroundColor,
    required this.dotColor,
    this.spacing = 13.0,
    this.dotRadius = 1.4,
    this.patternWidth,
    this.patternHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill full background
    final Paint fill = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, fill);

    // Determine the area where we will draw the dot pattern.
    final double areaW = patternWidth != null
        ? math.min(patternWidth!, size.width)
        : size.width;
    final double areaH = patternHeight != null
        ? math.min(patternHeight!, size.height)
        : size.height;

    // Calculate origin to center the pattern inside the canvas when fixed size
    final double originX = (size.width - areaW) / 2.0;
    final double originY = (size.height - areaH) / 2.0;

    final Paint dotPaint = Paint()..color = dotColor;
    final double step = math.max(6.0, spacing);
    // We use an offset so dots are nicely centered inside the pattern box.
    final double offset = step / 2.0;

    // Start positions (clamped to pattern area)
    double startY = originY + offset;
    while (startY - offset < originY) {
      startY += step;
    }
    double startX = originX + offset;
    while (startX - offset < originX) {
      startX += step;
    }

    // Draw dots only inside the defined pattern rectangle [originX, originX+areaW] x [originY, originY+areaH]
    final double maxX = originX + areaW;
    final double maxY = originY + areaH;
    final double r = math.max(0.5, dotRadius);

    for (double y = startY; y <= maxY; y += step) {
      for (double x = startX; x <= maxX; x += step) {
        canvas.drawCircle(Offset(x, y), r, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LedBackgroundPainter old) {
    return old.backgroundColor != backgroundColor ||
        old.dotColor != dotColor ||
        old.spacing != spacing ||
        old.dotRadius != dotRadius ||
        old.patternWidth != patternWidth ||
        old.patternHeight != patternHeight;
  }
}
