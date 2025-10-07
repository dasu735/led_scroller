// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:marquee/marquee.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const MaterialApp(home: LedAiPage()));
}

/// Fake streaming AI service (word-by-word).
/// Replace with real streaming service as required.
class FakeWebSocketService {
  Stream<String> requestStream(String requestId, String payload) async* {
    final text = "Here's a songified reply to: $payload";
    final parts = text.split(RegExp(r'\s+'));
    for (int i = 0; i < parts.length; i++) {
      await Future.delayed(const Duration(milliseconds: 110));
      yield parts[i] + (i < parts.length - 1 ? ' ' : '');
    }
  }
}

/// AiAudioCard: handles speech -> final transcript, streaming AI replies, and TTS "Sing".
class AiAudioCard extends StatefulWidget {
  final ValueChanged<String>? onTranscribed; // parent receives live/finished text
  final ValueChanged<String>? onAiAction; // notify parent of payload sent
  final Stream<String>? Function(String payload)? aiResponseStreamBuilder;

  const AiAudioCard({
    super.key,
    this.onTranscribed,
    this.onAiAction,
    this.aiResponseStreamBuilder,
  });

  @override
  State<AiAudioCard> createState() => _AiAudioCardState();
}

enum SingingVoice { male, female }

class _AiAudioCardState extends State<AiAudioCard> {
  // Speech
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool listening = false;
  String _partialSpoken = '';

  // AI streaming
  bool aiInProgress = false;
  String _partialAi = '';
  StreamSubscription<String>? _aiSub;

  // TTS for AI replies (optional)
  late FlutterTts _tts;
  bool _ttsReady = false;

  // voice selection
  SingingVoice _selectedVoice = SingingVoice.female;

  // History (song outputs)
  final List<String> audioHistory = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
    _tts = FlutterTts();
    _initTts();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => listening = status == 'listening');
        },
        onError: (err) {
          debugPrint('speech error: $err');
          if (!mounted) return;
          setState(() => listening = false);
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = available);
    } catch (e) {
      debugPrint('init speech failed: $e');
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speech not available')));
        return;
      }
    }
    setState(() => _partialSpoken = '');
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() => _partialSpoken = result.recognizedWords);
          if (result.finalResult) {
            _onFinalSpoken(_partialSpoken);
            _stopListening();
          }
        },
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('listen failed: $e');
      if (mounted) setState(() => listening = false);
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (mounted) setState(() => listening = false);
    if (_partialSpoken.trim().isNotEmpty) _onFinalSpoken(_partialSpoken);
  }

  void _onFinalSpoken(String txt) {
    final cleaned = txt.trim();
    if (cleaned.isEmpty) return;
    setState(() {
      audioHistory.insert(0, cleaned);
      _partialSpoken = '';
    });
    widget.onTranscribed?.call(cleaned);
    _scrollToTop();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
      setState(() => _ttsReady = true);
    } catch (e) {
      debugPrint('initTts failed: $e');
      setState(() => _ttsReady = false);
    }
  }

  Future<void> _configureTtsForVoice(SingingVoice voice) async {
    if (!_ttsReady) return;
    try {
      if (voice == SingingVoice.male) {
        await _tts.setPitch(0.85);
        await _tts.setSpeechRate(0.42);
      } else {
        await _tts.setPitch(1.15);
        await _tts.setSpeechRate(0.52);
      }
    } catch (e) {
      debugPrint('configure tts failed: $e');
    }
  }

  Future<void> _speak(String text) async {
    if (!_ttsReady) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TTS not ready')));
      return;
    }
    try {
      await _configureTtsForVoice(_selectedVoice);
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  /// Very small transformation to make text "song-like".
  String _makeSongLike(String plain) {
    final words = plain.trim();
    if (words.isEmpty) return words;
    final chorus = " ♪ La-la ♪ ";
    final base = words.replaceAll(RegExp(r'\s+'), ' ♪ ');
    return "$base$chorus${base.toUpperCase()}";
  }

  Future<void> _handleAiPressed() async {
    if (aiInProgress) return;

    final payload = _partialSpoken.trim().isNotEmpty ? _partialSpoken : (audioHistory.isNotEmpty ? audioHistory.first : '');
    if (payload.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No transcript to send')));
      return;
    }

    widget.onAiAction?.call(payload);
    final builder = widget.aiResponseStreamBuilder;
    if (builder == null) return;

    await _aiSub?.cancel();
    setState(() {
      _partialAi = '';
      aiInProgress = true;
    });

    final stream = builder(payload);
    if (stream == null) {
      setState(() => aiInProgress = false);
      return;
    }

    String built = '';
    _aiSub = stream.listen((chunk) {
      if (!mounted) return;
      built += chunk;
      // update partial displays
      final songPreview = _makeSongLike(built);
      setState(() {
        _partialAi = built;
      });
      // send live preview upstream to parent so marquee updates
      widget.onTranscribed?.call(songPreview);
    }, onDone: () async {
      if (!mounted) return;
      final finalText = built.trim();
      final song = _makeSongLike(finalText);
      if (song.trim().isNotEmpty) {
        setState(() {
          audioHistory.insert(0, song);
          _partialAi = '';
        });
        widget.onTranscribed?.call(song);
      }
      _scrollToTop();
      if (song.trim().isNotEmpty) await _speak(song);
      if (mounted) setState(() => aiInProgress = false);
    }, onError: (err) {
      debugPrint('AI stream error: $err');
      if (mounted) setState(() => aiInProgress = false);
    }, cancelOnError: true);
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _aiSub?.cancel();
    _tts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            ElevatedButton(
              onPressed: aiInProgress ? null : _handleAiPressed,
              child: aiInProgress
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('AI → Song'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!listening) {
                  _startListening();
                } else {
                  _stopListening();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: listening ? Colors.red : null, shape: const CircleBorder(), padding: const EdgeInsets.all(12)),
              child: Icon(listening ? Icons.mic_off : Icons.mic),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final toSpeak = _partialAi.isNotEmpty ? _makeSongLike(_partialAi) : (audioHistory.isNotEmpty ? audioHistory.first : (_partialSpoken.isNotEmpty ? _makeSongLike(_partialSpoken) : ''));
                if (toSpeak.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to sing')));
                  return;
                }
                _speak(toSpeak);
              },
              icon: const Icon(Icons.music_note),
              label: const Text('Sing'),
            ),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Voice:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Female'),
              selected: _selectedVoice == SingingVoice.female,
              onSelected: (v) => setState(() => _selectedVoice = SingingVoice.female),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Male'),
              selected: _selectedVoice == SingingVoice.male,
              onSelected: (v) => setState(() => _selectedVoice = SingingVoice.male),
            ),
          ]),
          const SizedBox(height: 8),
          if (_partialSpoken.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text('Spoken: $_partialSpoken', style: const TextStyle(fontStyle: FontStyle.italic))),
          if (_partialAi.isNotEmpty || aiInProgress) Align(alignment: Alignment.centerLeft, child: Text(_partialAi.isNotEmpty ? _partialAi : 'Waiting for AI...', style: const TextStyle(fontStyle: FontStyle.italic))),
          const Divider(),
          SizedBox(
            height: 140,
            child: audioHistory.isEmpty ? const Center(child: Text('No transcripts yet')) : ListView.builder(controller: _scrollController, itemCount: audioHistory.length, itemBuilder: (_, i) => ListTile(title: Text(audioHistory[i]))),
          ),
        ]),
      ),
    );
  }
}

