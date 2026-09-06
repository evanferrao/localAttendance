import 'package:flutter/material.dart';

/// Centralized Navy Blue Design System Palette
class AppColors {
  // Deep Navy Backgrounds & Surfaces
  static const Color navyBackground = Color(0xFF0A1128);
  static const Color navySurface = Color(0xFF132247);
  static const Color navySurfaceElevated = Color(0xFF1B2E5B);
  static const Color navySurfaceHighlight = Color(0xFF243B73);

  // Primary Navy / Royal / Sapphire Accents
  static const Color primary = Color(0xFF2563EB); // Vibrant Royal/Navy Blue
  static const Color primaryLight = Color(0xFF60A5FA); // Ice/Sky Navy Accent
  static const Color primaryDark = Color(0xFF1D4ED8); // Deep Cobalt Navy
  static const Color accentCyan = Color(0xFF38BDF8); // Electric Cyan-Blue Accent

  // Borders & Dividers
  static final Color border = const Color(0xFF3B82F6).withValues(alpha: 0.25);
  static final Color borderSubtle = Colors.white.withValues(alpha: 0.08);

  // Functional / Status Colors
  static const Color present = Color(0xFF10B981); // Emerald Present
  static const Color absent = Color(0xFFEF4444); // Red Absent
  static const Color warning = Color(0xFFF59E0B); // Amber Warning

  // Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}
