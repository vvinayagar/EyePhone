import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GeminiNanoStatus {
  final bool isAvailable;
  final String deviceModel;
  final String manufacturer;
  final String details;

  const GeminiNanoStatus({
    required this.isAvailable,
    required this.deviceModel,
    required this.manufacturer,
    required this.details,
  });

  const GeminiNanoStatus.unknown()
      : isAvailable = false,
        deviceModel = '',
        manufacturer = '',
        details = 'Checking on-device AI capabilities...';
}

/// Service managing on-device Gemini Nano (via Android AICore system service)
class GeminiNanoService {
  static const MethodChannel _channel = MethodChannel('com.eyephone.app/gemini_nano');

  GeminiNanoStatus _status = const GeminiNanoStatus.unknown();
  GeminiNanoStatus get status => _status;

  Future<GeminiNanoStatus> checkAvailability() async {
    try {
      final info = await _channel.invokeMethod('getDeviceInfo');
      if (info is Map) {
        final map = Map<String, dynamic>.from(info);
        final hasAICore = map['hasAICore'] as bool? ?? false;
        final manufacturer = map['manufacturer'] as String? ?? 'Android';
        final model = map['model'] as String? ?? 'Device';

        _status = GeminiNanoStatus(
          isAvailable: hasAICore,
          deviceModel: model,
          manufacturer: manufacturer,
          details: hasAICore
              ? 'Internal Gemini Nano active via Android AICore ($model)'
              : 'AICore not detected on $model. Cloud Gemini Flash enabled for vision.',
        );
        return _status;
      }
    } on MissingPluginException {
      _status = const GeminiNanoStatus(
        isAvailable: false,
        deviceModel: 'Desktop/Web',
        manufacturer: 'System',
        details: 'Native AICore channel not available on this platform.',
      );
    } catch (e) {
      debugPrint('Error checking Gemini Nano: $e');
      _status = GeminiNanoStatus(
        isAvailable: false,
        deviceModel: '',
        manufacturer: '',
        details: 'Error verifying AICore: $e',
      );
    }
    return _status;
  }

  /// Parses voice navigation commands offline using on-device pattern intelligence / Nano logic
  Map<String, dynamic> parseVoiceCommandOffline(String text) {
    final lower = text.toLowerCase().trim();

    // Navigation / Clear path intent
    if (lower.contains('path') ||
        lower.contains('clear') ||
        lower.contains('walk') ||
        lower.contains('step') ||
        lower.contains('direction') ||
        lower.contains('guide me') ||
        lower.contains('navigate')) {
      return {
        'intent': 'navigation',
        'action': 'scan_path',
        'query': lower,
      };
    }

    // Read text / sign intent
    if (lower.contains('read') ||
        lower.contains('text') ||
        lower.contains('sign') ||
        lower.contains('label') ||
        lower.contains('say') ||
        lower.contains('word') ||
        lower.contains('letter')) {
      return {
        'intent': 'read_text',
        'action': 'read_sign',
        'query': lower,
      };
    }

    // Find object intent
    if (lower.contains('find') ||
        lower.contains('where is') ||
        lower.contains('where\'s') ||
        lower.contains('locate') ||
        lower.contains('search')) {
      // Extract target object: e.g. "where is my cup" -> "cup"
      String target = lower
          .replaceAll('where is my', '')
          .replaceAll('where is the', '')
          .replaceAll('where is', '')
          .replaceAll('find my', '')
          .replaceAll('find the', '')
          .replaceAll('find', '')
          .replaceAll('locate', '')
          .trim();
      return {
        'intent': 'find_object',
        'action': 'locate_target',
        'target': target.isNotEmpty ? target : 'object',
        'query': lower,
      };
    }

    // Describe surroundings intent
    if (lower.contains('describe') ||
        lower.contains('surrounding') ||
        lower.contains('around me') ||
        lower.contains('where am i') ||
        lower.contains('what is this') ||
        lower.contains('what is here') ||
        lower.contains('room')) {
      return {
        'intent': 'scene_description',
        'action': 'describe_scene',
        'query': lower,
      };
    }

    // Torch / flashlight
    if (lower.contains('torch') ||
        lower.contains('flash') ||
        lower.contains('light on') ||
        lower.contains('light off') ||
        lower.contains('flashlight')) {
      final on = !lower.contains('off');
      return {
        'intent': 'torch_toggle',
        'action': 'set_torch',
        'value': on,
      };
    }

    // Continuous guide toggle
    if (lower.contains('continuous') || lower.contains('auto guide') || lower.contains('keep watching')) {
      return {
        'intent': 'continuous_toggle',
        'action': 'toggle_continuous',
      };
    }

    // Stop / silence
    if (lower.contains('stop') || lower.contains('quiet') || lower.contains('silence') || lower.contains('cancel')) {
      return {
        'intent': 'stop',
        'action': 'stop_all',
      };
    }

    // Headphone status
    if (lower.contains('headphone') || lower.contains('earphone') || lower.contains('headset') || lower.contains('bluetooth')) {
      return {
        'intent': 'headphone_status',
        'action': 'announce_headphone',
      };
    }

    // General question for visual multimodal answering
    return {
      'intent': 'visual_qa',
      'action': 'ask_vision',
      'question': text,
    };
  }

  /// Executes prompt via local AICore if supported on the device
  Future<String?> executeLocalPrompt(String prompt) async {
    if (!_status.isAvailable) return null;
    try {
      final res = await _channel.invokeMethod('executeNanoPrompt', {'prompt': prompt});
      if (res is Map && res['success'] == true) {
        return res['response'] as String?;
      }
    } catch (e) {
      debugPrint('Local AICore execution error: $e');
    }
    return null;
  }
}
