import 'package:shared_preferences/shared_preferences.dart';
import '../services/frame_source.dart';
import '../services/wake_word_matcher.dart';

enum AiEnginePreference {
  autoHybrid,
  onDeviceOnly,
  cloudFlashOnly,
}

extension AiEnginePreferenceExtension on AiEnginePreference {
  String get label {
    switch (this) {
      case AiEnginePreference.autoHybrid:
        return 'Auto (On-Device first, Cloud fallback)';
      case AiEnginePreference.onDeviceOnly:
        return 'On-Device Only (Offline / Gemma 3n)';
      case AiEnginePreference.cloudFlashOnly:
        return 'Cloud Gemini Flash Only (Multimodal)';
    }
  }

  String get shortLabel {
    switch (this) {
      case AiEnginePreference.autoHybrid:
        return 'Auto Hybrid';
      case AiEnginePreference.onDeviceOnly:
        return 'On-Device';
      case AiEnginePreference.cloudFlashOnly:
        return 'Gemini Flash';
    }
  }

  /// Whether the on-device model should be attempted for this preference.
  bool get usesLocal =>
      this == AiEnginePreference.autoHybrid || this == AiEnginePreference.onDeviceOnly;

  /// Whether cloud vision may be used (as primary or as fallback).
  bool get usesCloud =>
      this == AiEnginePreference.autoHybrid || this == AiEnginePreference.cloudFlashOnly;
}

class AppSettings {
  String apiKey;
  AiEnginePreference aiEngine;
  double speechRate;
  double speechPitch;
  int continuousScanIntervalSeconds;
  bool hapticsEnabled;
  bool soundCuesEnabled;
  bool autoTorchInDark;

  /// Listen continuously for the wake phrase. Off by default: it holds the microphone
  /// open and costs battery, so it should be the user's deliberate choice.
  bool wakeWordEnabled;

  /// The phrase that activates voice interaction. User-editable.
  String wakeWord;

  /// Which camera supplies frames.
  CameraSourceKind cameraSource;

  /// Snapshot or MJPEG URL for a wireless camera.
  String networkCameraUrl;
  String networkCameraUsername;
  String networkCameraPassword;

  /// Straighten fisheye distortion before analysis. Off unless the lens needs it.
  bool fisheyeCorrectionEnabled;

  /// 0 = none, ~0.6 = mild wide-angle, 1.0+ = true 180-degree fisheye.
  double fisheyeStrength;

  AppSettings({
    this.apiKey = '',
    this.aiEngine = AiEnginePreference.autoHybrid,
    this.speechRate = 0.52,
    this.speechPitch = 1.0,
    this.continuousScanIntervalSeconds = 4,
    this.hapticsEnabled = true,
    this.soundCuesEnabled = true,
    this.autoTorchInDark = false,
    this.wakeWordEnabled = false,
    this.wakeWord = WakeWordMatcher.defaultPhrase,
    this.cameraSource = CameraSourceKind.device,
    this.networkCameraUrl = '',
    this.networkCameraUsername = '',
    this.networkCameraPassword = '',
    this.fisheyeCorrectionEnabled = false,
    this.fisheyeStrength = 0.6,
  });

