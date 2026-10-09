import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'wake_word_matcher.dart';

/// What the single speech recognizer is currently doing.
///
/// There is only one recognizer instance available to the app, so wake-word listening and
/// command capture cannot run at once — this makes the handover explicit rather than
/// leaving two callers fighting over the microphone.
enum SttMode { idle, wakeWord, command }

class SttService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;

  SttMode _mode = SttMode.idle;
  bool _wakeWordRequested = false;
  bool _suspended = false;
  Timer? _restartTimer;

  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;
  SttMode get mode => _mode;

  /// True when the wake word loop is meant to be running (even if briefly between
  /// recognizer restarts, or paused because the app is speaking).
  bool get isWakeWordActive => _wakeWordRequested;

  VoidCallback? onListeningStart;
  VoidCallback? onListeningEnd;
  Function(String)? onError;

  /// Fired with the full transcript whenever the wake phrase is heard.
  Function(String transcript)? onWakeWordDetected;

  /// Decides whether a transcript contains the wake phrase. Replaced when the user
  /// edits their phrase in settings.
  WakeWordMatcher matcher = WakeWordMatcher();

  Future<bool> initialize() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('Microphone permission not granted: $status');
        return false;
      }

      _isAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('STT status: $status (mode: $_mode)');
          if (status == 'listening') {
            _isListening = true;
            // Wake-word listening is background activity — surfacing it as "listening"
            // would leave the UI permanently showing a listening indicator and fire the
            // listen-start chime on every restart.
            if (_mode == SttMode.command) onListeningStart?.call();
          } else if (status == 'notListening' || status == 'done') {
            _isListening = false;
            if (_mode == SttMode.command) {
              onListeningEnd?.call();
            } else if (_mode == SttMode.wakeWord) {
              // The recognizer stops on its own after silence; keep the loop alive.
              _scheduleWakeWordRestart();
            }
          }
        },
        onError: (errorNotification) {
          debugPrint('STT error: ${errorNotification.errorMsg} (mode: $_mode)');
          _isListening = false;
          if (_mode == SttMode.command) {
            onError?.call(errorNotification.errorMsg);
            onListeningEnd?.call();
          } else if (_mode == SttMode.wakeWord) {
            // "no match" and "speech timeout" are the normal result of ambient silence.
            // They must not kill the loop or stop the user reaching the app hands-free.
            _scheduleWakeWordRestart();
          }
        },
      );
      return _isAvailable;
    } catch (e) {
      debugPrint('STT initialize exception: $e');
      _isAvailable = false;
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Wake word
  // ---------------------------------------------------------------------------

  /// Begins listening for the wake phrase and keeps listening until stopped.
  ///
  /// Implemented as a restart loop over the platform recognizer rather than a dedicated
  /// hotword engine: the recognizer always stops after a few seconds of silence, so the
  /// loop restarts it. See the note in the README-level docs about battery cost.
  Future<void> startWakeWordListening() async {
    if (!_isAvailable) {
      final ok = await initialize();
      if (!ok) {
        onError?.call('Microphone access unavailable');
        return;
      }
    }
    _wakeWordRequested = true;
    await _beginWakeWordCycle();
  }

  Future<void> stopWakeWordListening() async {
    _wakeWordRequested = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    if (_mode == SttMode.wakeWord) {
      _mode = SttMode.idle;
      if (_speech.isListening) await _speech.stop();
      _isListening = false;
    }
  }

  /// Temporarily halts the wake loop without forgetting that it should be running.
  ///
  /// Used while the app is speaking, so EyePhone does not hear its own voice and wake
  /// itself, and while a real command is being captured.
  Future<void> suspendWakeWord() async {
    if (!_wakeWordRequested || _suspended) return;
    _suspended = true;
    _restartTimer?.cancel();
    if (_mode == SttMode.wakeWord) {
      _mode = SttMode.idle;
      if (_speech.isListening) await _speech.stop();
      _isListening = false;
    }
  }

  /// Resumes the wake loop after a suspend.
  Future<void> resumeWakeWord() async {
    if (!_wakeWordRequested || !_suspended) return;
    _suspended = false;
    await _beginWakeWordCycle();
  }

  void _scheduleWakeWordRestart() {
    if (!_wakeWordRequested || _suspended) return;
    _restartTimer?.cancel();
    // A short gap avoids hammering the recognizer when it errors immediately, which
    // some devices do when the microphone is briefly held by another process.
    _restartTimer = Timer(const Duration(milliseconds: 400), _beginWakeWordCycle);
  }

  Future<void> _beginWakeWordCycle() async {
    if (!_wakeWordRequested || _suspended) return;
    if (_mode == SttMode.command) return; // a real command outranks the wake loop
    if (_speech.isListening) return;

    try {
      _mode = SttMode.wakeWord;
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          if (words.trim().isEmpty) return;
          if (!matcher.matches(words)) return;

          debugPrint('Wake word detected in: "$words"');
          _mode = SttMode.idle;
          _speech.stop();
          _isListening = false;
          onWakeWordDetected?.call(words);
        },
        listenOptions: stt.SpeechListenOptions(
          // Dictation keeps the recognizer open longest between restarts.
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
          // Partial results are essential: waiting for a final result would add seconds
          // of delay before the app reacts to its own name.
          partialResults: true,
          onDevice: false,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('Wake word listen error: $e');
      _mode = SttMode.idle;
      _scheduleWakeWordRestart();
    }
  }

  // ---------------------------------------------------------------------------
  // Command capture
  // ---------------------------------------------------------------------------

  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Duration listenFor = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_isAvailable) {
      final ok = await initialize();
      if (!ok) {
        onError?.call('Microphone access unavailable');
        return;
      }
    }

    // Take the microphone off the wake loop before capturing a command.
    _restartTimer?.cancel();
    if (_speech.isListening) {
      await _speech.stop();
    }

    try {
      _mode = SttMode.command;
      _isListening = true;
      onListeningStart?.call();

      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          cancelOnError: true,
          partialResults: true,
          listenFor: listenFor,
          pauseFor: pauseFor,
        ),
      );
    } catch (e) {
      debugPrint('STT start listening error: $e');
      _mode = SttMode.idle;
      _isListening = false;
      onListeningEnd?.call();
      onError?.call(e.toString());
      _scheduleWakeWordRestart();
    }
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    _mode = SttMode.idle;
    _isListening = false;
    onListeningEnd?.call();
    // Hand the microphone back to the wake loop if it is meant to be running.
    _scheduleWakeWordRestart();
  }

  void dispose() {
    _wakeWordRequested = false;
    _restartTimer?.cancel();
    _speech.stop();
  }
}
