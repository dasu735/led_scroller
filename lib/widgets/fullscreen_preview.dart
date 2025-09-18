// lib/widgets/fullscreen_preview.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'led_scroller.dart';
import 'led_background.dart';

class FullscreenRotatedPreview extends StatelessWidget {
  final String displayText;
  final double textSize;
  final Color textColor;
  final Color backgroundColor;
  final File? bgImageFile;
  final bool useGradient;
  final bool useLedDots;
  final double speed;
  final bool playing;
  final bool directionLeft;
  final bool blinkText;
  final bool blinkBackground;

  const FullscreenRotatedPreview({
    super.key,
    required this.displayText,
    required this.textSize,
    required this.textColor,
    required this.backgroundColor,
    required this.bgImageFile,
    required this.useGradient,
    required this.useLedDots,
    required this.speed,
    required this.playing,
    required this.directionLeft,
    required this.blinkText,
    required this.blinkBackground,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final screenH = media.size.height;

    // clamp inner sizes so rotated child doesn't overflow the screen
    final innerWidth = screenH.clamp(0.0, screenW * 1.2);
    final innerHeight = screenW.clamp(0.0, screenH * 1.2);

    // we'll render a simple dummy matrix of full-on dots if you haven't passed a matrix.
    // The FullscreenRotatedPreview is for visual full-screen experience; PreviewBox handles rasterization.
    final dummyRows = (textSize / 8).clamp(4, 80).toInt();
    final dummyCols = (screenW / (textSize / 8)).clamp(8, 500).toInt();
    final dummyMatrix = List.generate(
      dummyRows,
      (_) => List.generate(dummyCols, (_) => true),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bgImageFile != null)
              Image.file(bgImageFile!, fit: BoxFit.cover)
            else if (useGradient)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue, Colors.purple],
                  ),
                ),
              )
            else if (useLedDots)
              CustomPaint(
                painter: LedBackgroundPainter(),
                child: Container(color: backgroundColor),
              )
            else
              Container(color: backgroundColor),
            Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: SizedBox(
                  width: innerWidth,
                  height: innerHeight,
                  child: LedScroller(
                    matrix: dummyMatrix,
                    dotSize: (textSize / 16.0).clamp(2.0, 999.0),
                    spacing: ((textSize / 16.0) / 3.0).clamp(0.0, 999.0),
                    onColor: textColor,
                    offColor: Colors.transparent,
                    glow: true,
                    speedPxPerSec: (speed / 200.0) * 180.0 + 12.0,
                    playing: playing,
                    directionLeft: directionLeft,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
