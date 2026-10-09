/// Decides whether a speech transcript contains the wake phrase.
///
/// Kept separate from the microphone plumbing so the matching rules can be tested
/// directly — this is the part that decides whether the app answers a blind user at all.
///
/// Matching is deliberately forgiving. Android's recognizer rarely returns "EyePhone"
/// verbatim: it produces "hey iphone", "hey eye phone", "a iphone", "hi iphone" and so on,
/// because "EyePhone" is not in its vocabulary. Requiring an exact string would mean the
/// wake word almost never fires. A false wake costs the user one unwanted listen; a missed
/// wake means they cannot reach the app hands-free at all, so we bias toward firing.
class WakeWordMatcher {
  /// Default phrase. Chosen to match the product name while staying two words, which
  /// recognizers handle far better than a single invented word.
  static const String defaultPhrase = 'Hey EyePhone';

  /// Known mis-transcriptions of the default phrase. Only applied when the user is on
  /// the default — a custom phrase gets generic fuzzy handling instead.
  static const List<String> _defaultAliases = [
    'hey eyephone',
    'hey iphone',
    'hey i phone',
    'hey eye phone',
    'hey ai phone',
    'hey my phone',
    'hi eyephone',
    'hi iphone',
    'hi eye phone',
    'a iphone',
    'ok eyephone',
    'ok iphone',
    'okay eyephone',
    'okay iphone',
    'eyephone',
  ];

  final String phrase;

  WakeWordMatcher({String? phrase})
      : phrase = (phrase == null || phrase.trim().isEmpty)
            ? defaultPhrase
            : phrase.trim();

  bool get _isDefaultPhrase =>
      normalize(phrase) == normalize(defaultPhrase);

  /// Lowercases and strips everything except letters, digits and single spaces.
  static String normalize(String input) {
    final lowered = input.toLowerCase();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalized with spaces removed, so "eye phone" and "eyephone" compare equal.
  static String _collapse(String input) => normalize(input).replaceAll(' ', '');

  /// True when [transcript] appears to contain the wake phrase.
  bool matches(String transcript) {
    if (transcript.trim().isEmpty) return false;

    final collapsedTranscript = _collapse(transcript);
    if (collapsedTranscript.isEmpty) return false;

    final collapsedPhrase = _collapse(phrase);

    // 1. Spacing-insensitive containment catches the common "eye phone" split.
    if (collapsedPhrase.isNotEmpty && collapsedTranscript.contains(collapsedPhrase)) {
      return true;
    }

    // 2. Known homophones, for the default phrase only.
    if (_isDefaultPhrase) {
      for (final alias in _defaultAliases) {
        if (collapsedTranscript.contains(_collapse(alias))) return true;
      }
    }

    // 3. Fuzzy window match, for custom phrases and badly mangled audio. Scans windows
    //    of the transcript the same length as the phrase and accepts a close match.
    return _fuzzyContains(collapsedTranscript, collapsedPhrase);
  }

  /// Slides a phrase-sized window across the transcript looking for a near match.
  ///
  /// The window is widened slightly either side because recognizers both drop and add
  /// characters. Tolerance scales with phrase length: ~20%, so "Hey EyePhone"
  /// (11 chars collapsed) permits 2 edits, which covers "hey iphone" style errors
  /// without matching unrelated speech.
  static bool _fuzzyContains(String haystack, String needle) {
    if (needle.isEmpty) return false;
    if (needle.length > haystack.length + 3) return false;

    final tolerance = (needle.length * 0.2).floor().clamp(1, 4);

    for (var start = 0; start <= haystack.length - 1; start++) {
      for (var pad = -1; pad <= 1; pad++) {
        final end = start + needle.length + pad;
        if (end > haystack.length || end <= start) continue;
        final window = haystack.substring(start, end);
        if (_editDistance(window, needle) <= tolerance) return true;
      }
    }
    return false;
  }

  /// Levenshtein distance, two-row variant.
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + cost;
        current[j] = deletion < insertion
            ? (deletion < substitution ? deletion : substitution)
            : (insertion < substitution ? insertion : substitution);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }

  /// Returns whatever the user said after the wake phrase, so "Hey EyePhone, is the path
  /// clear" runs the command immediately instead of making them speak twice.
  String? commandAfterWake(String transcript) {
    final normalized = normalize(transcript);
    if (normalized.isEmpty) return null;

    final candidates = <String>[
      normalize(phrase),
      if (_isDefaultPhrase) ..._defaultAliases.map(normalize),
    ]..sort((a, b) => b.length.compareTo(a.length)); // longest first

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final index = normalized.indexOf(candidate);
      if (index >= 0) {
        final tail = normalized.substring(index + candidate.length).trim();
        return tail.isEmpty ? null : tail;
      }
    }
    return null;
  }
}
