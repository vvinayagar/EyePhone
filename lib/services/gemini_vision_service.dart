import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/guidance_result.dart';
import '../models/vision_mode.dart';

/// Cloud multimodal vision via the Gemini REST API.
///
/// This talks to REST directly rather than through the `google_generative_ai` package
/// because current Gemini models are *thinking* models, and the only way to turn that off
/// is `generationConfig.thinkingConfig.thinkingBudget`, which that (now deprecated) SDK
/// cannot express. Leaving thinking on is not viable here: with a small output budget the
/// model spends the entire allowance reasoning and returns an empty answer, and with a
/// large one it costs ~760 extra tokens and seconds of latency on every scan.
class GeminiVisionService {
  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Fast, accurate, and honours `thinkingBudget: 0` (~1.4s per scan).
  static const String defaultModelName = 'gemini-3.5-flash';

  /// Tried in order when a model is rejected as unknown or retired.
  static const List<String> fallbackModels = [
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
    'gemini-flash-latest',
  ];

  /// Enough for a complete spoken sentence; responses are capped at ~30 words by prompt.
  static const int _maxOutputTokens = 300;

  String _apiKey = '';
  String _modelName = defaultModelName;
  final Set<String> _rejectedModels = {};
  final http.Client _client;

  String get activeModelName => _modelName;
  bool get hasApiKey => _apiKey.isNotEmpty;

