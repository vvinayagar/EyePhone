import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class AccessibleButton extends StatelessWidget {
  final String label;
  final String? semanticLabel;
  final String? semanticHint;
  final IconData icon;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLarge;
  final bool isPulsing;

  const AccessibleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
    this.semanticHint,
    this.backgroundColor = AppTheme.surfaceLight,
    this.foregroundColor = AppTheme.highVisYellow,
    this.isLarge = false,
    this.isPulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: semanticLabel ?? label,
      hint: semanticHint,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: foregroundColor.withValues(alpha: 0.3),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLarge ? 24 : 16,
              vertical: isLarge ? 18 : 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPulsing ? AppTheme.highVisYellow : foregroundColor.withValues(alpha: 0.4),
                width: isPulsing ? 3 : 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: isLarge ? 32 : 24, color: foregroundColor),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: isLarge ? 20 : 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
