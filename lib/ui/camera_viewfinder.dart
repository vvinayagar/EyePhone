import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/guidance_result.dart';
import '../services/camera_service.dart';
import '../utils/app_theme.dart';

class CameraViewfinder extends StatelessWidget {
  final CameraService cameraService;
  final GuidanceResult guidanceResult;
  final bool isScanning;

  const CameraViewfinder({
    super.key,
    required this.cameraService,
    required this.guidanceResult,
    required this.isScanning,
  });

  @override
  Widget build(BuildContext context) {
    final isInitialized = cameraService.isInitialized && cameraService.controller != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Preview or Simulated HUD
          if (isInitialized)
            CameraPreview(cameraService.controller!)
          else
            _buildCameraPlaceholder(),

          // High-contrast accessibility crosshair & clock guide
          _buildClockDirectionOverlay(),

          // Active scanning pulse overlay
          if (isScanning) _buildScanningAnimation(),

          // Directional Hazard Pointer (e.g. at 2 o'clock or 10 o'clock)
          if (!guidanceResult.isPathClear && guidanceResult.clockDirection != null)
            _buildDirectionalPointer(guidanceResult.clockDirection!),
        ],
      ),
    );
  }

  Widget _buildCameraPlaceholder() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.highVisYellow.withValues(alpha: 0.5), width: 3),
              ),
              child: const Icon(
                Icons.remove_red_eye_rounded,
                size: 64,
                color: AppTheme.highVisYellow,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'EYEPHONE VISION ENGINE',
              style: TextStyle(
                color: AppTheme.highVisYellow,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Camera active. Point phone in walking direction.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockDirectionOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            // Center crosshair
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.highVisYellow.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.highVisYellow,
                    ),
                  ),
                ),
              ),
            ),
            // Top clock label (12 o'clock - Ahead)
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '12h STRAIGHT AHEAD',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            // Left label (9 o'clock)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  '9h LEFT',
                  style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Right label (3 o'clock)
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text(
                  '3h RIGHT',
                  style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionalPointer(int clock) {
    Alignment alignment = Alignment.center;
    IconData arrowIcon = Icons.arrow_upward;

    if (clock == 12) {
      alignment = Alignment.topCenter;
      arrowIcon = Icons.arrow_upward;
    } else if (clock >= 1 && clock <= 2) {
      alignment = Alignment.topRight;
      arrowIcon = Icons.north_east;
    } else if (clock == 3) {
      alignment = Alignment.centerRight;
      arrowIcon = Icons.arrow_forward;
    } else if (clock >= 4 && clock <= 5) {
      alignment = Alignment.bottomRight;
      arrowIcon = Icons.south_east;
    } else if (clock >= 7 && clock <= 8) {
      alignment = Alignment.bottomLeft;
      arrowIcon = Icons.south_west;
    } else if (clock == 9) {
      alignment = Alignment.centerLeft;
      arrowIcon = Icons.arrow_back;
    } else if (clock >= 10 && clock <= 11) {
      alignment = Alignment.topLeft;
      arrowIcon = Icons.north_west;
    }

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.dangerRed,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.dangerRed.withValues(alpha: 0.6),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(arrowIcon, color: Colors.white, size: 28),
            const SizedBox(width: 6),
            Text(
              "HAZARD: $clock o'clock",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningAnimation() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.cyanAccent, width: 3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Container(
          width: double.infinity,
          height: 3,
          color: AppTheme.cyanAccent.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
