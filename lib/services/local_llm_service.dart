import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/guidance_result.dart';
import '../models/vision_mode.dart';

/// Lifecycle of the on-device model.
enum LocalLlmState {
  /// Platform has no local engine (iOS, desktop, web).
  unsupported,

  /// Engine present but no .task bundle on disk yet.
  modelMissing,

  /// Model file found, not yet loaded into memory.
  idle,

  /// Loading into memory — takes 10-30s for a 3-4 GB bundle.
  loading,

  /// Loaded and able to answer.
  ready,

  /// Load or inference failed.
  error,
}

class LocalLlmStatus {
  final LocalLlmState state;
  final String modelName;
  final String modelsDir;
  final int modelSizeBytes;
  final String error;

  /// Whether the loaded bundle can accept camera frames. Only Gemma 3n can; DeepSeek
  /// and other text-only distills cannot describe a scene at all.
  final bool supportsVision;

  const LocalLlmStatus({
    required this.state,
    this.modelName = '',
    this.modelsDir = '',
    this.modelSizeBytes = 0,
    this.supportsVision = false,
    this.error = '',
  });

  const LocalLlmStatus.unknown()
      : state = LocalLlmState.idle,
        modelName = '',
        modelsDir = '',
        modelSizeBytes = 0,
        supportsVision = false,
        error = '';

  bool get isReady => state == LocalLlmState.ready;

  /// Ready *and* able to analyse a camera frame.
  bool get canSeeImages => isReady && supportsVision;
  bool get hasModelFile =>
      state != LocalLlmState.modelMissing && state != LocalLlmState.unsupported;

  double get modelSizeGb => modelSizeBytes / (1024 * 1024 * 1024);

  /// Spoken-friendly description — this is read aloud to the user, so no jargon.
  ///
  /// Deliberately says nothing about cloud fallback: whether cloud is actually used
  /// depends on the engine preference, and promising a fallback that will not happen
  /// is worse than saying nothing to someone relying on this to walk.
  String get spokenDescription {
    switch (state) {
      case LocalLlmState.unsupported:
        return 'On-device AI is not supported on this platform.';
      case LocalLlmState.modelMissing:
        return 'Offline AI model is not installed.';
      case LocalLlmState.idle:
        return 'Offline AI model found, but not yet loaded.';
      case LocalLlmState.loading:
        return 'Loading offline AI model. This takes up to thirty seconds.';
      case LocalLlmState.ready:
        return supportsVision
            ? 'Offline AI is ready. Vision runs entirely on this phone.'
            : 'Offline AI is ready for questions, but this model cannot see images.';
      case LocalLlmState.error:
        return 'Offline AI failed to load.';
    }
  }

  String get shortLabel {
    switch (state) {
      case LocalLlmState.unsupported:
        return 'Unsupported';
      case LocalLlmState.modelMissing:
        return 'Model not installed';
      case LocalLlmState.idle:
        return 'Not loaded';
      case LocalLlmState.loading:
        return 'Loading...';
      case LocalLlmState.ready:
        return modelName.isNotEmpty ? 'Ready ($modelName)' : 'Ready';
      case LocalLlmState.error:
        return 'Error';
    }
  }
}

/// Fully on-device multimodal vision via MediaPipe LLM Inference (Gemma 3n).
///
/// This is what "internal AI" actually means on hardware without AICore: the model
/// runs in-process, works with no network, and camera frames never leave the device.
class LocalLlmService {
  static const MethodChannel _channel = MethodChannel('com.eyephone.app/gemini_nano');

  LocalLlmStatus _status = const LocalLlmStatus.unknown();
  LocalLlmStatus get status => _status;

  /// Notifies the UI on every state transition (load progress, failures).
  final ValueNotifier<LocalLlmStatus> statusNotifier =
      ValueNotifier<LocalLlmStatus>(const LocalLlmStatus.unknown());

  void _setStatus(LocalLlmStatus s) {
    _status = s;
    statusNotifier.value = s;
  }

  LocalLlmState _parseState(String raw, bool modelPresent) {
    if (!modelPresent) return LocalLlmState.modelMissing;
    switch (raw) {
      case 'READY':
        return LocalLlmState.ready;
      case 'LOADING':
        return LocalLlmState.loading;
      case 'ERROR':
        return LocalLlmState.error;
      default:
        return LocalLlmState.idle;
    }
  }

  LocalLlmStatus _fromMap(Map<dynamic, dynamic> map) {
    final modelPresent = map['modelPresent'] as bool? ?? false;
    return LocalLlmStatus(
      state: _parseState(map['state'] as String? ?? 'IDLE', modelPresent),
      modelName: map['modelName'] as String? ?? '',
      modelsDir: map['modelsDir'] as String? ?? '',
      modelSizeBytes: (map['modelSizeBytes'] as num?)?.toInt() ?? 0,
      supportsVision: map['supportsVision'] as bool? ?? false,
      error: map['error'] as String? ?? '',
    );
  }

  /// Reports whether a model bundle is on disk, without loading it.
  Future<LocalLlmStatus> refreshStatus() async {
    try {
      final res = await _channel.invokeMethod('getLocalModelStatus');
      if (res is Map) {
        _setStatus(_fromMap(res));
        return _status;
      }
      _setStatus(const LocalLlmStatus(state: LocalLlmState.unsupported));
    } on MissingPluginException {
      _setStatus(const LocalLlmStatus(state: LocalLlmState.unsupported));
    } catch (e) {
      debugPrint('Local model status error: $e');
      _setStatus(LocalLlmStatus(state: LocalLlmState.error, error: '$e'));
    }
    return _status;
  }

