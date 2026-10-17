import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/app_settings.dart';
import '../models/guidance_result.dart';
import '../models/headphone_status.dart';
import '../models/vision_mode.dart';
import 'audio_feedback_service.dart';
import 'audio_headphone_service.dart';
import 'camera_service.dart';
import 'camera_source_manager.dart';
import 'frame_source.dart';
import 'gemini_nano_service.dart';
import 'gemini_vision_service.dart';
import 'local_llm_service.dart';
import 'haptic_service.dart';
import 'stt_service.dart';
import 'tts_service.dart';
import 'wake_word_matcher.dart';

class GuidanceController extends ChangeNotifier with WidgetsBindingObserver {
  final AppSettings settings;
  final CameraService cameraService = CameraService();
  late final GeminiVisionService visionService;
  final GeminiNanoService nanoService = GeminiNanoService();
  final LocalLlmService localLlm = LocalLlmService();
  final AudioHeadphoneService headphoneService = AudioHeadphoneService();
  late final TtsService ttsService;
  final SttService sttService = SttService();
  late final AudioFeedbackService audioFeedbackService;
  late final HapticService hapticService;

  VisionMode _currentMode = VisionMode.navigation;
  bool _isContinuousActive = false;
  bool _isScanning = false;
  bool _isListening = false;
  String _targetObject = '';
  String _lastVoiceInput = '';
  GuidanceResult _lastResult = GuidanceResult.empty();
  Timer? _continuousTimer;

  VisionMode get currentMode => _currentMode;
  bool get isContinuousActive => _isContinuousActive;
  bool get isScanning => _isScanning;
  bool get isListening => _isListening;
  String get targetObject => _targetObject;
  String get lastVoiceInput => _lastVoiceInput;
  GuidanceResult get lastResult => _lastResult;
  HeadphoneStatus get headphoneStatus => headphoneService.statusNotifier.value;

  late final CameraSourceManager cameraSources;

  GuidanceController({required this.settings}) {
    cameraSources = CameraSourceManager(
      settings: settings,
      deviceCamera: cameraService,
    );
    visionService = GeminiVisionService(apiKey: settings.apiKey);
    ttsService = TtsService(speechRate: settings.speechRate, pitch: settings.speechPitch);
    audioFeedbackService = AudioFeedbackService(enabled: settings.soundCuesEnabled);
    hapticService = HapticService(enabled: settings.hapticsEnabled);
  }

  Future<void> initialize() async {
    // 0. Android reclaims the camera whenever the app leaves the foreground. Without this
    //    the preview comes back black after a screen-off, a call, or an app switch, and
    //    every scan fails silently.
    WidgetsBinding.instance.addObserver(this);

    // 1. Check AICore availability (reporting only — real local inference is the model below)
    await nanoService.checkAvailability();

    // 1b. Bring up the on-device model if the user wants local inference.
    //     Deliberately not awaited: loading a 3-4 GB bundle takes 10-30s and must not
    //     delay the camera or the welcome announcement. Scans fall back to cloud until ready.
    if (settings.aiEngine.usesLocal) {
      localLlm.statusNotifier.addListener(notifyListeners);
      unawaited(localLlm.initialize());
    } else {
      unawaited(localLlm.refreshStatus());
    }

    // 2. Setup Headphone callbacks
    headphoneService.onHeadsetButtonTriggered = () {
      debugPrint('Headset button event triggered');
      startVoiceInteraction();
    };

    headphoneService.onStatusChanged = (status) {
      notifyListeners();
      // Announce headphone connection changes into the ear
      if (status.isConnected) {
        ttsService.speak(status.spokenDescription, interrupt: false);
      }
    };

    // 3. Initialize STT callbacks
    sttService.onListeningStart = () {
      _isListening = true;
      audioFeedbackService.playListenStart();
      hapticService.listeningStartPattern();
      notifyListeners();
    };

    sttService.onListeningEnd = () {
      _isListening = false;
      audioFeedbackService.playListenEnd();
      notifyListeners();
    };

    sttService.onError = (err) {
      _isListening = false;
      notifyListeners();
    };

    // 3b. Wake word: "Hey EyePhone" (or the user's own phrase) opens voice interaction
    //     without touching the phone, which matters when it is in a pocket or on a strap.
    sttService.matcher = WakeWordMatcher(phrase: settings.wakeWord);
    sttService.onWakeWordDetected = _onWakeWordDetected;

    // Mute the wake loop while the app is talking. Without this EyePhone hears its own
    // voice through the speaker and wakes itself, which on a phone speaker turns every
    // spoken answer into a new activation.
    ttsService.onStart = () => unawaited(sttService.suspendWakeWord());
    ttsService.onCompletion = () => unawaited(sttService.resumeWakeWord());

    if (settings.wakeWordEnabled) {
      unawaited(sttService.startWakeWordListening());
    }

    // 4. Initialize Camera (device camera always comes up — it is the fallback path)
    await cameraService.initialize();
    await cameraSources.applySettings();
    cameraSources.addListener(notifyListeners);

    // 5. Welcome announcement
    final welcome = 'EyePhone is ready. Navigation mode active. '
        '${headphoneStatus.isConnected ? "Headphones connected." : "Using phone speaker."} '
        'Double tap the screen or press your headphone button to speak.';
    await ttsService.speak(welcome, interrupt: true);
  }

