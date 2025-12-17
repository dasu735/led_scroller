import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../widgets/audio_source_sheet.dart';

class AudioEngine {
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();

  VoiceType _voice = VoiceType.girl;
  AudioSourceType? _source;

  bool _isPlaying = false;

  void setVoice(VoiceType v) {
    _voice = v;
    _tts.setVoice({
      'name': v == VoiceType.boy ? 'en-us-x-sfg#male_1' : 'en-us-x-sfg#female_1',
      'locale': 'en-US',
    });
  }

  void setSource(AudioSourceType source) {
    _source = source;
  }

  Future<void> play(String text) async {
    if (_source == null) return;

    stop();

    if (_source == AudioSourceType.ai ||
        _source == AudioSourceType.browser) {
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(_voice == VoiceType.boy ? 0.9 : 1.1);
      await _tts.speak(text);
      _isPlaying = true;
    }

    if (_source == AudioSourceType.mic) {
      await _startMic();
    }
  }

  Future<void> stop() async {
    if (_isPlaying) {
      await _tts.stop();
      await _player.stop();
      _isPlaying = false;
    }
  }

  Future<void> _startMic() async {
    bool available = await _speech.initialize();
    if (!available) return;

    await _speech.listen(
      onResult: (result) async {
        if (result.finalResult) {
          await _tts.speak(result.recognizedWords);
        }
      },
    );
  }

  Future<void> dispose() async {
    await stop();
    _speech.stop();
    _player.dispose();
  }
}
