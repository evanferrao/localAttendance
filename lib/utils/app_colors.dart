import 'package:flutter/material.dart';

/// Modern Design System Palette (Material 3 Monet Dynamic Theming)
class AppColors {
  // Functional / Status Colors (Consistent across all themes)
  static const Color present = Color(0xFF10B981); // Emerald Present
  static const Color absent = Color(0xFFEF4444); // Red Absent
  static const Color warning = Color(0xFFF59E0B); // Amber Warning

  // Context-aware dynamic Monet accessors
  static Color primaryOf(BuildContext context) => Theme.of(context).colorScheme.primary;
  static Color onPrimaryOf(BuildContext context) => Theme.of(context).colorScheme.onPrimary;
  static Color primaryContainerOf(BuildContext context) => Theme.of(context).colorScheme.primaryContainer;
  static Color onPrimaryContainerOf(BuildContext context) => Theme.of(context).colorScheme.onPrimaryContainer;

  static Color surfaceOf(BuildContext context) => Theme.of(context).colorScheme.surface;
  static Color surfaceContainerOf(BuildContext context) => Theme.of(context).colorScheme.surfaceContainer;
  static Color surfaceContainerHighOf(BuildContext context) => Theme.of(context).colorScheme.surfaceContainerHigh;
  static Color surfaceContainerHighestOf(BuildContext context) => Theme.of(context).colorScheme.surfaceContainerHighest;

  static Color onSurfaceOf(BuildContext context) => Theme.of(context).colorScheme.onSurface;
  static Color onSurfaceVariantOf(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

  static Color borderOf(BuildContext context) => Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5);
  static Color borderSubtleOf(BuildContext context) => Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25);
}

/// Extension on BuildContext for quick, elegant access to Material 3 Monet theme tokens
extension AppThemeExtension on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
