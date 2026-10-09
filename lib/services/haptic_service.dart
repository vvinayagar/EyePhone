import 'package:flutter/services.dart';

class HapticService {
  bool enabled = true;

  HapticService({this.enabled = true});

  void lightTap() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  void mediumTap() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  void heavyTap() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }

  void selectionTick() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  void confirmTap() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Urgent haptic alert when an obstacle or hazard is directly in path
  Future<void> obstacleAlert() async {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.heavyImpact();
  }

  /// Gentle confirmation pattern when path is clear
  Future<void> pathClearPattern() async {
    if (!enabled) return;
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    HapticFeedback.lightImpact();
  }

  /// Pattern when voice listening begins
  Future<void> listeningStartPattern() async {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.selectionClick();
  }
}
