/// What the camera sees of a door, when one is in view.
enum DoorState {
  none,
  open,
  partlyOpen,

  /// Closed — the user has to physically open it to continue.
  closed,
}

class GuidanceResult {
  final String spokenText;
  final String detailedDescription;
  final bool isPathClear;
  final List<String> hazards;
  final int? clockDirection;
  final String? distanceEstimate;
  final String? suggestedAction;
  final DateTime timestamp;
  final String engineUsed;

  /// Someone is in the user's path. Drives a distinct audio cue so it is not confused
  /// with an inanimate obstacle — you walk around furniture, you speak to a person.
  final bool personAhead;

  /// Door visibility and whether it must be opened.
  final DoorState doorState;

  GuidanceResult({
    required this.spokenText,
    required this.detailedDescription,
    this.isPathClear = true,
    this.hazards = const [],
    this.clockDirection,
    this.distanceEstimate,
    this.suggestedAction,
    DateTime? timestamp,
    this.engineUsed = 'Gemini Flash',
    this.personAhead = false,
    this.doorState = DoorState.none,
  }) : timestamp = timestamp ?? DateTime.now();

  /// True when the user must act on the door rather than walk through it.
  bool get doorNeedsOpening => doorState == DoorState.closed;

  factory GuidanceResult.fromAiResponse(String rawText, {String engine = 'Gemini Flash'}) {
    final text = rawText.trim();
    final lower = text.toLowerCase();

    // Check if path is blocked or has obstacles
    final hasObstacle = lower.contains('obstacle') ||
        lower.contains('hazard') ||
        lower.contains('warning') ||
        lower.contains('stop') ||
        lower.contains('blocked') ||
        lower.contains('caution') ||
        lower.contains('stairs') ||
        lower.contains('curb') ||
        lower.contains('step down') ||
        lower.contains('step up') ||
        lower.contains('door closed');

    final isClear = !hasObstacle || lower.contains('path is clear') || lower.contains('clear path');

    // Extract clock directions if mentioned
    int? clock;
    final clockRegex = RegExp(r'(\d{1,2})\s*o\s*[\x27\u2019]?\s*clock', caseSensitive: false);
    final match = clockRegex.firstMatch(text);
    if (match != null) {
      final hour = int.tryParse(match.group(1) ?? '');
      if (hour != null && hour >= 1 && hour <= 12) {
        clock = hour;
      }
    }

    // Extract hazards list
    final List<String> detectedHazards = [];
    final lines = text.split(RegExp(r'[\n\.]'));
    for (final line in lines) {
      final trimmed = line.trim();
      final lineLower = trimmed.toLowerCase();
      if (lineLower.contains('obstacle') ||
          lineLower.contains('warning') ||
          lineLower.contains('caution') ||
          lineLower.contains('stairs') ||
          lineLower.contains('chair') ||
          lineLower.contains('curb') ||
          lineLower.contains('blocked')) {
        if (trimmed.isNotEmpty && trimmed.length < 80) {
          detectedHazards.add(trimmed);
        }
      }
    }

    return GuidanceResult(
      spokenText: text,
      detailedDescription: text,
      isPathClear: isClear,
      hazards: detectedHazards,
      clockDirection: clock,
      engineUsed: engine,
      personAhead: _detectPerson(lower),
      doorState: _detectDoorState(lower),
    );
  }

  /// Detects a person in the path, taking care not to fire on an explicit denial —
  /// "no one ahead" and "nobody in the way" both contain person words.
  static bool _detectPerson(String lower) {
    const negations = [
      'no one', 'no-one', 'noone', 'nobody', 'no people', 'no person',
      'no pedestrians', 'not any people', 'clear of people',
    ];
    for (final n in negations) {
      if (lower.contains(n)) return false;
    }

    const indicators = [
      'person', 'people', 'pedestrian', 'someone', 'somebody',
      'man ', 'woman ', 'child', 'crowd', 'queue', 'group of',
    ];
    return indicators.any(lower.contains);
  }

  /// Classifies a door mention. Order matters: "partly open" must be checked before the
  /// bare "open" test, and a closed door is the only state that demands user action.
  static DoorState _detectDoorState(String lower) {
    final mentionsDoor = lower.contains('door') || lower.contains('doorway');
    if (!mentionsDoor) return DoorState.none;

    const partly = ['partly open', 'partially open', 'ajar', 'half open', 'half-open'];
    if (partly.any(lower.contains)) return DoorState.partlyOpen;

    const closed = [
      'closed door', 'door is closed', 'door closed', 'shut door', 'door is shut',
      'must open', 'need to open', 'needs opening', 'push to open', 'pull to open',
      'open the door',
    ];
    if (closed.any(lower.contains)) return DoorState.closed;

    const open = ['open door', 'door is open', 'doorway', 'open doorway'];
    if (open.any(lower.contains)) return DoorState.open;

    // A door was mentioned but its state was not stated. Treat as closed: assuming a
    // door is open when it might not be is the error that walks someone into it.
    return DoorState.closed;
  }

  factory GuidanceResult.empty() {
    return GuidanceResult(
      spokenText: 'Ready. Point your camera forward and double tap to scan or speak.',
      detailedDescription: 'Ready.',
      isPathClear: true,
      engineUsed: 'Idle',
    );
  }
}