  /// Switch Vision Mode (Navigation, Read Text, Describe Scene, Find Object)
  Future<void> switchMode(VisionMode newMode) async {
    if (_currentMode == newMode) return;
    _currentMode = newMode;
    hapticService.mediumTap();
    notifyListeners();

    await ttsService.speak(_currentMode.spokenAnnouncement, interrupt: true);

    // Auto-trigger a scan for the new mode
    await scanCurrentScene();
  }

  /// Cycles to next mode
  Future<void> nextMode() async {
    final nextIndex = (_currentMode.index + 1) % VisionMode.values.length;
    await switchMode(VisionMode.values[nextIndex]);
  }

  /// Cycles to previous mode
  Future<void> previousMode() async {
    final prevIndex = (_currentMode.index - 1 + VisionMode.values.length) % VisionMode.values.length;
    await switchMode(VisionMode.values[prevIndex]);
  }

  /// Routes one camera frame to the engine the user selected.
  ///
  /// On-device runs first when enabled, so guidance keeps working with no network and
  /// no frame ever leaves the phone. Cloud is used only as configured — either as the
  /// primary engine, or as fallback when the local model is missing, still loading, or
  /// returned nothing.
  Future<GuidanceResult> _analyzeFrame({
    required Uint8List imageBytes,
    String? customQuestion,
    String? targetObject,
  }) async {
    final pref = settings.aiEngine;

    if (pref.usesLocal && localLlm.status.canSeeImages) {
      final local = await localLlm.analyzeImage(
        imageBytes: imageBytes,
        mode: _currentMode,
        customQuestion: customQuestion,
        targetObject: targetObject,
      );
      if (local != null) return local;
      debugPrint('On-device inference returned nothing; falling back.');
    }

    if (!pref.usesCloud) {
      // On-device only: say why it is unavailable, and that no scan happened — never
      // imply a cloud fallback the user explicitly turned off.
      final text = '${localLlm.status.spokenDescription} '
          'Switch AI Engine Mode to Auto Hybrid in settings to use cloud vision.';
      return GuidanceResult.failed(
        failure: ScanFailure.onDeviceUnavailable,
        spokenText: text,
        engineUsed: 'On-Device Unavailable',
      );
    }

    return visionService.analyzeImage(
      imageBytes: imageBytes,
      mode: _currentMode,
      customQuestion: customQuestion,
      targetObject: targetObject,
    );
  }

