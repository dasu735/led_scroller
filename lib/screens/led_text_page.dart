// lib/screens/led_scroller_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import '../widgets/preview_box.dart';
import '../widgets/control_panel.dart';
import '../widgets/fullscreen_preview.dart';
import 'privacy_policy.dart';

class LedTestPage extends StatefulWidget {
  const LedTestPage({super.key});
  @override
  State<LedTestPage> createState() => _LedTestPageState();
}

class _LedTestPageState extends State<LedTestPage> {
  // Shared UI state
  String displayText = "Dasu@735";
  double speed = 50;
  double textSize = 120;
  Color textColor = Colors.green;
  Color backgroundColor = Colors.white;
  bool blinkText = false;
  bool blinkBackground = false;
  bool useGradient = false;
  bool useLedDots = false;
  File? bgImageFile;
  int scrollDirection = -1;
  bool playing = true;

  // Recording guard
  bool isRecording = false;

  final TextEditingController textController = TextEditingController();
  final GlobalKey previewKey = GlobalKey(); // RepaintBoundary capture key

  @override
  void initState() {
    super.initState();
    textController.text = displayText;
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  void _openFullscreenPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return FullscreenRotatedPreview(
            displayText: displayText,
            textSize: textSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            useGradient: useGradient,
            useLedDots: useLedDots,
            bgImageFile: bgImageFile,
            speed: speed,
            playing: playing,
            directionLeft: scrollDirection == -1,
            blinkText: blinkText,
            blinkBackground: blinkBackground,
          );
        },
      ),
    );
  }

  // ---------------- PNG capture ----------------
  Future<Uint8List?> _capturePreviewPngBytes() async {
    try {
      final boundary = previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _sharePreviewAsPng() async {
    final bytes = await _capturePreviewPngBytes();
    if (bytes == null) return _showSnack('PNG capture failed');
    final tmp = await getTemporaryDirectory();
    final file = await File(
            '${tmp.path}/led_${DateTime.now().millisecondsSinceEpoch}.png')
        .writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: 'LED preview (PNG)');
  }

  Future<void> _savePreviewPng() async {
    final bytes = await _capturePreviewPngBytes();
    if (bytes == null) return _showSnack('PNG save failed');
    final dir = await getApplicationDocumentsDirectory();
    final file = await File(
            '${dir.path}/led_${DateTime.now().millisecondsSinceEpoch}.png')
        .writeAsBytes(bytes);
    _showSnack('Saved PNG to ${file.path}');
  }

  // ---------------- GIF recording ----------------
  Future<Uint8List?> _recordGifBytes({
    int durationSeconds = 2,
    int fps = 6,
    int maxWidth = 720,
  }) async {
    if (isRecording) return null;
    setState(() => isRecording = true);

    try {
      final boundary = previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final int totalFrames = (durationSeconds * fps).clamp(1, 200).toInt();
      final int frameDelayMs = (1000 / fps).round();
      final frames = <img.Image>[];

      await Future.delayed(const Duration(milliseconds: 50));

      for (int i = 0; i < totalFrames; i++) {
        try {
          final ui.Image uiImage = await boundary.toImage(pixelRatio: 1.0);
          final ByteData? bd =
              await uiImage.toByteData(format: ui.ImageByteFormat.png);
          if (bd != null) {
            final img.Image? frame = img.decodeImage(bd.buffer.asUint8List());
            if (frame != null) {
              final img.Image resized = frame.width > maxWidth
                  ? img.copyResize(frame, width: maxWidth)
                  : frame;
              frames.add(resized);
            }
          }
        } catch (e) {
          debugPrint('frame capture error: $e');
        }
        if (i < totalFrames - 1) {
          await Future.delayed(Duration(milliseconds: frameDelayMs));
        }
      }

      if (frames.isEmpty) return null;

      final encoder = img.GifEncoder();
      final int delayCs = (frameDelayMs / 10).round();
      for (final f in frames) {
        encoder.addFrame(f, duration: delayCs);
      }

      final Uint8List? out = encoder.finish();
      return out;
    } catch (e) {
      debugPrint('GIF encode unexpected error: $e');
      return null;
    } finally {
      if (mounted) setState(() => isRecording = false);
    }
  }

  Future<void> _recordAndShareGif() async {
    if (isRecording) return _showSnack('Busy — try again shortly.');
    _showSnack('Recording GIF (short)...');
    final bytes = await _recordGifBytes(durationSeconds: 3, fps: 8);
    if (bytes == null)
      return _showSnack(
          'Failed to record GIF — try lower FPS or make preview fully visible.');
    try {
      final tmp = await getTemporaryDirectory();
      final file = await File(
              '${tmp.path}/led_${DateTime.now().millisecondsSinceEpoch}.gif')
          .writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'LED preview (GIF)');
    } catch (e) {
      _showSnack('Failed to share GIF: $e');
    }
  }

  Future<void> _recordAndSaveGif() async {
    if (isRecording) return _showSnack('Busy — try again shortly.');
    _showSnack('Recording GIF (short)...');
    final bytes = await _recordGifBytes(durationSeconds: 3, fps: 8);
    if (bytes == null)
      return _showSnack(
          'Failed to record GIF — try lower FPS or make preview fully visible.');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = await File(
              '${dir.path}/led_${DateTime.now().millisecondsSinceEpoch}.gif')
          .writeAsBytes(bytes);
      _showSnack('Saved GIF to ${file.path}');
    } catch (e) {
      _showSnack('Failed to save GIF: $e');
    }
  }

  // convenience
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Parent callback for image picking. Accepts File? so callers can pass a picked file
  /// or null to clear/prompt.
  void _setBackgroundFile(File? f) => setState(() => bgImageFile = f);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Preview', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.star),
                      title: const Text('Rate App'),
                      onTap: () {
                        Navigator.pop(context);
                        showDialog(
                            context: context,
                            builder: (_) =>
                                const AlertDialog(title: Text('Rate app')));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.share),
                      title: const Text('Share App'),
                      onTap: () {
                        Navigator.pop(context);
                        _showSnack('Use share from control panel');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip),
                      title: const Text('Privacy Policy'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PrivacyPolicy()));
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.screen_rotation_alt),
            onPressed: _openFullscreenPreview,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Preview
            PreviewBox(
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
              directionLeft: scrollDirection == -1,
              blinkText: blinkText,
              blinkBackground: blinkBackground,
              onPickBackgroundImage: (file) {
                // When the small camera button in PreviewBox calls this it passes `null`.
                // Open image picker here (or clear) — simple example clears if null.
                if (file != null) {
                  _setBackgroundFile(file);
                } else {
                  // Here you should open your ImagePicker; for now we just clear.
                  // You can integrate image_picker and then call _setBackgroundFile(pickedFile)
                  _setBackgroundFile(null);
                  _showSnack(
                      'Pick image from Control Panel (implement picker in parent).');
                }
              },
            ),

            // Controls
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    10, 10, 10, MediaQuery.of(context).viewInsets.bottom + 10),
                child: ControlPanel(
                  textController: textController,
                  displayText: displayText,
                  textColor: textColor,
                  backgroundColor: backgroundColor,
                  speed: speed,
                  textSize: textSize,
                  blinkText: blinkText,
                  blinkBackground: blinkBackground,
                  isBusy: isRecording,
                  onTextChanged: (v) => setState(() => displayText = v),
                  onSpeedChanged: (v) => setState(() => speed = v),
                  onTextSizeChanged: (v) => setState(() => textSize = v),
                  onToggleBlinkText: (b) => setState(() => blinkText = b),
                  onToggleBlinkBackground: (b) =>
                      setState(() => blinkBackground = b),
                  onTogglePlay: () => setState(() => playing = !playing),
                  onSetDirection: (d) => setState(() => scrollDirection = d),
                  // onPickBackgroundImage: (f) => setState(() => bgImageFile = f),
                  onPickTextColor: (c) => setState(() => textColor = c),
                  onPickBackgroundColor: (c) =>
                      setState(() => backgroundColor = c),
                  onUseGradientChanged: (b) => setState(() => useGradient = b),
                  onUseLedDotsChanged: (b) => setState(() => useLedDots = b),
                  onShare: _recordAndShareGif,
                  onDownload: _recordAndSaveGif,
                  onSharePng: _sharePreviewAsPng,
                  onDownloadPng: _savePreviewPng,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