/// Main page which controls background audio and marquee text.
class LedAiPage extends StatefulWidget {
  const LedAiPage({super.key});
  @override
  State<LedAiPage> createState() => _LedAiPageState();
}

class _LedAiPageState extends State<LedAiPage> {
  final TextEditingController _textController = TextEditingController(text: 'LED SCROLLER');
  final FakeWebSocketService fakeService = FakeWebSocketService();

  // Background audio player (owned by the page)
  AudioPlayer? _bgPlayer;
  bool _isBgPlaying = false;
  String? _bgFileName;
  String? _bgFilePath;

  bool _scrolling = true;
  double _velocity = 60;

  @override
  void dispose() {
    _textController.dispose();
    _disposeBgPlayer();
    super.dispose();
  }

  Stream<String>? _aiStreamBuilder(String payload) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    return fakeService.requestStream(id, payload);
  }

  Future<void> _pickBgAudioFile() async {
    try {
      const XTypeGroup audioGroup = XTypeGroup(label: 'audio', extensions: ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg']);
      final XFile? picked = await openFile(acceptedTypeGroups: [audioGroup]);
      if (picked == null) return;

      await _stopBgPlayback(keepSelection: true);

      _bgFileName = picked.name;
      _bgFilePath = picked.path;
      setState(() {});

      _bgPlayer = AudioPlayer();
      try {
        await _bgPlayer!.setReleaseMode(ReleaseMode.loop);
      } catch (_) {}

      try {
        await _bgPlayer!.setSourceDeviceFile(_bgFilePath!);
        await _bgPlayer!.resume();
      } catch (e) {
        debugPrint('setSourceDeviceFile failed: $e — trying play() fallback');
        await _bgPlayer!.play(DeviceFileSource(_bgFilePath!));
      }

      _bgPlayer!.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _isBgPlaying = state == PlayerState.playing);
      });

      if (!_scrolling) {
        await _bgPlayer!.pause();
        setState(() => _isBgPlaying = false);
      }
    } catch (e) {
      debugPrint('pick bg audio failed: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick/play audio: $e')));
    }
  }

  Future<void> _toggleScroll() async {
    setState(() => _scrolling = !_scrolling);

    if (_scrolling) {
      if (_bgFilePath != null) {
        if (_bgPlayer == null) {
          _bgPlayer = AudioPlayer();
          try {
            await _bgPlayer!.setReleaseMode(ReleaseMode.loop);
          } catch (_) {}
          try {
            await _bgPlayer!.setSourceDeviceFile(_bgFilePath!);
            await _bgPlayer!.resume();
          } catch (e) {
            debugPrint('toggle: setSourceDeviceFile failed: $e, fallback to play()');
            await _bgPlayer!.play(DeviceFileSource(_bgFilePath!));
          }
          _bgPlayer!.onPlayerStateChanged.listen((state) {
            if (!mounted) return;
            setState(() => _isBgPlaying = state == PlayerState.playing);
          });
        } else {
          try {
            try {
              await _bgPlayer!.setSourceDeviceFile(_bgFilePath!);
            } catch (_) {}
            await _bgPlayer!.resume();
            setState(() => _isBgPlaying = true);
          } catch (e) {
            debugPrint('toggle resume failed: $e');
          }
        }
      }
    } else {
      if (_bgPlayer != null) {
        try {
          await _bgPlayer!.pause();
        } catch (e) {
          debugPrint('pause bg failed: $e');
        }
        setState(() => _isBgPlaying = false);
      }
    }
  }

  Future<void> _stopBgPlayback({bool keepSelection = true}) async {
    try {
      if (_bgPlayer != null) {
        await _bgPlayer!.stop();
        try {
          await _bgPlayer!.dispose();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('stop bg playback failed: $e');
    } finally {
      _bgPlayer = null;
      _isBgPlaying = false;
      if (!keepSelection) {
        _bgFileName = null;
        _bgFilePath = null;
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _disposeBgPlayer() async {
    await _stopBgPlayback(keepSelection: false);
  }

  void _onTranscribed(String txt) {
    setState(() => _textController.text = txt);
  }

  @override
  Widget build(BuildContext context) {
    final display = _textController.text.isEmpty ? ' ' : _textController.text;
    return Scaffold(
      appBar: AppBar(title: const Text('LED Scroller + Background Audio')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            Container(
              height: 140,
              color: Colors.black,
              child: Center(
                child: _scrolling
                    ? Marquee(
                        text: display,
                        style: const TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.bold),
                        velocity: _velocity,
                        blankSpace: 40,
                      )
                    : Center(child: Text(display, style: const TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.bold))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Expanded(child: TextField(controller: _textController, decoration: const InputDecoration(labelText: 'Text to scroll'))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _toggleScroll, child: Text(_scrolling ? 'Pause' : 'Play')),
              ]),
            ),
            // Simplified audio UI: filename row (tappable) + a single Select button + playback controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickBgAudioFile,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            _bgFileName == null ? 'No background audio selected' : 'Background audio: $_bgFileName',
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(children: [
                  // Single select button (replaces duplicate "browse" and browser icon)
                  ElevatedButton.icon(onPressed: _pickBgAudioFile, icon: const Icon(Icons.folder_open), label: const Text('Select audio')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _bgPlayer == null ? null : () async {
                      if (_isBgPlaying) {
                        try { await _bgPlayer!.pause(); } catch (e) { debugPrint('pause failed: $e'); }
                        setState(() => _isBgPlaying = false);
                      } else {
                        try {
                          if (_bgFilePath != null) {
                            try { await _bgPlayer!.setSourceDeviceFile(_bgFilePath!); } catch (_) {}
                            await _bgPlayer!.resume();
                          }
                        } catch (e) {
                          debugPrint('resume failed: $e');
                        }
                        setState(() => _isBgPlaying = true);
                      }
                    },
                    icon: Icon(_isBgPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(_isBgPlaying ? 'Pause' : 'Play'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(onPressed: _bgPlayer == null ? null : () => _stopBgPlayback(keepSelection: true), icon: const Icon(Icons.stop), label: const Text('Stop')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(onPressed: _bgFilePath == null ? null : _disposeBgPlayer, icon: const Icon(Icons.delete), label: const Text('Clear')),
                ]),
              ]),
            ),
            AiAudioCard(onTranscribed: _onTranscribed, onAiAction: (p) => debugPrint('sent payload: $p'), aiResponseStreamBuilder: _aiStreamBuilder),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}
