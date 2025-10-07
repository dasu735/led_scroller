// lib/widgets/fullscreen_preview.dart
import 'dart:io';
import 'package:flutter/material.dart';

import 'led_scroller.dart';
import 'led_background.dart';
import 'preview_box.dart'; // <-- reuse your preview implementation

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

    // When rotated, the child width should match screen height and vice versa.
    final childWidth = screenH;
    final childHeight = screenW;

    // Create a key for the preview box (so capture still works if needed).
    final GlobalKey previewKey = GlobalKey();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background (image / gradient / LED dots / solid color)
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
                painter: LedBackgroundPainter(
                  backgroundColor: backgroundColor,
                  dotColor: (backgroundColor.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white)
                      .withOpacity(0.18),
                  spacing: (textSize / 16.0 * 6).clamp(8.0, 24.0),
                  dotRadius: (textSize / 16.0 * 0.45).clamp(1.0, 4.0),
                ),
                child: const SizedBox.expand(),
              )
            else
              Container(color: backgroundColor),

            // Center rotated preview that uses the same PreviewBox as the main screen.
            Center(
              child: RotatedBox(
                quarterTurns: 1, // rotate 90 degrees clockwise
                child: SizedBox(
                  width: childWidth,
                  height: childHeight,
                  child: PreviewBox(
                    // supply a local key so captures still work if you call them from full screen
                    previewKey: previewKey,
                    displayText: displayText,
                    textSize: textSize,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    useGradient: useGradient,
                    useLedDots: useLedDots,
                    bgImageFile: bgImageFile,
                    speed: speed,
                    playing: playing,
                    directionLeft: directionLeft,
                    blinkText: blinkText,
                    blinkBackground: blinkBackground,
                    glow: true,
                    // PreviewBox expects an onPickBackgroundImage; provide a no-op so full screen doesn't attempt to open pickers
                    onPickBackgroundImage: (_) {},
                  ),
                ),
              ),
            ),

            // Close button
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
