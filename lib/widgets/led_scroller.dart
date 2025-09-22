// lib/widgets/led_scroller.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

/// LedScroller: paints a horizontal scrolling boolean matrix of dots.
/// Now supports automatic scaling to ensure the matrix fits vertically
/// inside the available height (prevents text going off-screen).
class LedScroller extends StatefulWidget {
  final List<List<bool>> matrix;
  final double dotSize; // nominal dot diameter in px
  final double spacing; // nominal spacing between dots
  final Color onColor;
  final Color offColor;
  final bool glow;
  final double speedPxPerSec;
  final bool playing;
  final bool directionLeft;

  const LedScroller({
    super.key,
    required this.matrix,
    required this.dotSize,
    required this.spacing,
    required this.onColor,
    required this.offColor,
    this.glow = true,
    required this.speedPxPerSec,
    required this.playing,
    required this.directionLeft,
  });

  @override
  State<LedScroller> createState() => _LedScrollerState();
}

class _LedScrollerState extends State<LedScroller>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _offset = 0.0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.playing) _ticker.start();
    if (!widget.playing) _ticker.muted = true;
  }

  @override
  void didUpdateWidget(covariant LedScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      if (widget.playing) {
        _last = Duration.zero;
        _ticker.muted = false;
        _ticker.start();
      } else {
        _ticker.muted = true;
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_last == Duration.zero) {
      _last = elapsed;
      return;
    }
    final dt = (elapsed - _last).inMilliseconds / 1000.0;
    _last = elapsed;
    final dir = widget.directionLeft ? 1.0 : -1.0;
    setState(() {
      _offset += dir * widget.speedPxPerSec * dt;
      // keep offset within reasonable bounds by modding by a large number
      if (_offset.abs() > 1e7) _offset = _offset % 10000.0;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build a painter that will scale content to fit the available height.
    return LayoutBuilder(builder: (context, constraints) {
      final canvasW = constraints.maxWidth;
      final canvasH = constraints.maxHeight;

      return CustomPaint(
        size: Size(canvasW, canvasH),
        painter: _LedScrollerPainter(
          matrix: widget.matrix,
          nominalDotSize: widget.dotSize,
          nominalSpacing: widget.spacing,
          onColor: widget.onColor,
          offColor: widget.offColor,
          glow: widget.glow,
          offset: _offset,
          canvasSize: Size(canvasW, canvasH),
        ),
      );
    });
  }
}

class _LedScrollerPainter extends CustomPainter {
  final List<List<bool>> matrix;
  final double nominalDotSize;
  final double nominalSpacing;
  final Color onColor;
  final Color offColor;
  final bool glow;
  final double offset;
  final Size canvasSize;

  _LedScrollerPainter({
    required this.matrix,
    required this.nominalDotSize,
    required this.nominalSpacing,
    required this.onColor,
    required this.offColor,
    required this.glow,
    required this.offset,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (matrix.isEmpty) return;
    final int rows = matrix.length;
    final int cols = matrix.first.length;
    if (rows == 0 || cols == 0) return;

    // compute nominal cell size
    final double nominalCell = nominalDotSize + nominalSpacing;
    final double nominalHeight = rows * nominalCell;

    // If nominal height > available height, scale down to fit
    final double scaleFactor = nominalHeight > size.height && nominalHeight > 0
        ? (size.height / nominalHeight)
        : 1.0;

    // scaled sizes
    final double dotSize = nominalDotSize * scaleFactor;
    final double spacing = nominalSpacing * scaleFactor;
    final double cell = dotSize + spacing;

    // vertical offset to center matrix
    final double totalHeight = rows * cell;
    final double verticalOffset = (size.height - totalHeight) / 2.0;

    final Paint onPaint = Paint()..color = onColor;
    final Paint offPaint = Paint()..color = offColor;

    // compute total width of single matrix strip
    final double totalStripWidth = cols * cell;

    // compute startX based on offset. We want content to move horizontally.
    // offset increases (positive) to move content to the left; so we invert for drawing start
    final double startX =
        -offset % (totalStripWidth == 0 ? 1 : totalStripWidth);

    // draw enough copies of the strip to fill the canvas
    // find the min and max copy indices
    final int minCopy = ((-startX) / totalStripWidth).floor() - 1;
    final int maxCopy = ((size.width - startX) / totalStripWidth).ceil() + 1;

    for (int copy = minCopy; copy <= maxCopy; copy++) {
      final double baseX = startX + copy * totalStripWidth;
      for (int c = 0; c < cols; c++) {
        final double colX = baseX + c * cell + (cell - dotSize) / 2.0;
        // quickly skip columns entirely offscreen
        if (colX + dotSize < 0 || colX > size.width) continue;
        for (int r = 0; r < rows; r++) {
          final double rowY =
              verticalOffset + r * cell + (cell - dotSize) / 2.0;
          final bool lit = matrix[r][c];
          final Offset center =
              Offset(colX + dotSize / 2.0, rowY + dotSize / 2.0);

          if (lit) {
            if (glow) {
              final Paint shadowPaint = Paint()
                ..color = onColor.withOpacity(0.18)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
              // draw a soft shadow circle larger than dot
              canvas.drawCircle(center, dotSize * 0.9, shadowPaint);
            }
            canvas.drawCircle(center, dotSize / 2.0, onPaint);
          } else {
            if (offColor.opacity > 0.0) {
              canvas.drawCircle(center, dotSize / 2.0, offPaint);
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LedScrollerPainter old) {
    return old.offset != offset ||
        old.nominalDotSize != nominalDotSize ||
        old.nominalSpacing != nominalSpacing ||
        old.onColor != onColor ||
        old.offColor != offColor ||
        old.matrix != matrix ||
        old.glow != glow ||
        old.canvasSize != canvasSize;
  }
}
