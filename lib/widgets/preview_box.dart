// lib/widgets/preview_box.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'led_background.dart';
import 'led_scroller.dart';
import '../utils/text_to_matrix.dart';

class PreviewBox extends StatefulWidget {
  final GlobalKey? previewKey;
  final String displayText;
  final double textSize;
  final Color textColor;
  final Color backgroundColor;
  final bool useGradient;
  final bool useLedDots;
  final File? bgImageFile;
  final double speed;
  final bool playing;
  final bool directionLeft;
  final bool blinkText;
  final bool blinkBackground;

  /// Unified callback used by control panel AND the preview camera button.
  /// Value is a File? representing the chosen image (or null if cleared).
  final ValueChanged<File?>? onPickBackgroundImage;

  const PreviewBox({
    super.key,
    this.previewKey,
    required this.displayText,
    required this.textSize,
    required this.textColor,
    required this.backgroundColor,
    required this.useGradient,
    required this.useLedDots,
    required this.bgImageFile,
    required this.speed,
    required this.playing,
    required this.directionLeft,
    required this.blinkText,
    required this.blinkBackground,
    this.onPickBackgroundImage,
  });

  @override
  State<PreviewBox> createState() => _PreviewBoxState();
}

class _PreviewBoxState extends State<PreviewBox>
    with SingleTickerProviderStateMixin {
  Future<List<List<bool>>>? _matrixFuture;
  late final AnimationController _blinkController;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _regenMatrix();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )
      ..addListener(() {
        if (widget.blinkText || widget.blinkBackground) {
          final newVisible = _blinkController.value < 0.5;
          if (newVisible != _visible) setState(() => _visible = newVisible);
        } else if (!_visible) {
          setState(() => _visible = true);
        }
      })
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant PreviewBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayText != widget.displayText ||
        oldWidget.textSize != widget.textSize) {
      _regenMatrix();
    }

    if (oldWidget.blinkText != widget.blinkText ||
        oldWidget.blinkBackground != widget.blinkBackground) {
      if (widget.blinkText || widget.blinkBackground) {
        _blinkController.repeat();
      } else {
        _blinkController.stop();
        setState(() => _visible = true);
      }
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _regenMatrix() {
    final fontSizeForRaster = math.max(24.0, widget.textSize * 2.5);
    final baseDot = math.max(2.0, widget.textSize / 16.0);
    // dotPixelSize = dot + spacing
    final dotPixelSize = baseDot + math.max(0.0, baseDot / 3.0);

    _matrixFuture = textToDotMatrix(
      text: widget.displayText.isEmpty ? ' ' : widget.displayText,
      textStyle: TextStyle(
        fontSize: fontSizeForRaster,
        fontWeight: FontWeight.bold,
        fontFamily: 'Roboto',
        color: Colors.white,
      ),
      scale: 1.0,
      maxWidth: 3000,
      maxHeight: 1200,
      dotPixelSize: dotPixelSize,
    );
    // FutureBuilder will update when ready
  }

  Widget _buildBackgroundSnapshot(bool visible) {
    if (widget.bgImageFile != null) {
      return Image.file(widget.bgImageFile!, fit: BoxFit.cover);
    }
    if (widget.useGradient) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue, Colors.purple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }
    if (widget.useLedDots) {
      return CustomPaint(
        painter: LedBackgroundPainter(),
        child: Container(color: widget.backgroundColor),
      );
    }
    return Container(
      color: (widget.blinkBackground && !visible)
          ? Colors.black
          : widget.backgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    const double previewHeight = 195.0;

    return RepaintBoundary(
      key: widget.previewKey,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(6),
            color: Colors.transparent,
          ),
          height: previewHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBackgroundSnapshot(_visible),
              // Use LayoutBuilder to size the scroller to available width/height
              LayoutBuilder(builder: (context, constraints) {
                return Center(
                  child: FutureBuilder<List<List<bool>>>(
                    future: _matrixFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const SizedBox(
                          height: 40,
                          width: 40,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snap.hasError || snap.data == null) {
                        return Text(
                          'Error creating matrix',
                          style: TextStyle(color: widget.textColor),
                        );
                      }

                      final matrix = snap.data!;
                      final dotSize = math.max(2.0, widget.textSize / 16.0);
                      final spacing = math.max(0.0, dotSize / 3.0);
                      final textOpacity =
                          (widget.blinkText && !_visible) ? 0.0 : 1.0;

                      // compute a safe width based on available width; prevents overflow and gives stable capture dimensions
                      final safeWidth = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : MediaQuery.of(context).size.width;
                      final safeHeight = previewHeight.clamp(
                          40.0,
                          constraints.maxHeight.isFinite
                              ? constraints.maxHeight
                              : previewHeight);

                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: textOpacity,
                        child: SizedBox(
                          width: safeWidth,
                          height: safeHeight,
                          child: LedScroller(
                            matrix: matrix,
                            dotSize: dotSize,
                            spacing: spacing,
                            onColor: widget.textColor,
                            offColor: Colors.transparent,
                            glow: true,
                            speedPxPerSec:
                                (widget.speed / 200.0) * 180.0 + 12.0,
                            playing: widget.playing,
                            directionLeft: widget.directionLeft,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    // call unified background-image callback; parent decides how to pick image
                    if (widget.onPickBackgroundImage != null) {
                      // sending null indicates "pick/clear" — parent can open picker
                      widget.onPickBackgroundImage!(null);
                    }
                  },
                  child: Container(
                    height: 36,
                    width: 36,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.asset(
                      'assets/images/camera.png',
                      color: Colors.white,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.camera_alt,
                            color: Colors.white, size: 20);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
