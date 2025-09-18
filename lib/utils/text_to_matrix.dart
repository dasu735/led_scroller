// lib/utils/text_to_matrix.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Rasterizes text into a LED dot matrix.
Future<List<List<bool>>> textToDotMatrix({
  required String text,
  required TextStyle textStyle,
  double scale = 1.0,
  int maxWidth = 2000,
  int maxHeight = 800,
  required double dotPixelSize,
}) async {
  final tp = TextPainter(
    text: TextSpan(text: text, style: textStyle),
    textDirection: TextDirection.ltr,
  );
  tp.layout();

  final logicalWidth = tp.width == 0 ? 1.0 : tp.width;
  final logicalHeight = tp.height == 0 ? 1.0 : tp.height;

  final scaledW = (logicalWidth * scale).clamp(1, maxWidth).toInt();
  final scaledH = (logicalHeight * scale).clamp(1, maxHeight).toInt();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
      recorder, Rect.fromLTWH(0, 0, scaledW.toDouble(), scaledH.toDouble()));

  // Transparent background
  canvas.drawRect(Rect.fromLTWH(0, 0, scaledW.toDouble(), scaledH.toDouble()),
      Paint()..color = Colors.transparent);

  final scaleX = scaledW / logicalWidth;
  final scaleY = scaledH / logicalHeight;
  final textScale = math.min(scaleX, scaleY);

  canvas.save();
  canvas.scale(textScale, textScale);
  tp.paint(canvas, const Offset(0, 0));
  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(scaledW, scaledH);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) throw Exception('Failed to read image bytes');

  final Uint8List pixels = byteData.buffer.asUint8List();
  final cellSize = dotPixelSize.clamp(1.0, double.infinity);
  final cols = (scaledW / cellSize).floor();
  final rows = (scaledH / cellSize).floor();

  final safeCols = math.max(1, cols);
  final safeRows = math.max(1, rows);

  List<List<bool>> matrix =
      List.generate(safeRows, (_) => List.filled(safeCols, false));

  double luminanceAt(int x, int y) {
    final idx = (y * scaledW + x) * 4;
    if (idx + 2 >= pixels.length) return 0.0;
    final r = pixels[idx];
    final g = pixels[idx + 1];
    final b = pixels[idx + 2];
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }

  for (int r = 0; r < safeRows; r++) {
    for (int c = 0; c < safeCols; c++) {
      final startX = (c * cellSize).toInt();
      final startY = (r * cellSize).toInt();
      final endX = ((startX + cellSize).clamp(0, scaledW)).toInt();
      final endY = ((startY + cellSize).clamp(0, scaledH)).toInt();

      double sum = 0;
      int count = 0;
      final step = math.max(1, (cellSize / 3).floor());

      for (int yy = startY; yy < endY; yy += step) {
        for (int xx = startX; xx < endX; xx += step) {
          sum += luminanceAt(xx, yy);
          count++;
        }
      }

      final avg = count > 0 ? (sum / count) : 0;
      matrix[r][c] = avg > 30;
    }
  }

  return matrix;
}