  static const String _keyApiKey = 'eyephone_api_key';
  static const String _keyAiEngine = 'eyephone_ai_engine';
  static const String _keySpeechRate = 'eyephone_speech_rate';
  static const String _keySpeechPitch = 'eyephone_speech_pitch';
  static const String _keyScanInterval = 'eyephone_scan_interval';
  static const String _keyHaptics = 'eyephone_haptics';
  static const String _keySoundCues = 'eyephone_sound_cues';
  static const String _keyAutoTorch = 'eyephone_auto_torch';
  static const String _keyWakeWordEnabled = 'eyephone_wake_word_enabled';
  static const String _keyWakeWord = 'eyephone_wake_word';
  static const String _keyCameraSource = 'eyephone_camera_source';
  static const String _keyNetworkUrl = 'eyephone_network_camera_url';
  static const String _keyNetworkUser = 'eyephone_network_camera_user';
  static const String _keyNetworkPass = 'eyephone_network_camera_pass';
  static const String _keyFisheyeEnabled = 'eyephone_fisheye_enabled';
  static const String _keyFisheyeStrength = 'eyephone_fisheye_strength';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_keyApiKey) ?? '';
    final engineIndex = prefs.getInt(_keyAiEngine) ?? 0;
    final speechRate = prefs.getDouble(_keySpeechRate) ?? 0.52;
    final speechPitch = prefs.getDouble(_keySpeechPitch) ?? 1.0;
    final scanInterval = prefs.getInt(_keyScanInterval) ?? 4;
    final haptics = prefs.getBool(_keyHaptics) ?? true;
    final soundCues = prefs.getBool(_keySoundCues) ?? true;
    final autoTorch = prefs.getBool(_keyAutoTorch) ?? false;
    final wakeWordEnabled = prefs.getBool(_keyWakeWordEnabled) ?? false;
    final storedWakeWord = prefs.getString(_keyWakeWord)?.trim();

    final engine = (engineIndex >= 0 && engineIndex < AiEnginePreference.values.length)
        ? AiEnginePreference.values[engineIndex]
        : AiEnginePreference.autoHybrid;

    return AppSettings(
      apiKey: apiKey,
      aiEngine: engine,
      speechRate: speechRate,
      speechPitch: speechPitch,
      continuousScanIntervalSeconds: scanInterval,
      hapticsEnabled: haptics,
      soundCuesEnabled: soundCues,
      autoTorchInDark: autoTorch,
      wakeWordEnabled: wakeWordEnabled,
      wakeWord: (storedWakeWord == null || storedWakeWord.isEmpty)
          ? WakeWordMatcher.defaultPhrase
          : storedWakeWord,
      cameraSource: _cameraSourceFromIndex(prefs.getInt(_keyCameraSource)),
      networkCameraUrl: prefs.getString(_keyNetworkUrl) ?? '',
      networkCameraUsername: prefs.getString(_keyNetworkUser) ?? '',
      networkCameraPassword: prefs.getString(_keyNetworkPass) ?? '',
      fisheyeCorrectionEnabled: prefs.getBool(_keyFisheyeEnabled) ?? false,
      fisheyeStrength: prefs.getDouble(_keyFisheyeStrength) ?? 0.6,
    );
  }

  static CameraSourceKind _cameraSourceFromIndex(int? index) {
    if (index == null || index < 0 || index >= CameraSourceKind.values.length) {
      return CameraSourceKind.device;
    }
    return CameraSourceKind.values[index];
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey);
    await prefs.setInt(_keyAiEngine, aiEngine.index);
    await prefs.setDouble(_keySpeechRate, speechRate);
    await prefs.setDouble(_keySpeechPitch, speechPitch);
    await prefs.setInt(_keyScanInterval, continuousScanIntervalSeconds);
    await prefs.setBool(_keyHaptics, hapticsEnabled);
    await prefs.setBool(_keySoundCues, soundCuesEnabled);
    await prefs.setBool(_keyAutoTorch, autoTorchInDark);
    await prefs.setBool(_keyWakeWordEnabled, wakeWordEnabled);
    await prefs.setString(_keyWakeWord, wakeWord);
    await prefs.setInt(_keyCameraSource, cameraSource.index);
    await prefs.setString(_keyNetworkUrl, networkCameraUrl);
    await prefs.setString(_keyNetworkUser, networkCameraUsername);
    await prefs.setString(_keyNetworkPass, networkCameraPassword);
    await prefs.setBool(_keyFisheyeEnabled, fisheyeCorrectionEnabled);
    await prefs.setDouble(_keyFisheyeStrength, fisheyeStrength);
  }
}
