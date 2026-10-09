import 'package:flutter/material.dart';
import '../services/guidance_controller.dart';

class GestureOverlay extends StatelessWidget {
  final Widget child;
  final GuidanceController controller;

  const GestureOverlay({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // Single tap: Announce current status
        controller.announceStatus();
      },
      onDoubleTap: () {
        // Double tap: Activate voice assistant or scene scan
        controller.startVoiceInteraction();
      },
      onLongPress: () {
        // Long press: Emergency instant scan
        controller.scanCurrentScene();
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) {
          // Swipe Left -> Next mode
          controller.nextMode();
        } else if (velocity > 300) {
          // Swipe Right -> Previous mode
          controller.previousMode();
        }
      },
      child: child,
    );
  }
}
