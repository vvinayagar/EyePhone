import 'package:flutter/material.dart';
import '../../models/vision_mode.dart';
import '../../utils/app_theme.dart';

class ModeSelector extends StatelessWidget {
  final VisionMode currentMode;
  final Function(VisionMode) onModeSelected;

  const ModeSelector({
    super.key,
    required this.currentMode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Vision mode selector. Current mode is ${currentMode.title}. Swipe horizontally to switch.',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: VisionMode.values.map((mode) {
            final isSelected = mode == currentMode;
            IconData icon;
            switch (mode) {
              case VisionMode.navigation:
                icon = Icons.navigation_rounded;
                break;
              case VisionMode.readText:
                icon = Icons.menu_book_rounded;
                break;
              case VisionMode.sceneDescriber:
                icon = Icons.visibility_rounded;
                break;
              case VisionMode.findObject:
                icon = Icons.search_rounded;
                break;
            }

            return Expanded(
              child: Semantics(
                button: true,
                selected: isSelected,
                label: '${mode.title} mode',
                hint: isSelected ? 'Currently selected' : 'Double tap to activate ${mode.title}',
                child: GestureDetector(
                  onTap: () => onModeSelected(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.highVisYellow : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? Colors.black : AppTheme.textDim,
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mode.shortName,
                          style: TextStyle(
                            color: isSelected ? Colors.black : AppTheme.textDim,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