  /// Plays non-speech cues for a result, most urgent first.
  ///
  /// The cue arrives before the spoken sentence, so the user gets the gist in a few
  /// hundred milliseconds instead of waiting out a full sentence of TTS. Each category
  /// gets a distinct sound: hazard, person, and door must be tellable apart by ear alone.
  Future<void> _playFeedbackFor(GuidanceResult result) async {
    // A failed scan saw nothing: no obstacle alarm, and no "clear" chime either. The
    // spoken error that follows says what went wrong.
    if (result.isError) return;

    final hazardous = !result.isPathClear || result.hazards.isNotEmpty;

    if (hazardous) {
      await audioFeedbackService.playObstacleAlert(clockDirection: result.clockDirection);
      await hapticService.obstacleAlert();
    }

    if (result.personAhead) {
      await audioFeedbackService.playPersonAhead(clockDirection: result.clockDirection);
      hapticService.mediumTap();
    }

    if (result.doorState != DoorState.none) {
      await audioFeedbackService.playDoorAhead(
        clockDirection: result.clockDirection,
        needsOpening: result.doorNeedsOpening,
      );
      // A door that must be opened gets its own stronger tap, so the hand knows to reach.
      if (result.doorNeedsOpening) {
        hapticService.heavyTap();
      } else {
        hapticService.lightTap();
      }
    }

    // Only confirm "clear" when there is genuinely nothing to report.
    if (!hazardous && !result.personAhead && result.doorState == DoorState.none) {
      await audioFeedbackService.playClearPath();
      await hapticService.pathClearPattern();
    }
  }

  /// Takes a snapshot and executes visual guidance analysis
  Future<void> scanCurrentScene({
    String? customQuestion,
    String? targetObjectOverride,
  }) async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      await audioFeedbackService.playScanTick();
      final imageBytes = await cameraSources.captureFrame();

      if (imageBytes == null) {
        const errorText = 'Camera image could not be captured. Please ensure camera lens is not covered.';
        _lastResult = GuidanceResult.failed(
          failure: ScanFailure.camera,
          spokenText: errorText,
          engineUsed: 'Camera Error',
        );
        _isScanning = false;
        notifyListeners();
        await ttsService.speak(errorText);
        return;
      }

      final target = targetObjectOverride ?? _targetObject;
      final result = await _analyzeFrame(
        imageBytes: imageBytes,
        customQuestion: customQuestion,
        targetObject: target,
      );

      _lastResult = result;
      _isScanning = false;
      notifyListeners();

      await _playFeedbackFor(result);

