import 'package:flutter/material.dart';
import '../models/guidance_result.dart';
import '../services/guidance_controller.dart';
import '../utils/app_theme.dart';
import 'camera_viewfinder.dart';
import 'gesture_overlay.dart';
import 'settings_sheet.dart';
import 'status_announcement_bar.dart';
import 'widgets/accessible_button.dart';
import 'widgets/hazard_badge.dart';
import 'widgets/mode_selector.dart';

class HomeScreen extends StatelessWidget {
  final GuidanceController controller;

  const HomeScreen({super.key, required this.controller});

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsSheet(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final result = controller.lastResult;
        final isScanning = controller.isScanning;
        final isListening = controller.isListening;
        final isContinuous = controller.isContinuousActive;

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: GestureOverlay(
              controller: controller,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top: Status Bar (Headphones, AICore Nano, Flashlight, Settings)
                    StatusAnnouncementBar(
                      controller: controller,
                      onOpenSettings: () => _openSettings(context),
                    ),
                    const SizedBox(height: 12),

                    // Mode Selector Bar (Navigation, Read Text, Describe, Find)
                    ModeSelector(
                      currentMode: controller.currentMode,
                      onModeSelected: (mode) => controller.switchMode(mode),
                    ),
                    const SizedBox(height: 12),

                    // Central Camera Viewfinder with Clock & Directional Hazard Overlays
                    Expanded(
                      flex: 5,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CameraViewfinder(
                              cameraService: controller.cameraService,
                              guidanceResult: result,
                              isScanning: isScanning,
                            ),
                          ),
                          // Hazard / Clear Path Badge. Sits below the viewfinder's
                          // "12h STRAIGHT AHEAD" label so neither covers the other.
                          Positioned(
                            top: CameraViewfinder.topLabelReserve,
                            left: 14,
                            right: 14,
                            child: Center(
                              child: HazardBadge(
                                result: result,
                                isScanning: isScanning,
                                isListening: isListening,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Spoken Guidance Card (Spoken into headphone)
                    _buildGuidanceCard(result),
                    const SizedBox(height: 12),

                    // Bottom Action Controls
                    // Giant Primary Voice Command Button (Click earbud or tap here)
                    AccessibleButton(
                      label: isListening ? 'LISTENING... SPEAK NOW' : 'PUSH TO TALK / ASK EYE',
                      semanticLabel: isListening
                          ? 'Listening for voice command. Speak now.'
                          : 'Push to talk button. Double tap screen or click headphone button to ask EyePhone.',
                      icon: isListening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                      isLarge: true,
                      isPulsing: isListening,
                      backgroundColor: isListening ? AppTheme.highVisYellow : AppTheme.surfaceLight,
                      foregroundColor: isListening ? Colors.black : AppTheme.highVisYellow,
                      onTap: () => controller.startVoiceInteraction(),
                    ),
                    const SizedBox(height: 10),

                    // Secondary Navigation Row: Quick Scan + Continuous Eyes Toggle
                    Row(
                      children: [
                        // Quick Scan Button
                        Expanded(
                          child: AccessibleButton(
                            label: 'SCAN NOW',
                            semanticLabel: 'Scan scene now. Analyzes view ahead for obstacles.',
                            icon: Icons.camera_alt_rounded,
                            onTap: () => controller.scanCurrentScene(),
                            backgroundColor: AppTheme.surfaceLight,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Continuous Guide Toggle
                        Expanded(
                          child: AccessibleButton(
                            label: isContinuous ? 'EYES: ON' : 'EYES: AUTO',
                            semanticLabel: isContinuous
                                ? 'Continuous eyes guide is active. Double tap to pause.'
                                : 'Continuous eyes guide is paused. Double tap to start auto-walking guidance.',
                            icon: isContinuous ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                            onTap: () => controller.toggleContinuousMode(),
                            backgroundColor: isContinuous ? AppTheme.safeGreen.withValues(alpha: 0.3) : AppTheme.surfaceLight,
                            foregroundColor: isContinuous ? AppTheme.safeGreen : AppTheme.textDim,
                            isPulsing: isContinuous,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuidanceCard(GuidanceResult result) {
    return Semantics(
      liveRegion: true,
      label: 'Spoken guidance: ${result.spokenText}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: result.isError
                ? AppTheme.textDim.withValues(alpha: 0.4)
                : result.isPathClear
                    ? AppTheme.safeGreen.withValues(alpha: 0.3)
                    : AppTheme.dangerRed.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_rounded, color: AppTheme.highVisYellow, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'AUDIO GUIDANCE',
                  style: TextStyle(
                    color: AppTheme.highVisYellow,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Text(
                  result.engineUsed,
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              result.spokenText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
