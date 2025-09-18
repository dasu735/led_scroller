// lib/widgets/led_scroller.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class LedScroller extends StatefulWidget {
  final List<List<bool>> matrix;
  final double dotSize;
  final double spacing;
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
    this.speedPxPerSec = 80,
    this.playing = true,
    this.directionLeft = true,
  });

  @override
  State<LedScroller> createState() => _LedScrollerState();
}

class _LedScrollerState extends State<LedScroller>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _offset = 0.0;
  double contentWidth = 1.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    if (!widget.playing) {
      _last = elapsed;
      return;
    }
    if (_last == Duration.zero) {
      _last = elapsed;
      return;
    }
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;

    final dir = widget.directionLeft ? 1.0 : -1.0;
    _offset += widget.speedPxPerSec * dt * dir;
    if (contentWidth > 0) {
      _offset %= contentWidth;
      if (_offset < 0) _offset += contentWidth;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = widget.matrix.length;
        final cols = widget.matrix.isNotEmpty ? widget.matrix[0].length : 0;
        final baseDot = widget.dotSize;
        final baseSpacing = widget.spacing;

        final desiredHeight = rows * (baseDot + baseSpacing);
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : desiredHeight;

        final scaleY = desiredHeight > 0
            ? math.min(1.0, availableHeight / desiredHeight)
            : 1.0;
        final renderDot = baseDot * scaleY;
        final renderSpacing = baseSpacing * scaleY;

        final renderTotalWidth = cols * (renderDot + renderSpacing);
        final usedContentWidth = math.max(1.0, renderTotalWidth.toDouble());
        // clamp content width to avoid huge values
        contentWidth = usedContentWidth.clamp(
          1.0,
          (constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.of(context).size.width) *
              10.0,
        );

        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width - 16;
        final renderHeight = rows * (renderDot + renderSpacing);
        final constrainedHeight = math.max(
          1.0,
          renderHeight.clamp(1.0, availableHeight),
        );

        return ClipRect(
          child: SizedBox(
            width: width,
            height: constrainedHeight,
            child: CustomPaint(
              painter: _LedScrollerPainter(
                matrix: widget.matrix,
                dotSize: renderDot,
                spacing: renderSpacing,
                onColor: widget.onColor,
                offColor: widget.offColor,
                glow: widget.glow,
                offset: _offset,
                contentWidth: contentWidth,
              ),
              size: Size(width, constrainedHeight),
            ),
          ),
        );
      },
    );
  }
}

class _LedScrollerPainter extends CustomPainter {
  final List<List<bool>> matrix;
  final double dotSize;
  final double spacing;
  final Color onColor;
  final Color offColor;
  final bool glow;
  final double offset;
  final double contentWidth;

  _LedScrollerPainter({
    required this.matrix,
    required this.dotSize,
    required this.spacing,
    required this.onColor,
    required this.offColor,
    required this.glow,
    required this.offset,
    required this.contentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rows = matrix.length;
    final cols = matrix.isNotEmpty ? matrix[0].length : 0;
    if (cols == 0 || rows == 0) return;

    // small top offset so topmost LED isn't clipped
    final yOffset = dotSize / 2 + 1.0;

    final draws = <double>[-offset, -offset + contentWidth];

    for (final baseShift in draws) {
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final on = matrix[r][c];
          final cx = baseShift + c * (dotSize + spacing) + dotSize / 2;
          final cy = yOffset + r * (dotSize + spacing) + dotSize / 2;

          if (cx + dotSize < 0 || cx - dotSize > size.width) continue;
          if (cy + dotSize < 0 || cy - dotSize > size.height) continue;

          if (on) {
            if (glow) {
              final glowPaint = Paint()
                ..color = onColor.withOpacity(0.18)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
              canvas.drawCircle(Offset(cx, cy), dotSize * 1.1, glowPaint);
            }
            paint.color = onColor;
            canvas.drawCircle(Offset(cx, cy), dotSize / 2, paint);
          } else {
            if (offColor != Colors.transparent) {
              paint.color = onColor.withOpacity(0.06);
              canvas.drawCircle(Offset(cx, cy), dotSize / 2, paint);
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LedScrollerPainter old) {
    return old.matrix != matrix ||
        old.dotSize != dotSize ||
        old.spacing != spacing ||
        old.onColor != onColor ||
        old.offColor != offColor ||
        old.offset != offset ||
        old.glow != glow;
  }
}