  /// Loads the model into memory. Slow (10-30s); call once at startup.
  Future<LocalLlmStatus> initialize() async {
    await refreshStatus();
    if (_status.state == LocalLlmState.unsupported ||
        _status.state == LocalLlmState.modelMissing) {
      return _status;
    }

    _setStatus(LocalLlmStatus(
      state: LocalLlmState.loading,
      modelName: _status.modelName,
      modelsDir: _status.modelsDir,
      modelSizeBytes: _status.modelSizeBytes,
    ));

    try {
      final res = await _channel.invokeMethod('initializeLocalModel');
      if (res is Map) {
        _setStatus(_fromMap(res));
      }
    } on MissingPluginException {
      _setStatus(const LocalLlmStatus(state: LocalLlmState.unsupported));
    } catch (e) {
      debugPrint('Local model init error: $e');
      _setStatus(LocalLlmStatus(state: LocalLlmState.error, error: '$e'));
    }
    return _status;
  }

  /// Removes chain-of-thought from reasoning models before anything is spoken.
  ///
  /// DeepSeek R1 distills emit a long `<think>...</think>` monologue ahead of the answer.
  /// Read aloud that is minutes of rambling to someone standing at a kerb waiting to be
  /// told whether to step, so it is stripped here rather than trusted to the prompt.
  @visibleForTesting
  static String stripReasoning(String raw) {
    var text = raw;

    // Closed block: drop it wherever it appears.
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );

    // Unterminated block (hit the token cap mid-thought): keep only what follows the
    // opening tag if the model never closed it, otherwise nothing useful remains.
    final openOnly = RegExp(r'<think>', caseSensitive: false);
    if (openOnly.hasMatch(text)) {
      text = text.split(openOnly).last;
    }

    // Some builds emit a bare closing tag with no opener.
    text = text.replaceAll(RegExp(r'</?think>', caseSensitive: false), '');

    return text.trim();
  }

  /// Runs a prompt with an optional camera frame. Returns null if the engine is
  /// unavailable, so callers can fall back to cloud without special-casing errors.
  Future<String?> runPrompt(String prompt, {Uint8List? imageBytes}) async {
    if (!_status.isReady) return null;
    try {
      final res = await _channel.invokeMethod('runLocalPrompt', {
        'prompt': prompt,
        'image': imageBytes,
      });
      if (res is Map && res['success'] == true) {
        final text = stripReasoning(res['response'] as String? ?? '');
        final elapsed = (res['elapsedMs'] as num?)?.toInt();
        if (elapsed != null) {
          debugPrint('Local inference took ${elapsed}ms');
        }
        return text.isEmpty ? null : text;
      }
      if (res is Map) {
        debugPrint('Local inference failed: ${res['error']}');
      }
    } catch (e) {
      debugPrint('Local inference error: $e');
    }
    return null;
  }

  /// Runs a short fixed prompt to prove the model actually generates, and reports how
  /// long it took. Used by the settings screen so a load failure or a model that is too
  /// slow to be useful is visible before someone relies on it to cross a road.
  Future<({String text, int millis})?> selfTest() async {
    if (!_status.isReady) return null;
    final sw = Stopwatch()..start();
    final text = await runPrompt(
      'Reply with exactly one short sentence confirming you are running offline.',
    );
    sw.stop();
    if (text == null) return null;
    return (text: text, millis: sw.elapsedMilliseconds);
  }

  /// Analyzes a camera frame entirely on-device.
  ///
  /// Returns null when the local engine cannot answer, letting the caller fall back
  /// to cloud vision rather than speaking an error to the user.
  Future<GuidanceResult?> analyzeImage({
    required Uint8List imageBytes,
    required VisionMode mode,
    String? customQuestion,
    String? targetObject,
  }) async {
    // A text-only model must not guess at a scene it cannot see — that would invent
    // hazards for someone who cannot check. Fall back instead.
    if (!_status.canSeeImages) return null;

    String prompt = mode.promptInstruction;
    if (customQuestion != null && customQuestion.trim().isNotEmpty) {
      prompt = '''
You are the visual eyes for a blind person.
They asked: "$customQuestion"
Answer directly from the image. Include clock directions and distances if relevant.
Keep your response under 30 words.
''';
    } else if (mode == VisionMode.findObject &&
        targetObject != null &&
        targetObject.isNotEmpty) {
      prompt = '''
You are helping a blind person find: "$targetObject".
If you see it, state its clock position (12 o'clock straight ahead, 1-3 right, 9-11 left),
approximate distance, and how to reach it.
If not visible, say: "$targetObject not in view, pan camera slowly to the left or right".
Keep under 25 words.
''';
    }

    final response = await runPrompt(prompt, imageBytes: imageBytes);
    if (response == null || response.isEmpty) return null;

    return GuidanceResult.fromAiResponse(
      response,
      engine: _status.modelName.isNotEmpty
          ? 'On-Device ${_status.modelName.replaceAll('.task', '')}'
          : 'On-Device AI',
    );
  }

  void dispose() {
    statusNotifier.dispose();
  }
}
