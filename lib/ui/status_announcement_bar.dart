import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/headphone_status.dart';
import '../services/guidance_controller.dart';
import '../utils/app_theme.dart';

class StatusAnnouncementBar extends StatelessWidget {
  final GuidanceController controller;
  final VoidCallback onOpenSettings;

  const StatusAnnouncementBar({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final hp = controller.headphoneStatus;
    // Reflect the engine that will actually serve the next scan, not what the
    // hardware could theoretically support.
    // The chip describes what will handle the next scene scan, so it tracks vision
    // capability — a loaded text-only model does not make this say "On-Device".
    final localReady =
        controller.settings.aiEngine.usesLocal && controller.localLlm.status.canSeeImages;
    final isNano = localReady;
    final engineLabel = localReady
        ? 'On-Device'
        : controller.settings.aiEngine.usesCloud
            ? 'Gemini Flash'
            : 'No Engine';
    final isContinuous = controller.isContinuousActive;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          // Headphone Status Badge
          Expanded(
            child: Semantics(
              label: hp.spokenDescription,
              hint: 'Double tap to hear headphone status',
              child: GestureDetector(
                onTap: () => controller.ttsService.speak(hp.spokenDescription, interrupt: true),
                child: Row(
                  children: [
                    Icon(
                      hp.isConnected
                          ? (hp.type == HeadphoneType.bluetooth ? Icons.headphones_rounded : Icons.headset_mic_rounded)
                          : Icons.volume_up_rounded,
                      color: hp.isConnected ? AppTheme.cyanAccent : AppTheme.highVisYellow,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        hp.displayLabel,
                        style: TextStyle(
                          color: hp.isConnected ? AppTheme.cyanAccent : AppTheme.highVisYellow,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // AI Engine Indicator (Gemini Nano vs Cloud)
          Semantics(
            label: localReady
                ? 'On-device AI active. Vision runs offline on this phone.'
                : controller.settings.aiEngine.usesCloud
                    ? 'Cloud Gemini Flash active'
                    : 'No vision engine available. Offline model not loaded.',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isNano ? Colors.deepPurple.shade900 : Colors.blueGrey.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isNano ? Colors.purpleAccent : Colors.cyan.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Text(
                engineLabel,
                style: TextStyle(
                  color: isNano ? Colors.purpleAccent.shade100 : AppTheme.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),

          if (isContinuous)
            Semantics(
              label: 'Continuous eyes guide is active',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.safeGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.safeGreen, width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, color: AppTheme.safeGreen, size: 8),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        color: AppTheme.safeGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Flashlight Toggle Button
          Semantics(
            button: true,
            label: controller.cameraService.isTorchOn ? 'Flashlight is on' : 'Flashlight is off',
            hint: 'Double tap to toggle flashlight',
            child: IconButton(
              icon: Icon(
                controller.cameraService.isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: controller.cameraService.isTorchOn ? AppTheme.highVisYellow : Colors.white60,
                size: 22,
              ),
              onPressed: () => controller.toggleTorch(),
            ),
          ),

          // Settings Button
          Semantics(
            button: true,
            label: 'Settings',
            hint: 'Double tap to configure API key, voice, and audio cues',
            child: IconButton(
              icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
              onPressed: onOpenSettings,
            ),
          ),
        ],
      ),
    );
  }
}
