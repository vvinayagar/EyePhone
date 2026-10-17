import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../utils/sound_generator.dart';

class AudioFeedbackService {
  final AudioPlayer _player = AudioPlayer();
  bool enabled = true;

  /// Longest a cue may hold up the caller. Scans await their cues, so a cue that never
  /// finishes preparing would freeze guidance on "Analyzing scene".
  static const Duration _cueTimeout = Duration(seconds: 2);

  /// Temp-file paths of tones already written, keyed by a hash of the WAV bytes.
  final Map<int, String> _cueFiles = {};

  AudioFeedbackService({this.enabled = true}) {
    _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
            AVAudioSessionOptions.duckOthers,
          },
        ),
      ),
    );
  }

  /// Plays a short chime when voice listening starts
  Future<void> playListenStart() async {
    if (!enabled) return;
    try {
      final wav = SoundGenerator.createToneWav(
        frequency: 660.0,
        durationSeconds: 0.15,
        volume: 0.4,
        pan: 0.0,
      );
      await _playWav(wav);
    } catch (_) {}
  }

  /// Plays a short chime when voice listening ends
  Future<void> playListenEnd() async {
    if (!enabled) return;
    try {
      final wav = SoundGenerator.createToneWav(
        frequency: 440.0,
        durationSeconds: 0.15,
        volume: 0.35,
        pan: 0.0,
      );
      await _playWav(wav);
    } catch (_) {}
  }

  /// Plays a directional obstacle warning tone panned to left/right headphone ear
  Future<void> playObstacleAlert({int? clockDirection}) async {
    if (!enabled) return;
    try {
      double pan = 0.0;
      if (clockDirection != null) {
        if (clockDirection >= 1 && clockDirection <= 4) {
          // Right side (e.g. 2 o'clock -> pan right)
          pan = 0.75;
        } else if (clockDirection >= 8 && clockDirection <= 11) {
          // Left side (e.g. 10 o'clock -> pan left)
          pan = -0.75;
        }
      }

      final wav = SoundGenerator.createToneWav(
        frequency: 880.0, // High alert frequency
        durationSeconds: 0.25,
        volume: 0.7,
        pan: pan,
      );
      await _playWav(wav);
    } catch (_) {}
  }

  /// Two soft mid tones, panned toward the person.
  ///
  /// Deliberately gentler and lower than the obstacle alert: a person is not a hazard to
  /// swerve around, they are someone to slow down for and possibly speak to. Using the
  /// same alarm for both trains users to ignore it.
  Future<void> playPersonAhead({int? clockDirection}) async {
    if (!enabled) return;
    try {
      final pan = _panForClock(clockDirection);
      for (var i = 0; i < 2; i++) {
        final wav = SoundGenerator.createToneWav(
          frequency: 587.33, // D5
          durationSeconds: 0.12,
          volume: 0.45,
          pan: pan,
        );
        await _playWav(wav);
        await Future.delayed(const Duration(milliseconds: 160));
      }
    } catch (_) {}
  }

  /// A low rising pair, signalling "something to open, not something to avoid".
  Future<void> playDoorAhead({int? clockDirection, bool needsOpening = false}) async {
    if (!enabled) return;
    try {
      final pan = _panForClock(clockDirection);
      final tones = needsOpening
          ? <double>[392.0, 523.25] // G4 -> C5, rising: action required
          : <double>[523.25, 392.0]; // falling: passable, no action
      for (final f in tones) {
        final wav = SoundGenerator.createToneWav(
          frequency: f,
          durationSeconds: 0.14,
          volume: 0.5,
          pan: pan,
        );
        await _playWav(wav);
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } catch (_) {}
  }

  /// Maps a clock direction to a stereo pan position.
  double _panForClock(int? clockDirection) {
    if (clockDirection == null) return 0.0;
    if (clockDirection >= 1 && clockDirection <= 4) return 0.75;
    if (clockDirection >= 8 && clockDirection <= 11) return -0.75;
    return 0.0;
  }

  /// Plays a calm harmonic tone when walking path ahead is verified clear
  Future<void> playClearPath() async {
    if (!enabled) return;
    try {
      final wav = SoundGenerator.createToneWav(
        frequency: 523.25, // C5
        durationSeconds: 0.18,
        volume: 0.3,
        pan: 0.0,
      );
      await _playWav(wav);
    } catch (_) {}
  }

  /// Subtle processing tick
  Future<void> playScanTick() async {
    if (!enabled) return;
    try {
      final wav = SoundGenerator.createToneWav(
        frequency: 400.0,
        durationSeconds: 0.06,
        volume: 0.2,
      );
      await _playWav(wav);
    } catch (_) {}
  }

  /// Plays a generated WAV.
  ///
  /// audioplayers cannot play in-memory audio on iOS or macOS (setSourceBytes is not
  /// implemented there): it waits out its 30 s preparation timeout and then fails. So
  /// outside the web, each tone is written once to a temp file and played from there.
  Future<void> _playWav(Uint8List wav) async {
    final Source source;
    if (kIsWeb) {
      source = BytesSource(wav, mimeType: 'audio/wav');
    } else {
      source = DeviceFileSource(await _cueFile(wav), mimeType: 'audio/wav');
    }
    await _player.play(source).timeout(_cueTimeout);
  }

  Future<String> _cueFile(Uint8List wav) async {
    final key = Object.hashAll(wav);
    final cached = _cueFiles[key];
    if (cached != null && File(cached).existsSync()) return cached;
    final path = '${Directory.systemTemp.path}/eyephone_cue_${key.toUnsigned(32)}.wav';
    await File(path).writeAsBytes(wav, flush: true);
    _cueFiles[key] = path;
    return path;
  }

  void dispose() {
    _player.dispose();
  }
}
