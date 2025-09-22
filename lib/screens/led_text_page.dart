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
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String displayText = "LED SCROLLER";
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

  final List<String> history = [];
  bool isRecording = false;
  bool _disableGlowForCapture = false;

  final TextEditingController textController = TextEditingController();
  final GlobalKey previewKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

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

  void _openBottomMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121214),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.star_rate_rounded, color: Colors.white),
              title:
                  const Text('Rate App', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRateDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('Share App',
                  style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.of(ctx).pop();
                _shareAppLink(
                    "https://play.google.com/store/apps/details?id=com.example.myapp");
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.privacy_tip_outlined, color: Colors.white),
              title: const Text('Privacy Policy',
                  style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PrivacyPolicy()));
              },
            ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  void _showRateDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        int rating = 0;
        final TextEditingController commentCtrl = TextEditingController();
        return StatefulBuilder(builder: (context, setStateDialog) {
          final bool showComment = rating <= 2 && rating > 0;
          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18.0, vertical: 16.0),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Enjoying the Digital LED app ?',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600))),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            commentCtrl.dispose();
                            Navigator.of(ctx).pop();
                          })
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(
                        height: 100,
                        child: Center(
                            child: Container(
                                width: 120,
                                height: 80,
                                decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Center(
                                    child: Icon(Icons.thumb_up_alt_outlined,
                                        size: 36, color: Colors.amber))))),
                    const SizedBox(height: 12),
                    Column(children: [
                      const Text('Rate your experience with Digital LED app',
                          style:
                              TextStyle(fontSize: 13, color: Colors.black54)),
                      const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (i) {
                            final starIndex = i + 1;
                            final filled = starIndex <= rating;
                            return GestureDetector(
                              onTap: () =>
                                  setStateDialog(() => rating = starIndex),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6.0),
                                  child: Icon(
                                      filled ? Icons.star : Icons.star_border,
                                      size: 36,
                                      color: filled
                                          ? Colors.amber
                                          : Colors.grey[400])),
                            );
                          })),
                      const SizedBox(height: 8),
                      Text(
                          rating == 0
                              ? 'Not rated yet'
                              : (rating <= 2
                                  ? '$rating - Bad'
                                  : (rating == 3
                                      ? '$rating - Okay'
                                      : '$rating - Great')),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 12),
                    if (showComment) ...[
                      TextField(
                          controller: commentCtrl,
                          maxLines: 4,
                          decoration: InputDecoration(
                              hintText:
                                  'Tell us more about your experience (Optional)',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12))),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber[700],
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: () {
                          final comment = commentCtrl.text.trim();
                          if (rating == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Please select star rating before submitting')));
                            return;
                          }
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                              content: Text(
                                  'Thanks! Rating: $rating ${comment.isEmpty ? '' : '- comment saved'}')));
                          commentCtrl.dispose();
                        },
                        child: Text(showComment ? 'Submit' : 'Submit',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ]),
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _openPlayStore() async {
    final play = Uri.parse('market://details?id=com.example.myapp');
    final web = Uri.parse(
        'https://play.google.com/store/apps/details?id=com.example.myapp');
    if (await canLaunchUrl(play)) {
      await launchUrl(play);
    } else {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  void _shareAppLink(String appLink) {
    Share.share('Check out this awesome app!\n\n$appLink',
        subject: 'Digital LED Signboard');
  }

  Future<void> _pickBackgroundImageFromGallery() async {
    final XFile? x =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => bgImageFile = File(x.path));
  }

  Future<void> _pickBackgroundImageFromCamera() async {
    final XFile? x =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x != null) setState(() => bgImageFile = File(x.path));
  }

  Future<void> _showImagePickChooser() async {
    showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickBackgroundImageFromGallery();
                  }),
              ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Camera'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickBackgroundImageFromCamera();
                  }),
              ListTile(
                  leading: const Icon(Icons.clear),
                  title: const Text('Clear background'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() => bgImageFile = null);
                  }),
            ]),
          );
        });
  }

  Future<Uint8List?> _capturePreviewPngBytes() async {
    try {
      final boundary = previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('capture error: $e');
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

  Future<Uint8List?> _recordGifBytes(
      {int durationSeconds = 2, int fps = 6, int maxWidth = 720}) async {
    if (isRecording) return null;
    setState(() {
      isRecording = true;
      _disableGlowForCapture = true;
    });
    try {
      // small delay to let UI update without glow
      await Future.delayed(const Duration(milliseconds: 80));
      final boundary = previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final totalFrames = (durationSeconds * fps).clamp(1, 200).toInt();
      final frameDelayMs = (1000 / fps).round();
      final frames = <img.Image>[];
      // initial settle
      await Future.delayed(const Duration(milliseconds: 50));

      for (int i = 0; i < totalFrames; i++) {
        try {
          final ui.Image uiImage = await boundary.toImage(pixelRatio: 1.0);
          final ByteData? bd =
              await uiImage.toByteData(format: ui.ImageByteFormat.png);
          if (bd != null) {
            final img.Image? frame = img.decodeImage(bd.buffer.asUint8List());
            if (frame != null) {
              final resized = frame.width > maxWidth
                  ? img.copyResize(frame, width: maxWidth)
                  : frame;
              frames.add(resized);
            }
          }
        } catch (e) {
          debugPrint('frame capture error: $e');
        }
        if (i < totalFrames - 1)
          await Future.delayed(Duration(milliseconds: frameDelayMs));
      }
      if (frames.isEmpty) return null;
      final encoder = img.GifEncoder();
      final delayCs = (frameDelayMs / 10).round();
      for (final f in frames) {
        encoder.addFrame(f, duration: delayCs);
      }
      final out = encoder.finish();
      return out;
    } catch (e) {
      debugPrint('GIF encode error: $e');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _disableGlowForCapture = false;
          isRecording = false;
        });
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _recordAndShareGif() async {
    if (isRecording) return _showSnack('Busy — try again shortly.');
    _showSnack('Recording GIF (short)...');
    final bytes = await _recordGifBytes(durationSeconds: 3, fps: 6);
    if (bytes == null)
      return _showSnack(
          'Failed to record GIF — try lower FPS or ensure preview fully visible.');
    final tmp = await getTemporaryDirectory();
    final file = await File(
            '${tmp.path}/led_${DateTime.now().millisecondsSinceEpoch}.gif')
        .writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: 'LED preview (GIF)');
  }

  Future<void> _recordAndSaveGif() async {
    if (isRecording) return _showSnack('Busy — try again shortly.');
    _showSnack('Recording GIF (short)...');
    final bytes = await _recordGifBytes(durationSeconds: 3, fps: 6);
    if (bytes == null)
      return _showSnack(
          'Failed to record GIF — try lower FPS or ensure preview fully visible.');
    final dir = await getApplicationDocumentsDirectory();
    final file = await File(
            '${dir.path}/led_${DateTime.now().millisecondsSinceEpoch}.gif')
        .writeAsBytes(bytes);
    _showSnack('Saved GIF to ${file.path}');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addToHistory(String t) {
    if (t.trim().isEmpty) return;
    if (!history.contains(t)) setState(() => history.insert(0, t));
  }

  void _deleteHistoryAt(int index) {
    setState(() => history.removeAt(index));
  }

  void _handlePreviewCameraPressed() => _showImagePickChooser();
  Future<void> pickImageFromPanel() => _showImagePickChooser();

  void _openFullscreenPreview() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) {
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
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Preview', style: TextStyle(color: Colors.white)),
        leading: IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: _openBottomMenu),
        actions: [
          IconButton(
              icon: const Icon(Icons.screen_rotation_alt),
              onPressed: _openFullscreenPreview)
        ],
      ),
      body: SafeArea(
        child: Column(children: [
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
            glow: !_disableGlowForCapture,
            onPickBackgroundImage: (file) {
              if (file == null) {
                _showImagePickChooser();
              } else {
                setState(() => bgImageFile = file);
              }
            },
          ),
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
                history: history,
                isBusy: isRecording,
                playing: playing,
                isFavorite: false,
                onTextChanged: (v) {
                  setState(() {
                    displayText = v;
                    _addToHistory(v);
                  });
                },
                onSpeedChanged: (v) => setState(() => speed = v),
                onTextSizeChanged: (v) => setState(() => textSize = v),
                onToggleBlinkText: (b) => setState(() => blinkText = b),
                onToggleBlinkBackground: (b) =>
                    setState(() => blinkBackground = b),
                onTogglePlay: () => setState(() => playing = !playing),
                onSetDirection: (d) => setState(() => scrollDirection = d),
                onPickBackgroundImage: (f) => setState(() => bgImageFile = f),
                onPickTextColor: (c) => setState(() => textColor = c),
                onPickBackgroundColor: (c) =>
                    setState(() => backgroundColor = c),
                onUseGradientChanged: (b) => setState(() => useGradient = b),
                onUseLedDotsChanged: (b) => setState(() => useLedDots = b),
                onShare: _recordAndShareGif,
                onDownload: _recordAndSaveGif,
                onSharePng: _sharePreviewAsPng,
                onDownloadPng: _savePreviewPng,
                onOpenImagePicker: _showImagePickChooser,
                onDeleteHistoryAt: _deleteHistoryAt,
                onPickHistoryItem: (s) {
                  setState(() {
                    displayText = s;
                    textController.text = s;
                  });
                },
                onShareApp: () => _shareAppLink(
                    "https://play.google.com/store/apps/details?id=com.example.myapp"),
                onToggleFavorite: () {
                  _showSnack('Toggled favorite (not persisted)');
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
