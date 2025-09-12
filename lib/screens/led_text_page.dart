// lib/led_scroller_screen.dart
// NOTE: Add required packages to pubspec.yaml:
// flutter_tts, http, flutter_colorpicker, image_picker, share_plus,
// path_provider, speech_to_text, url_launcher
//
// Example (run flutter pub get after adding):
// dependencies:
//   flutter_tts: ^3.6.0
//   http: ^0.13.6
//   flutter_colorpicker: ^1.0.3
//   image_picker: ^0.8.7+4
//   share_plus: ^6.3.0
//   path_provider: ^2.0.14
//   speech_to_text: ^5.6.0
//   url_launcher: ^6.1.10

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:led_digital_scroll/screens/privacy_policy.dart';

import 'package:share_plus/share_plus.dart';
import 'package:flutter/scheduler.dart'; // Ticker
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

class LedTestPage extends StatefulWidget {
  const LedTestPage({super.key});

  @override
  State<LedTestPage> createState() => _LedTextPageState();
}

class _LedTextPageState extends State<LedTestPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // UI state
  String displayText = "Dasu@735";
  double speed = 50; // slider 10..200 (we map to px/sec)
  double textSize = 120; // used to derive dot size
  Color textColor = Colors.green;
  Color backgroundColor = const Color.fromARGB(255, 255, 254, 254);
  bool useAudio = false;
  bool blinkText = false;
  bool blinkBackground = false;
  double blinkSpeed = 10;

  bool _visible = true; // For blinking
  int scrollDirection = 1; // 1 = right, -1 = left, 0 = stop
  bool _playing = true; // for play/pause toggle

  // Background options
  File? bgImageFile;
  bool useGradient = false;
  bool useLedDots = false;

  // History & favorites
  final TextEditingController _textController = TextEditingController();
  List<String> history = [];
  Set<String> favorites = {};
  bool showHistoryCard = false;

  // Audio/history related
  List<String> audioHistory = [];
  bool showAudioCard = false;

  // speech-to-text
  late final SpeechToText _speech;
  bool _speechAvailable = false;
  bool _listening = false;
  String _lastWords = '';

  // Dot-matrix generation
  Future<List<List<bool>>>? _matrixFuture;
  // visual parameters derived from textSize
  double get _dotSize => math.max(2.0, textSize / 16.0);
  double get _spacing => math.max(0.0, _dotSize / 3.0);

  // Blink controller
  late AnimationController _blinkController;

  // ValueNotifier so fullscreen page can listen to blink visibility
  late ValueNotifier<bool> _visibleNotifier;

  // Scroll controller for the control panel (so only it scrolls)
  late final ScrollController _controlsScrollController;

  // rotation for preview only
  bool _previewRotated = false;

  // optional metrics debounce
  Timer? _metricsDebounce;

  // === AI / TTS fields ===
  late final FlutterTts _flutterTts;
  bool _aiInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _textController.text = displayText;
    _controlsScrollController = ScrollController();

    _visibleNotifier = ValueNotifier<bool>(_visible);

    _blinkController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (1000 / math.max(1, blinkSpeed)).round(),
      ),
    )..addListener(() {
        if (blinkText || blinkBackground) {
          final newVisible = _blinkController.value < 0.5;
          // update both local state and notifier
          if (newVisible != _visible) {
            _visible = newVisible;
            _visibleNotifier.value = _visible;
            if (mounted) setState(() {});
          }
        } else {
          if (!_visible) {
            _visible = true;
            _visibleNotifier.value = _visible;
            if (mounted) setState(() => _visible = true);
          }
        }
      });
    _blinkController.repeat();

    // init flutter_tts
    _flutterTts = FlutterTts();
    _flutterTts.setSpeechRate(0.95);
    _flutterTts.setPitch(1.0);
    try {
      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() {});
      });
    } catch (_) {
      // older/newer APIs may differ; ignore if not available
    }

    // init speech-to-text instance (actual initialize is async)
    _speech = SpeechToText();
    _initSpeech();

    _generateMatrix();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _metricsDebounce?.cancel();
    _blinkController.dispose();
    _visibleNotifier.dispose();
    _textController.dispose();
    _controlsScrollController.dispose();
    // stop TTS
    _flutterTts.stop();
    // stop speech if still active
    if (_listening) {
      _speech.stop();
    }
    // restore orientations if you changed them elsewhere
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // debounce matrix regeneration
    _metricsDebounce?.cancel();
    _metricsDebounce = Timer(const Duration(milliseconds: 200), () {
      _generateMatrix();
    });
  }

  // regenerate matrix when inputs change
  void _generateMatrix() {
    if (!mounted) return;
    setState(() {
      final fontSizeForRaster = math.max(24.0, textSize * 2.5);

      _matrixFuture = textToDotMatrix(
        text: displayText.isEmpty ? " " : displayText,
        textStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: fontSizeForRaster,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        scale: 1.0,
        maxWidth: 3000,
        maxHeight: 1200,
        dotPixelSize: (_dotSize + _spacing),
      );
    });
  }

  // toggle only the preview rotation (90° clockwise each press)
  void _togglePreviewRotation() {
    if (!mounted) return;
    setState(() {
      _previewRotated = !_previewRotated;
    });
    // regenerate matrix since layout changed visually
    _generateMatrix();
  }

  // New: open a fullscreen rotated preview route that fills the whole device screen
  void _openFullscreenRotatedPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return FullscreenRotatedPreview(
            matrixFuture: _matrixFuture,
            dotSize: _dotSize,
            spacing: _spacing,
            onColor: textColor,
            offColor: Colors.transparent,
            glow: true,
            speedPxPerSec: (speed / 200.0) * 90.0 + 12.0,
            playing: scrollDirection == 0 ? false : _playing,
            directionLeft: scrollDirection == -1,
            // pass the concrete background parameters rather than a builder
            bgImageFile: bgImageFile,
            useGradient: useGradient,
            useLedDots: true,
            backgroundColor: backgroundColor,
            blinkText: true,
            blinkBackground: true,
            visibleListenable: _visibleNotifier,
            textColor: textColor,
          );
        },
      ),
    );
  }

  // ===== Drawer helpers =====
  void _openRateDialog() =>
      showDialog(context: context, builder: (_) => const _RateAppDialog());

  void _toggleFavorite() {
    if (!mounted) return;
    setState(() {
      if (favorites.contains(displayText)) {
        favorites.remove(displayText);
      } else {
        favorites.add(displayText);
      }
    });
  }

  Future<void> _pickBackgroundImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      setState(() {
        bgImageFile = File(image.path);
        useGradient = false;
        useLedDots = false;
      });
    }
  }

  Widget _buildBackgroundSnapshot({required bool visibleOverride}) {
    // snapshot background widget for main preview; uses current state
    if (bgImageFile != null) {
      return Image.file(bgImageFile!, fit: BoxFit.cover);
    } else if (useGradient) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue, Colors.purple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    } else if (useLedDots) {
      return CustomPaint(
        painter: LedBackgroundPainter(),
        child: Container(color: backgroundColor),
      );
    } else {
      return Container(
        color: blinkBackground && !visibleOverride ? Colors.black : backgroundColor,
      );
    }
  }

  void _pickColor(bool isText) async {
    Color tempColor = isText ? textColor : backgroundColor;
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Text(
            "Pick a ${isText ? "Text" : "Background"} Color",
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: tempColor,
              onColorChanged: (color) => tempColor = color,
            ),
          ),
          actions: [
            TextButton(
              child: const Text("OK", style: TextStyle(color: Colors.white)),
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  if (isText) {
                    textColor = tempColor;
                  } else {
                    backgroundColor = tempColor;
                  }
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _shareAppLink(String appLink) {
    Share.share(
      'Check out this awesome app!\n\n$appLink',
      subject: 'Digital LED Signboard',
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF121214),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            const SizedBox(height: 8),
            const ListTile(
              title: Text(
                'Digital LED Signboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.star_rate_rounded, color: Colors.white),
              title: const Text(
                'Rate App',
                style: TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.pop(context);
                _openRateDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text(
                'Share App',
                style: TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.pop(context);
                _shareAppLink(
                  "https://play.google.com/store/apps/details?id=com.example.myapp",
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.privacy_tip_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Privacy Policy',
                style: TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PrivacyPolicy()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text input + history + favorite
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.history,
                  color: Color.fromARGB(255, 248, 247, 247),
                  size: 30,
                ),
                onPressed: () => setState(() => showHistoryCard = !showHistoryCard),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(
                    color: Color.fromARGB(255, 36, 35, 35),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color.fromARGB(255, 55, 55, 55),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    hintText: "Enter text...",
                    hintStyle: const TextStyle(color: Colors.grey),
                  ),
                  onChanged: (value) {
                    displayText = value;
                    if (value.isNotEmpty && !history.contains(value)) history.add(value);
                    _generateMatrix();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  favorites.contains(displayText) ? Icons.star : Icons.star_border,
                  color: favorites.contains(displayText) ? Colors.amber : Colors.white,
                  size: 30,
                ),
                onPressed: _toggleFavorite,
              ),
            ],
          ),

          if (showHistoryCard) ...[
            const SizedBox(height: 10),
            Card(
              color: Colors.grey[850],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: history.map((t) {
                    return ListTile(
                      leading: const Icon(Icons.history, color: Colors.white),
                      title: Text(t, style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        displayText = t;
                        _textController.text = t;
                        showHistoryCard = false;
                        _generateMatrix();
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Move / Play buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(Icons.play_arrow, () {
                setState(() {
                  scrollDirection = -1;
                  _playing = true;
                });
              }, flip: true),
              _buildActionButton(_playing ? Icons.pause : Icons.play_arrow, () {
                setState(() {
                  _playing = !_playing;
                  scrollDirection = _playing ? (scrollDirection == 0 ? 1 : scrollDirection) : 0;
                });
              }),
              _buildActionButton(Icons.play_arrow, () {
                setState(() {
                  scrollDirection = 1;
                  _playing = true;
                });
              }),
            ],
          ),

          const SizedBox(height: 5),

          // Speed slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const Text(
                  "Speed",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: speed,
                    min: 10,
                    max: 200,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey,
                    onChanged: (val) => setState(() => speed = val),
                  ),
                ),
                Text(
                  "${speed.toInt()} Px",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Size slider -> affects dot size and regenerates matrix
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              height: 33,
              width: double.infinity,
              child: Row(
                children: [
                  const Text(
                    "Size   ",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: textSize,
                      min: 20,
                      max: 200,
                      activeColor: Colors.green,
                      inactiveColor: Colors.grey,
                      onChanged: (val) => setState(() {
                        textSize = val;
                        // regenerate matrix live for immediate visual feedback
                        _generateMatrix();
                      }),
                      onChangeEnd: (val) {
                        textSize = val;
                        // ensure final commit
                        _generateMatrix();
                      },
                    ),
                  ),
                  Text(
                    "${textSize.toInt()} Px",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Color pickers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const Text(
                "Colors",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(
                height: 37,
                width: 114,
                child: ElevatedButton(
                  onPressed: () => _pickColor(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                  ),
                  child: const Text(
                    "Text",
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
              SizedBox(
                height: 37,
                width: 115,
                child: ElevatedButton(
                  onPressed: () => _pickColor(false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                  ),
                  child: const Text(
                    "Background",
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Background toggles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                height: 30,
                width: 95,
                child: ElevatedButton(
                  onPressed: () => setState(() {
                    bgImageFile = null;
                    useGradient = false;
                    useLedDots = false;
                  }),
                  child: const Text("Solid"),
                ),
              ),
              SizedBox(
                height: 30,
                width: 105,
                child: ElevatedButton(
                  onPressed: () => setState(() {
                    bgImageFile = null;
                    useGradient = true;
                    useLedDots = false;
                  }),
                  child: const Text("Gradient"),
                ),
              ),
              SizedBox(
                height: 30,
                width: 95,
                child: ElevatedButton(
                  onPressed: () => setState(() {
                    bgImageFile = null;
                    useGradient = false;
                    useLedDots = true;
                  }),
                  child: const Text("LED"),
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          // Audio toggle/button
          Container(
            height: 30,
            width: 160,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    showAudioCard = !showAudioCard;
                    useAudio = showAudioCard;
                  }),
                  icon: const Icon(Icons.volume_up, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Text("Use Audio", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),

          // ======= UPDATED AI AUDIO CARD START =======
          if (showAudioCard) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 15,),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                       Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    Tooltip(
      message: 'AI Assistance' ,
      child: SizedBox(
        height: 60,
        width: 60,
        child: ElevatedButton(
          onPressed: _aiInProgress ? null : _generateAiAudioForCurrentText,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(35),
            ),
          ),
          child: Image.asset(
            'assets/icons/ai.png',
            width: 45,
            height: 45,
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
    const SizedBox(height: 6),
    const Text(
      'AIAssistance',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12, color: Colors.black),
      textAlign: TextAlign.center,
                       ),
                    ],
                       ),


                        const SizedBox(width: 8),
                        Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox(
      height: 60,
      width: 60,
      child: ElevatedButton(
        onPressed: _openVideoSearchDialog,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(35),
          ),
        ),
        child: Image.asset(
          'assets/icons/brow.png',
          width: 45,
          height: 45,
          fit: BoxFit.contain,
        ),
      ),
    ),
    const SizedBox(height: 6),
    const Text(
      'Browser',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12, color: Colors.black),
      textAlign: TextAlign.center,
    ),
  ],
),


                        const SizedBox(width: 8),
                        Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    Tooltip(
      message: 'Microphone',
      child: SizedBox(
        height: 60,
        width: 60,
        child: ElevatedButton(
          onPressed: _speechAvailable ? _toggleListening : _initSpeech,
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(35),
            ),
            backgroundColor: _listening ? Colors.redAccent : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/icons/micro.png',
                width: 45,
                height: 45,
                fit: BoxFit.contain,
                color: _listening ? Colors.white : null,
              ),
              if (_listening)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.8),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: 70, // same width as button so text wraps/centers nicely
      child: Text(
        'Microphone', // newline keeps it readable under the narrow button
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: _listening ? Colors.redAccent : Colors.black,
          height: 1.05,
        ),
      ),
    ),
  ],
),
SizedBox(width: 8),
                      ],
                    ),

                    const SizedBox(height: 8),
                    if (audioHistory.isEmpty)
                      const ListTile(title: Text("", style: TextStyle(color: Colors.black)))
                    else
                      Column(
                        children: audioHistory.map((a) {
                          final index = audioHistory.indexOf(a);
                          return ListTile(
                            leading: const Icon(Icons.audiotrack, color: Colors.black),
                            title: Text(
                              a,
                              style: const TextStyle(color: Colors.black),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('AI clip ${index + 1}', style: const TextStyle(color: Colors.black)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _playText(a),
                                  icon: const Icon(Icons.play_arrow, color: Colors.black),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      audioHistory.removeAt(index);
                                    });
                                  },
                                  icon: const Icon(Icons.delete, color: Colors.black),
                                ),
                              ],
                            ),
                            onTap: () => _playText(a),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
           Container(
            height: 32,
            width: 200,
            child: CheckboxListTile(
              activeColor: Colors.green,
              value: blinkText,
              onChanged: (val) => setState(() {
                blinkText = val ?? false;
                if (blinkText || blinkBackground) {
                  _blinkController.repeat();
                } else {
                  // stop blinking and ensure visible true
                  _visible = true;
                  _visibleNotifier.value = true;
                }
              }),
              title: const Text("Blink Text", style: TextStyle(color: Colors.white)),
            ),
          ),

          const SizedBox(height: 5),

          Container(
            height: 32,
            width: 250,
            child: CheckboxListTile(
              title: const Text("Blink Background", style: TextStyle(color: Colors.white)),
              activeColor: Colors.green,
              value: blinkBackground,
              onChanged: (val) => setState(() {
                blinkBackground = val ?? false;
                if (blinkText || blinkBackground) {
                  _blinkController.repeat();
                } else {
                  _visible = true;
                  _visibleNotifier.value = true;
                }
              }),
            ),
          ),

          // Blink speed
          Container(
            height: 55,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  const Text("Blink Speed", style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: blinkSpeed,
                      min: 1,
                      max: 20,
                      activeColor: Colors.green,
                      inactiveColor: Colors.grey,
                      onChanged: (val) => setState(() => blinkSpeed = val),
                      onChangeEnd: (val) {
                        blinkSpeed = val;
                        _blinkController.duration = Duration(
                          milliseconds: (1000 / math.max(1, blinkSpeed)).round(),
                        );
                        _blinkController.repeat();
                      },
                    ),
                  ),
                  Text("${blinkSpeed.toInt()}", style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 2),

          // Share / Download
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                height: 37,
                width: 130,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _shareAppLink(
                      "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_1MB.mp4",
                    );
                  },
                  icon: const Icon(Icons.share, color: Colors.white),
                  label: const Text("Share", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                ),
              ),
              SizedBox(
                height: 37,
                width: 130,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.download, color: Colors.white),
                  label: const Text("Download", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    VoidCallback onTap, {
    Color color = const Color.fromARGB(255, 0, 0, 0),
    bool flip = false,
  }) {
    return SizedBox(
      height: 35,
      width: 80,
      child: IconButton(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(const Color.fromARGB(66, 77, 76, 76)),
          shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        ),
        onPressed: onTap,
        icon: Transform(
          alignment: Alignment.center,
          transform: flip ? Matrix4.rotationY(3.1416) : Matrix4.identity(),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }

  // === AI / TTS helper methods ===

  /// Call your backend which returns a short AI reply (JSON: { "reply": "..." }).
  /// Replace the URL with your real backend endpoint.
  Future<String> _fetchAiReply(String prompt) async {
    if (prompt.trim().isEmpty) return "No text provided";

    if (mounted) setState(() => _aiInProgress = true);
    try {
      final uri = Uri.parse('https://your-backend.example.com/assistant/reply');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );
      if (resp.statusCode == 200) {
        final js = jsonDecode(resp.body);
        final reply = (js['reply'] ?? '').toString();
        return reply.isEmpty ? 'Sorry, no reply.' : reply;
      } else {
        return 'AI request failed: ${resp.statusCode}';
      }
    } catch (e) {
      return 'AI request error';
    } finally {
      if (mounted) setState(() => _aiInProgress = false);
    }
  }

  /// Generate AI reply for current displayText, add to audioHistory, and play via TTS.
  Future<void> _generateAiAudioForCurrentText() async {
    final prompt = displayText.isEmpty ? _textController.text : displayText;
    final reply = await _fetchAiReply(prompt);

    if (!mounted) return;
    // add to history (most recent first)
    setState(() {
      audioHistory.insert(0, reply);
      showAudioCard = true;
      useAudio = true;
    });

    // play using TTS
    await _playText(reply);
  }

  Future<void> _playText(String text) async {
    if (text.trim().isEmpty) return;
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  // === Speech-to-text helpers ===
  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          // keep listening state in sync
          if (status == 'done' || status == 'notListening') {
            if (_listening && mounted) {
              setState(() => _listening = false);
            }
          }
        },
        onError: (error) {
          // ignore for now
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      _speechAvailable = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Speech recognition unavailable')),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _listening = true;
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _lastWords = result.recognizedWords;
          // update main text and regenerate matrix in real-time
          displayText = _lastWords;
          _textController.text = _lastWords;
          _generateMatrix();
        });
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: null, // system default
      onSoundLevelChange: null,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
    });
    _generateMatrix();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  // === Video search / browser helpers ===

  Future<void> _openVideoSearchDialog() async {
    final controller = TextEditingController(text: displayText.isNotEmpty ? displayText : _textController.text);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Search Videos'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter search query'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final query = controller.text.trim();
                Navigator.of(context).pop();
                if (query.isNotEmpty) _launchYouTubeSearch(query);
              },
              child: const Text('Open in Browser'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchYouTubeSearch(String query) async {
    final url = Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
    if (!await canLaunchUrl(url)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open browser')));
      return;
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  // Build preview -> use FutureBuilder to render the matrix and LedScroller
  @override
  Widget build(BuildContext context) {
    final double velocity = (speed / 200.0) * 180.0 + 12.0;
    const double previewHeight = 195.0; // requested preview height

    // When preview is rotated, we give the inner scroller a square-ish area
    // so that RotatedBox displays it vertically.
    final innerPreviewWidthWhenRotated = previewHeight;
    final innerPreviewHeightWhenRotated = MediaQuery.of(context).size.width - 32;

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: _buildDrawer(),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Center(
          child: Text('Preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.screen_rotation_alt),
            onPressed: _openFullscreenRotatedPreview,
            tooltip: 'Open rotated preview full screen',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Preview box
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(border: Border.all(color: Colors.blue, width: 2)),
                height: previewHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildBackgroundSnapshot(visibleOverride: _visible),
                    Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: (blinkText && !_visible) ? 0 : 1,
                        child: FutureBuilder<List<List<bool>>>(
                          future: _matrixFuture,
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const SizedBox(
                                width: double.infinity,
                                height: 40,
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            if (snap.hasError || snap.data == null) {
                              return Text('Error creating matrix', style: TextStyle(color: textColor));
                            }

                            final matrix = snap.data!;
                            final rows = matrix.length;
                            final visualHeight = rows * (_dotSize + _spacing);

                            final playing = scrollDirection == 0 ? false : _playing;
                            final directionLeft = scrollDirection == -1;

                            final dotSize = _dotSize;
                            final spacing = _spacing;

                            final usedHeight = visualHeight.clamp(1.0, previewHeight);

                            Widget scrollerBox = SizedBox(
                              width: double.infinity,
                              height: usedHeight,
                              child: LedScroller(
                                matrix: matrix,
                                dotSize: dotSize,
                                spacing: spacing,
                                onColor: textColor,
                                offColor: Colors.transparent,
                                glow: true,
                                speedPxPerSec: velocity,
                                playing: playing,
                                directionLeft: directionLeft,
                              ),
                            );

                            if (!_previewRotated) {
                              return Align(alignment: Alignment.center, child: scrollerBox);
                            } else {
                              final rotatedInner = SizedBox(
                                width: innerPreviewWidthWhenRotated,
                                height: innerPreviewHeightWhenRotated.clamp(1.0, 1000.0),
                                child: Center(child: scrollerBox),
                              );
                              return RotatedBox(quarterTurns: 1, child: rotatedInner);
                            }
                          },
                        ),
                      ),
                    ),
                   Positioned(
  bottom: 8,
  right: 8,
  child: GestureDetector(
    onTap: _pickBackgroundImage,
    child: Container(
      height: 36,
      width: 36,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.asset(
        'assets/icons/camera.png', // <-- use your file name here
        color: Colors.white,            // makes it white like the icon
        fit: BoxFit.contain,
      ),
    ),
  ),
),

                  ],
                ),
              ),
            ),

            // Controls (scrollable) - only this area scrolls.
            Expanded(
              child: SingleChildScrollView(
                controller: _controlsScrollController,
                primary: false,
                padding: EdgeInsets.fromLTRB(10, 10, 10, MediaQuery.of(context).viewInsets.bottom + 10),
                child: _buildControlPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen rotated preview page — reuses matrix + rendering parameters
class FullscreenRotatedPreview extends StatelessWidget {
  final Future<List<List<bool>>>? matrixFuture;
  final double dotSize;
  final double spacing;
  final Color onColor;
  final Color offColor;
  final bool glow;
  final double speedPxPerSec;
  final bool playing;
  final bool directionLeft;

  // background props (snapshot at time of opening)
  final File? bgImageFile;
  final bool useGradient;
  final bool useLedDots;
  final Color backgroundColor;

  // blink props & notifier
  final bool blinkText;
  final bool blinkBackground;
  final ValueNotifier<bool> visibleListenable;

  // text color
  final Color textColor;

  const FullscreenRotatedPreview({
    super.key,
    required this.matrixFuture,
    required this.dotSize,
    required this.spacing,
    required this.onColor,
    required this.offColor,
    this.glow = true,
    this.speedPxPerSec = 80,
    this.playing = true,
    this.directionLeft = true,
    required this.bgImageFile,
    this.useGradient = false,
    this.useLedDots = false,
    required this.backgroundColor,
    this.blinkText = false,
    this.blinkBackground = false,
    required this.visibleListenable,
    required this.textColor,
  });

  Widget _buildBackgroundWidget(bool visible) {
    if (bgImageFile != null) {
      return Image.file(bgImageFile!, fit: BoxFit.cover);
    } else if (useGradient) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue, Colors.purple], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
      );
    } else if (useLedDots) {
      return CustomPaint(painter: LedBackgroundPainter(), child: Container(color: backgroundColor));
    } else {
      return Container(color: blinkBackground && !visible ? Colors.black : backgroundColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final screenH = media.size.height;

    final innerWidth = screenH;
    final innerHeight = screenW;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: visibleListenable,
          builder: (context, visible, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildBackgroundWidget(visible),
                Center(
                  child: FutureBuilder<List<List<bool>>>(
                    future: matrixFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError || snap.data == null) {
                        return Text('Error creating matrix', style: TextStyle(color: onColor));
                      }
                      final matrix = snap.data!;
                      final scroller = SizedBox(
                        width: innerWidth,
                        height: innerHeight,
                        child: LedScroller(
                          matrix: matrix,
                          dotSize: dotSize,
                          spacing: spacing,
                          onColor: onColor,
                          offColor: offColor,
                          glow: glow,
                          speedPxPerSec: speedPxPerSec,
                          playing: playing,
                          directionLeft: directionLeft,
                        ),
                      );

                      final textOpacity = (blinkText && !visible) ? 0.0 : 1.0;

                      return AnimatedOpacity(duration: const Duration(milliseconds: 120), opacity: textOpacity, child: RotatedBox(quarterTurns: 1, child: scroller));
                    },
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.of(context).pop()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// LED Dot painter for background pattern
class LedBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.redAccent.withOpacity(0.3)..style = PaintingStyle.fill;
    const double dotRadius = 3;
    const double gap = 12;
    for (double y = gap; y < size.height; y += gap) {
      for (double x = gap; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ========= LedScroller & helpers =========

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

class _LedScrollerState extends State<LedScroller> with SingleTickerProviderStateMixin {
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
    return LayoutBuilder(builder: (context, constraints) {
      final rows = widget.matrix.length;
      final cols = widget.matrix.isNotEmpty ? widget.matrix[0].length : 0;
      final baseDot = widget.dotSize;
      final baseSpacing = widget.spacing;

      final desiredHeight = rows * (baseDot + baseSpacing);
      final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : desiredHeight;

      final scaleY = desiredHeight > 0 ? math.min(1.0, availableHeight / desiredHeight) : 1.0;
      final renderDot = baseDot * scaleY;
      final renderSpacing = baseSpacing * scaleY;

      final renderTotalWidth = cols * (renderDot + renderSpacing);
      final usedContentWidth = math.max(1.0, renderTotalWidth.toDouble());
      contentWidth = usedContentWidth;

      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width - 16;

      final renderHeight = rows * (renderDot + renderSpacing);
      final constrainedHeight = math.max(1.0, renderHeight.clamp(1.0, availableHeight));

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
              contentWidth: usedContentWidth,
            ),
            size: Size(width, constrainedHeight),
          ),
        ),
      );
    });
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

    final draws = <double>[-offset, -offset + contentWidth];

    for (final baseShift in draws) {
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final on = matrix[r][c];
          final cx = baseShift + c * (dotSize + spacing) + dotSize / 2;
          final cy = r * (dotSize + spacing) + dotSize / 2;

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

/// textToDotMatrix: rasterizes text and samples luminance to build a boolean matrix.
Future<List<List<bool>>> textToDotMatrix({
  required String text,
  required TextStyle textStyle,
  double scale = 1.0,
  int maxWidth = 2000,
  int maxHeight = 800,
  required double dotPixelSize,
}) async {
  final tp = TextPainter(text: TextSpan(text: text, style: textStyle), textDirection: TextDirection.ltr);
  tp.layout();

  final logicalWidth = tp.width == 0 ? 1.0 : tp.width;
  final logicalHeight = tp.height == 0 ? 1.0 : tp.height;

  final scaledW = (logicalWidth * scale).clamp(1, maxWidth).toInt();
  final scaledH = (logicalHeight * scale).clamp(1, maxHeight).toInt();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, scaledW.toDouble(), scaledH.toDouble()));

  canvas.drawRect(Rect.fromLTWH(0, 0, scaledW.toDouble(), scaledH.toDouble()), Paint()..color = Colors.transparent);

  final scaleX = scaledW / logicalWidth;
  final scaleY = scaledH / logicalHeight;
  final textScale = math.min(scaleX, scaleY);

  canvas.save();
  canvas.scale(textScale, textScale);
  tp.paint(canvas, Offset.zero);
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

  List<List<bool>> matrix = List.generate(safeRows, (_) => List.filled(safeCols, false));

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
      matrix[r][c] = avg > 30; // threshold (tweakable)
    }
  }

  return matrix;
}

/// ====== Rate dialog ======
class _RateAppDialog extends StatefulWidget {
  const _RateAppDialog();

  @override
  State<_RateAppDialog> createState() => _RateAppDialogState();
}

class _RateAppDialogState extends State<_RateAppDialog> {
  int rating = 0;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color.fromARGB(255, 198, 200, 202),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Rate App'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            children: List.generate(
              5,
              (i) => IconButton(
                onPressed: () => setState(() => rating = i + 1),
                icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber, size: 30),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Leave a note (optional)',
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thanks for rating $rating★')));
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}