import 'package:face_att/services/face_recognition/ml_service.dart';
import 'package:face_att/services/theme_service.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ThemeService _themeService = ThemeService();
  final MLService _mlService = MLService();

  static const List<Map<String, dynamic>> _presetColors = [
    {'name': 'Monet Blue', 'color': Color(0xFF0B57D0)},
    {'name': 'Royal Navy', 'color': Color(0xFF2563EB)},
    {'name': 'Emerald', 'color': Color(0xFF059669)},
    {'name': 'Violet', 'color': Color(0xFF7C3AED)},
    {'name': 'Amber', 'color': Color(0xFFD97706)},
    {'name': 'Crimson', 'color': Color(0xFFE11D48)},
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeService,
      builder: (context, _) {
        final isIOS = _themeService.isIOS;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Appearance Section Header
              _sectionHeader(context, "Appearance & Theming"),

              // Theme Mode Selector
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Theme Mode",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<AppThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: AppThemeMode.system,
                            label: Text("System"),
                            icon: Icon(Icons.brightness_auto, size: 16),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.light,
                            label: Text("Light"),
                            icon: Icon(Icons.light_mode, size: 16),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.dark,
                            label: Text("Dark"),
                            icon: Icon(Icons.dark_mode, size: 16),
                          ),
                        ],
                        selected: {_themeService.themeMode},
                        onSelectionChanged: (newSelection) {
                          _themeService.setThemeMode(newSelection.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Android-only Monet & AMOLED Settings
              if (!isIOS) ...[
                // AMOLED Black Toggle
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: SwitchListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    secondary: Icon(Icons.contrast, color: colorScheme.primary),
                    title: Text(
                      "AMOLED Black",
                      style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      "Pure pitch black (#000000) for dark surfaces & battery saving",
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                    value: _themeService.isAmoled,
                    onChanged: (val) => _themeService.setIsAmoled(val),
                  ),
                ),

                // Dynamic Color (Material You / Monet) Toggle
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: SwitchListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    secondary: Icon(Icons.palette_outlined, color: colorScheme.primary),
                    title: Text(
                      "Dynamic Color (Material You)",
                      style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      "Extract Monet theme palette from device wallpaper (Android 12+)",
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                    value: _themeService.useDynamicColor,
                    onChanged: (val) => _themeService.setUseDynamicColor(val),
                  ),
                ),

                // Custom Accent Color (when Dynamic Color is disabled)
                if (!_themeService.useDynamicColor)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Custom Accent Palette",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Choose your preferred Material 3 accent color:",
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _presetColors.map((preset) {
                            final Color color = preset['color'] as Color;
                            final String name = preset['name'] as String;
                            // ignore: deprecated_member_use
                            final isSelected = _themeService.seedColor.value == color.value;

                            return GestureDetector(
                              onTap: () => _themeService.setSeedColor(color),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: isSelected ? 0.25 : 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected ? color : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(radius: 8, backgroundColor: color),
                                    const SizedBox(width: 8),
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? color : colorScheme.onSurface,
                                      ),
                                    ),
                                    if (isSelected) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.check, size: 14, color: color),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                // iOS Information Badge
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.apple, size: 24, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "iOS Build: Using default Blue Monet Material 3 theme. Monet and AMOLED Black configs are exclusive to Android.",
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              // App & System Information
              _sectionHeader(context, "About & Recognition Model"),
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.memory, color: colorScheme.primary),
                      title: const Text("Face Recognition Engine"),
                      subtitle: Text(_mlService.activeModelName),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined, color: AppColors.present),
                      title: const Text("Liveness & Anti-Spoofing"),
                      subtitle: const Text("ML Kit Blink & Head-Pose SpoofGuard"),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant),
                      title: const Text("App Version"),
                      subtitle: const Text("1.0.0 (On-Device Local Database)"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