      // Speak result through headphones/speaker
      await ttsService.speak(result.spokenText, interrupt: true);
    } catch (e) {
      debugPrint('Scan error: $e');
      _isScanning = false;
      notifyListeners();
      await ttsService.speak('Navigation scan failed. Please try again.');
    }
  }

  /// Toggles continuous walking guidance (acts as real-time Eyes)
  void toggleContinuousMode() {
    _isContinuousActive = !_isContinuousActive;
    hapticService.heavyTap();
    notifyListeners();

    if (_isContinuousActive) {
      ttsService.speak('Continuous eye guidance started. Scanning your path.', interrupt: true);
      _startContinuousGuidance();
    } else {
      _stopContinuousGuidance();
      ttsService.speak('Continuous eye guidance stopped.', interrupt: true);
    }
  }

  void _startContinuousGuidance() {
    _continuousTimer?.cancel();
    scanCurrentScene();

    final interval = Duration(seconds: settings.continuousScanIntervalSeconds);
    _continuousTimer = Timer.periodic(interval, (_) async {
      if (!_isContinuousActive) return;
      if (!_isScanning && !ttsService.isSpeaking && !_isListening) {
        await scanCurrentScene();
      }
    });
  }

  void _stopContinuousGuidance() {
    _continuousTimer?.cancel();
    _continuousTimer = null;
  }

  /// Starts voice interaction for hands-free queries & commands
  /// Handles the wake phrase being heard.
  ///
  /// If the user ran the phrase and the command together ("Hey EyePhone, is the path
  /// clear?"), the command is executed straight away rather than making them repeat it.
  Future<void> _onWakeWordDetected(String transcript) async {
    final trailing = sttService.matcher.commandAfterWake(transcript);

    hapticService.confirmTap();
    await audioFeedbackService.playListenStart();

    if (trailing != null && trailing.length > 2) {
      _lastVoiceInput = trailing;
      notifyListeners();
      await handleVoiceCommand(trailing);
      // handleVoiceCommand speaks, which suspends the loop; restore it afterwards.
      unawaited(sttService.resumeWakeWord());
      return;
    }

    await startVoiceInteraction();
  }

  /// Applies a changed wake phrase or on/off state without restarting the app.
  Future<void> updateWakeWord({String? phrase, bool? enabled}) async {
    if (phrase != null) {
      settings.wakeWord = phrase.trim().isEmpty
          ? WakeWordMatcher.defaultPhrase
          : phrase.trim();
      sttService.matcher = WakeWordMatcher(phrase: settings.wakeWord);
    }
    if (enabled != null) settings.wakeWordEnabled = enabled;
    await settings.save();

    if (settings.wakeWordEnabled) {
      await sttService.startWakeWordListening();
    } else {
      await sttService.stopWakeWordListening();
    }
    notifyListeners();
  }

  /// Applies a camera source change and tells the user which eye is in use.
  Future<void> updateCameraSource({
    CameraSourceKind? kind,
    String? networkUrl,
    String? username,
    String? password,
    bool? fisheyeEnabled,
    double? fisheyeStrength,
  }) async {
    if (kind != null) settings.cameraSource = kind;
    if (networkUrl != null) settings.networkCameraUrl = networkUrl.trim();
    if (username != null) settings.networkCameraUsername = username.trim();
    if (password != null) settings.networkCameraPassword = password;
    if (fisheyeEnabled != null) settings.fisheyeCorrectionEnabled = fisheyeEnabled;
    if (fisheyeStrength != null) settings.fisheyeStrength = fisheyeStrength;

    await settings.save();
    await cameraSources.applySettings();
    notifyListeners();
  }

  Future<void> startVoiceInteraction() async {
    // Stop ongoing speech
    await ttsService.stop();

    await sttService.startListening(
      onResult: (recognizedWords, isFinal) {
        _lastVoiceInput = recognizedWords;
        notifyListeners();

        if (isFinal && recognizedWords.trim().isNotEmpty) {
          handleVoiceCommand(recognizedWords.trim());
        }
      },
    );
  }

  /// Parses and executes user voice command using internal Gemini Nano / pattern logic
  Future<void> handleVoiceCommand(String command) async {
    debugPrint('Processing voice command: "$command"');
    hapticService.confirmTap();

    // Use Internal Gemini Nano for offline intent classification
    final parsed = nanoService.parseVoiceCommandOffline(command);
    final intent = parsed['intent'] as String? ?? 'visual_qa';

    switch (intent) {
      case 'navigation':
        _currentMode = VisionMode.navigation;
        notifyListeners();
        await ttsService.speak('Checking path.', interrupt: true);
        await scanCurrentScene();
        break;

      case 'read_text':
        _currentMode = VisionMode.readText;
        notifyListeners();
        await ttsService.speak('Reading text in front of you.', interrupt: true);
        await scanCurrentScene();
        break;

      case 'scene_description':
        _currentMode = VisionMode.sceneDescriber;
        notifyListeners();
        await ttsService.speak('Describing surroundings.', interrupt: true);
        await scanCurrentScene();
        break;

      case 'find_object':
        final target = parsed['target'] as String? ?? 'object';
        _targetObject = target;
        _currentMode = VisionMode.findObject;
        notifyListeners();
        await ttsService.speak('Searching for $target.', interrupt: true);
        await scanCurrentScene(targetObjectOverride: target);
        break;

      case 'torch_toggle':
        final on = parsed['value'] as bool? ?? !cameraService.isTorchOn;
        await cameraService.setTorch(on);
        notifyListeners();
        await ttsService.speak(on ? 'Flashlight turned on.' : 'Flashlight turned off.', interrupt: true);
        break;

      case 'continuous_toggle':
        toggleContinuousMode();
        break;

      case 'stop':
        if (_isContinuousActive) {
          _stopContinuousGuidance();
          _isContinuousActive = false;
        }
        await ttsService.stop();
        notifyListeners();
        break;

      case 'headphone_status':
        await ttsService.speak(headphoneStatus.spokenDescription, interrupt: true);
        break;

      case 'visual_qa':
      default:
        // Direct multimodal question: e.g. "Is this milk expired?" or "What color is this shirt?"
        await ttsService.speak('Looking at that for you.', interrupt: true);
        await scanCurrentScene(customQuestion: command);
        break;
    }
  }

  /// Announces full system status (battery, headphones, camera, mode)
  Future<void> announceStatus() async {
    hapticService.lightTap();
    final hp = headphoneStatus.spokenDescription;
    final mode = _currentMode.title;
    final continuous = _isContinuousActive ? 'Continuous guidance is active.' : 'Continuous guidance is paused.';
    // Report the engine actually in use, not merely what the device could support.
    final String engine;
    if (settings.aiEngine.usesLocal && localLlm.status.isReady) {
      engine = localLlm.status.spokenDescription;
    } else if (settings.aiEngine.usesLocal) {
      engine = '${localLlm.status.spokenDescription} '
          '${settings.aiEngine.usesCloud ? "Cloud Gemini Flash active." : ""}';
    } else {
      engine = 'Cloud Gemini Flash active.';
    }

    // Which camera is actually feeding the AI — if a remote camera dropped and we fell
    // back to the phone, the user needs to know their clipped-on camera is not working.
    final String camera;
    if (cameraSources.usingFallback) {
      camera = 'Remote camera not responding. Using phone camera.';
    } else if (settings.cameraSource != CameraSourceKind.device) {
      camera = 'Using ${settings.cameraSource.spokenLabel}.';
    } else {
      camera = '';
    }

    final msg = '$mode. $hp $continuous $engine $camera';
    await ttsService.speak(msg, interrupt: true);
  }

  /// Toggles camera torch
  Future<void> toggleTorch() async {
    hapticService.mediumTap();
    await cameraService.toggleTorch();
    notifyListeners();
    await ttsService.speak(
      cameraService.isTorchOn ? 'Flashlight on.' : 'Flashlight off.',
      interrupt: true,
    );
  }

  /// Update API Key
  void updateApiKey(String key) {
    settings.apiKey = key;
    settings.save();
    visionService.updateApiKey(key);
    notifyListeners();
  }

  /// Update speech settings
  void updateSpeechRate(double rate) {
    settings.speechRate = rate;
    settings.save();
    ttsService.setSpeechRate(rate);
    notifyListeners();
  }

  /// Releases the camera when backgrounded and rebuilds it on resume.
  ///
  /// The camera plugin's controller is dead after the OS reclaims the device, but still
  /// reports `isInitialized`, so it must be torn down and recreated rather than reused.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_isResumingCamera) return;
        // Continuous mode would keep firing scans against a dead camera.
        _continuousTimer?.cancel();
        _continuousTimer = null;
        cameraService.dispose();
        notifyListeners();
      case AppLifecycleState.resumed:
        unawaited(_restoreCamera());
    }
  }

  bool _isResumingCamera = false;

  Future<void> _restoreCamera() async {
    if (_isResumingCamera || cameraService.isInitialized) return;
    _isResumingCamera = true;
    try {
      final ok = await cameraService.initialize();
      notifyListeners();
      if (!ok) {
        await ttsService.speak(
          'Camera could not be restarted. Please check camera permission.',
          interrupt: true,
        );
        return;
      }
      // Resume continuous guidance only if the user had it running.
      if (_isContinuousActive) _startContinuousGuidance();
    } finally {
      _isResumingCamera = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _continuousTimer?.cancel();
    cameraService.dispose();
    ttsService.dispose();
    sttService.dispose();
    audioFeedbackService.dispose();
    headphoneService.dispose();
    super.dispose();
  }
}
