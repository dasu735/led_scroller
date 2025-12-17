import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../widgets/audio_source_sheet.dart'; // for AudioSourceType, VoiceType

class AudioEngine {
  /// 🔊 Voice audio
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();

  /// 🎵 Background music player
  final AudioPlayer _bgPlayer = AudioPlayer();

  AudioSourceType? _source;
  VoiceType _voice = VoiceType.girl;

  bool _voicePlaying = false;
  bool _bgPlaying = false;

  AudioEngine() {
    _bgPlayer.onPlayerStateChanged.listen((PlayerState state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        _bgPlaying = false;
      } else if (state == PlayerState.playing) {
        _bgPlaying = true;
      }
    });
  }

  /// =========================
  /// CONFIG
  /// =========================
  Future<void> setVoice(VoiceType voice) async {
    _voice = voice;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(_voice == VoiceType.boy ? 0.9 : 1.1);
  }

  void setSource(AudioSourceType type) {
    _source = type;
  }

  /// =========================
  /// VOICE AUDIO
  /// =========================
  Future<void> playVoice(String text) async {
    if (_source == null || text.trim().isEmpty) return;

    await stopVoice();

    if (_source == AudioSourceType.ai ||
        _source == AudioSourceType.browser) {
      _voicePlaying = true;
      await _tts.speak(text);
    }

    if (_source == AudioSourceType.mic) {
      await _startMic();
    }
  }

  Future<void> stopVoice() async {
    if (_voicePlaying) {
      await _tts.stop();
      _voicePlaying = false;
    }
    await _speech.stop();
  }

  Future<void> _startMic() async {
    final available = await _speech.initialize();
    if (!available) return;

    _voicePlaying = true;

    await _speech.listen(
      onResult: (result) async {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          await _tts.speak(result.recognizedWords);
        }
      },
    );
  }

  /// =========================
  /// 🎵 BACKGROUND MUSIC – ASSETS
  /// =========================
  ///
  /// assetPath comes from UI as 'assets/audio/ambient.mp3'.
  /// Because 'assets/' is declared as a root, audioplayers expects
  /// the path relative to it, e.g. 'audio/ambient.mp3'.
  ///
  Future<void> playBackgroundMusic(String assetPath) async {
    String relativePath = assetPath;
    if (relativePath.startsWith('assets/')) {
      relativePath = relativePath.substring('assets/'.length);
    }

    print('🎵 Playing background music (asset): $relativePath');

    try {
      await _bgPlayer.stop();
      await _bgPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgPlayer.setVolume(0.4);

      await _bgPlayer.play(AssetSource(relativePath));

      _bgPlaying = true;
      print('✅ Background music (asset) started: $relativePath');
    } catch (e) {
      _bgPlaying = false;
      print('❌ Failed to play background music (asset): $e');
    }
  }

  /// =========================
  /// 🎵 BACKGROUND MUSIC – FILE (BROWSER PICK)
  /// =========================
  Future<void> playBackgroundMusicFromFile(String filePath) async {
    print('🎵 Playing background music (file): $filePath');

    try {
      await _bgPlayer.stop();
      await _bgPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgPlayer.setVolume(0.4);

      await _bgPlayer.play(DeviceFileSource(filePath));

      _bgPlaying = true;
      print('✅ Background music (file) started: $filePath');
    } catch (e) {
      _bgPlaying = false;
      print('❌ Failed to play background music (file): $e');
    }
  }

  Future<void> pauseBackgroundMusic() async {
    if (_bgPlaying) {
      await _bgPlayer.pause();
      print('⏸️ Background music paused');
    }
  }

  Future<void> resumeBackgroundMusic() async {
    if (_bgPlaying) {
      await _bgPlayer.resume();
      print('▶️ Background music resumed');
    }
  }

  Future<void> stopBackgroundMusic() async {
    _bgPlaying = false;
    await _bgPlayer.stop();
    print('⛔ Background music stopped');
  }

  bool get isBackgroundPlaying => _bgPlaying;

  /// =========================
  /// CLEANUP
  /// =========================
  Future<void> dispose() async {
    await stopVoice();
    await stopBackgroundMusic();
    await _bgPlayer.dispose();
  }
}