  GeminiVisionService({
    String apiKey = '',
    String modelName = defaultModelName,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    // Named parameters cannot bind directly to private fields, so these are set here.
    _modelName = modelName;
    _apiKey = apiKey.trim();
  }

  void updateApiKey(String apiKey) {
    _apiKey = apiKey.trim();
    // A new key may have different model access; let the fallback chain re-evaluate.
    _rejectedModels.clear();
    _modelName = defaultModelName;
  }

  /// Analyzes a camera frame for navigation, reading, or scene understanding.
  Future<GuidanceResult> analyzeImage({
    required Uint8List imageBytes,
    required VisionMode mode,
    String? customQuestion,
    String? targetObject,
  }) {
    return _analyzeWithFallback(
      imageBytes: imageBytes,
      mode: mode,
      customQuestion: customQuestion,
      targetObject: targetObject,
      tried: {},
    );
  }

  /// One attempt per model; [tried] stops a scan from cycling between models.
  Future<GuidanceResult> _analyzeWithFallback({
    required Uint8List imageBytes,
    required VisionMode mode,
    String? customQuestion,
    String? targetObject,
    required Set<String> tried,
  }) async {
    if (_apiKey.isEmpty) {
      return GuidanceResult.failed(
        failure: ScanFailure.configuration,
        spokenText: 'Gemini API key is not configured. Please tap the Settings button or '
            'say your API key to activate visual guidance.',
        detailedDescription:
            'No API Key configured. Please enter your Google Gemini API key in settings.',
        engineUsed: 'Configuration Needed',
      );
    }

    final prompt = _buildPrompt(
      mode: mode,
      customQuestion: customQuestion,
      targetObject: targetObject,
    );

    try {
      final text = await _generate(prompt, imageBytes);
      if (text == null || text.isEmpty) {
        return GuidanceResult.failed(
          failure: ScanFailure.engine,
          spokenText: 'No description returned. Please try again.',
          detailedDescription: 'Empty response from vision model.',
          engineUsed: 'Error',
        );
      }
      return GuidanceResult.fromAiResponse(text, engine: 'Gemini Flash (Multimodal)');
    } catch (e) {
      debugPrint('Gemini vision API error: $e');
      final errorMsg = e.toString();

      // A retired model, an exhausted quota or an overloaded model is not a network
      // problem, and another model on the same key often still answers. Try the next
      // one rather than leaving the user without guidance.
      final overloaded = _isOverloaded(errorMsg);
      if (_isModelUnavailable(errorMsg) || _isQuotaExceeded(errorMsg) || overloaded) {
        tried.add(_modelName);
        // Overload passes in seconds; a retired model or a spent quota will not recover
        // this session, so stop sending scans there.
        if (!overloaded) _rejectedModels.add(_modelName);
        final next = _nextUsableModel(exclude: tried);
        if (next != null) {
          debugPrint('Model $_modelName failed ($errorMsg); switching to $next');
          _modelName = next;
          return _analyzeWithFallback(
            imageBytes: imageBytes,
            mode: mode,
            customQuestion: customQuestion,
            targetObject: targetObject,
            tried: tried,
          );
        }
      }

      return GuidanceResult.failed(
        failure: ScanFailure.engine,
        spokenText: _spokenErrorFor(errorMsg),
        detailedDescription: 'Error: $e',
        engineUsed: 'Error',
      );
    }
  }

  /// Issues one REST call and returns the response text.
  Future<String?> _generate(String prompt, Uint8List imageBytes) async {
    final uri = Uri.parse('$_endpoint/$_modelName:generateContent?key=$_apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(imageBytes),
              }
            },
          ]
        }
      ],
      'generationConfig': {
        // Navigation guidance must be literal, not creative.
        'temperature': 0.2,
        'maxOutputTokens': _maxOutputTokens,
        // The critical setting — see the class comment.
        'thinkingConfig': {'thinkingBudget': 0},
      },
    });

    final response = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    // A blocked prompt returns 200 with no candidates.
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      final feedback = decoded['promptFeedback'];
      throw Exception('No candidates returned. promptFeedback: $feedback');
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final parts = (candidate['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
    if (parts == null) return null;

    final buffer = StringBuffer();
    for (final part in parts) {
      final text = (part as Map<String, dynamic>)['text'];
      if (text is String) buffer.write(text);
    }
    return buffer.toString().trim();
  }

  String _buildPrompt({
    required VisionMode mode,
    String? customQuestion,
    String? targetObject,
  }) {
    if (customQuestion != null && customQuestion.trim().isNotEmpty) {
      return '''
You are the visual eyes for a blind person.
They asked this question about what the camera is pointing at:
"$customQuestion"
Look at the image carefully and answer their question directly, accurately, and concisely.
Name the specific objects you can see.
If there are obstacles, distances, or clock directions (e.g. at 2 o'clock, 10 o'clock), include them.
Keep your response under 30 words.
''';
    }

    if (mode == VisionMode.findObject &&
        targetObject != null &&
        targetObject.isNotEmpty) {
      return '''
You are helping a blind person find: "$targetObject".
Look at the camera image.
If you see the "$targetObject":
1. State its exact clock position (12 o'clock is straight ahead, 1-3 o'clock is right, 9-11 o'clock is left).
2. State approximate distance (e.g. "on table, arm's length away", "1 meter ahead to the left").
3. Tell them how to reach it.
If not visible, say: "$targetObject not in view, pan camera slowly to the left or right".
Keep under 25 words.
''';
    }

    return mode.promptInstruction;
  }

  bool _isModelUnavailable(String errorMsg) {
    final m = errorMsg.toLowerCase();
    return m.contains('is not found for api version') ||
        m.contains('not_found') ||
        m.contains('http 404') ||
        m.contains('not supported for generatecontent');
  }

  bool _isQuotaExceeded(String errorMsg) {
    final m = errorMsg.toLowerCase();
    return m.contains('http 429') || m.contains('resource_exhausted') || m.contains('quota');
  }

  bool _isOverloaded(String errorMsg) {
    final m = errorMsg.toLowerCase();
    return m.contains('http 503') || m.contains('unavailable') || m.contains('high demand');
  }

  String? _nextUsableModel({Set<String> exclude = const {}}) {
    for (final candidate in fallbackModels) {
      if (candidate != _modelName &&
          !_rejectedModels.contains(candidate) &&
          !exclude.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  /// Maps an API failure to something true and actionable when spoken aloud.
  String _spokenErrorFor(String errorMsg) {
    final m = errorMsg.toLowerCase();

    if (m.contains('api_key_invalid') ||
        m.contains('api key not valid') ||
        m.contains('http 403')) {
      return 'Gemini API key is invalid. Please check your key in settings.';
    }
    if (m.contains('quota') || m.contains('http 429') || m.contains('rate limit')) {
      return 'API quota reached. Please wait a moment.';
    }
    if (_isModelUnavailable(errorMsg)) {
      return 'The vision model is unavailable. Please update the app or check settings.';
    }
    if (m.contains('socket') ||
        m.contains('failed host lookup') ||
        m.contains('clientexception') ||
        m.contains('timeout') ||
        m.contains('network')) {
      return 'Unable to reach the vision service. Please check your internet connection.';
    }
    return 'Vision service error. Please try again.';
  }

  void dispose() => _client.close();
}
