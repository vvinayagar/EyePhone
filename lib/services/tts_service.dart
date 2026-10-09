import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  double _speechRate = 0.52;
  double _pitch = 1.0;

  bool get isSpeaking => _isSpeaking;

  VoidCallback? onStart;
  VoidCallback? onCompletion;
  Function(String)? onError;

  TtsService({double speechRate = 0.52, double pitch = 1.0}) {
    _speechRate = speechRate;
    _pitch = pitch;
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_pitch);
      await _flutterTts.setVolume(1.0);

      // Setup audio routing
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
      );

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        onStart?.call();
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        onCompletion?.call();
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        onCompletion?.call();
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        onError?.call(msg.toString());
      });
    } catch (e) {
      debugPrint('TTS initialization error: $e');
    }
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    try {
      await _flutterTts.setSpeechRate(rate);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
    try {
      await _flutterTts.setPitch(pitch);
    } catch (_) {}
  }

  Future<void> speak(String text, {bool interrupt = true}) async {
    if (text.trim().isEmpty) return;
    try {
      if (interrupt && _isSpeaking) {
        await _flutterTts.stop();
      }
      _isSpeaking = true;
      await _flutterTts.speak(text);
    } catch (e) {
      _isSpeaking = false;
      debugPrint('TTS speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }

  void dispose() {
    stop();
  }
}
