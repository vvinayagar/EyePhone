import 'package:flutter/material.dart';
import '../../models/guidance_result.dart';
import '../../utils/app_theme.dart';

class HazardBadge extends StatelessWidget {
  final GuidanceResult result;
  final bool isScanning;
  final bool isListening;

  const HazardBadge({
    super.key,
    required this.result,
    this.isScanning = false,
    this.isListening = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isListening) {
      return Semantics(
        label: 'Listening for voice command. Speak now.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.highVisYellow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, color: Colors.black, size: 24),
              SizedBox(width: 8),
              Text(
                'LISTENING... SPEAK NOW',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isScanning) {
      return Semantics(
        label: 'Scanning scene with camera',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.cyanAccent.withValues(alpha: 0.2),
            border: Border.all(color: AppTheme.cyanAccent, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.cyanAccent),
                ),
              ),
              SizedBox(width: 10),
              Text(
                'AI ANALYZING SCENE...',
                style: TextStyle(
                  color: AppTheme.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isClear = result.isPathClear;

    // Priority mirrors the audio cues: hazard, then person, then door. A person or a
    // door that must be opened is actionable even when the path is otherwise clear.
    final Color color;
    final IconData icon;
    final String title;

    if (result.isError) {
      // Neutral, not red: a failed scan is a problem with the app, not a hazard ahead.
      color = AppTheme.textDim;
      icon = result.failure == ScanFailure.camera
          ? Icons.no_photography_rounded
          : Icons.cloud_off_rounded;
      title = result.failure!.badgeTitle;
    } else if (!isClear) {
      color = AppTheme.dangerRed;
      icon = Icons.warning_amber_rounded;
      title = 'OBSTACLE DETECTED';
    } else if (result.personAhead) {
      color = AppTheme.highVisYellow;
      icon = Icons.person_rounded;
      title = 'PERSON AHEAD';
    } else if (result.doorNeedsOpening) {
      color = AppTheme.highVisYellow;
      icon = Icons.door_front_door_rounded;
      title = 'DOOR — OPEN IT';
    } else if (result.doorState != DoorState.none) {
      color = AppTheme.cyanAccent;
      icon = Icons.sensor_door_rounded;
      title = result.doorState == DoorState.partlyOpen ? 'DOOR PARTLY OPEN' : 'DOOR OPEN';
    } else {
      color = AppTheme.safeGreen;
      icon = Icons.check_circle;
      title = 'PATH CLEAR';
    }

    return Semantics(
      label: '$title. ${result.spokenText}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
            if (!result.isError && result.clockDirection != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${result.clockDirection} o'clock",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
