import 'dart:io';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/material.dart';

enum AppThemeMode {
  system,
  light,
  dark,
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _keyThemeMode = 'theme_mode';
  static const String _keyDynamicColor = 'use_dynamic_color';
  static const String _keyAmoled = 'is_amoled';
  static const String _keySeedColor = 'seed_color';

  // Default Blue Monet seed color (M3 baseline blue on non-monet / older android / iOS)
  static const Color defaultMonetBlue = Color(0xFF0B57D0);

  AppThemeMode _themeMode = AppThemeMode.dark;
  bool _useDynamicColor = true;
  bool _isAmoled = true; // Default to AMOLED black as requested
  Color _seedColor = defaultMonetBlue;

  AppThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => isIOS ? false : _useDynamicColor;
  bool get isAmoled => isIOS ? false : _isAmoled;
  Color get seedColor => _seedColor;

  bool get isIOS {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  void init() {
    try {
      final box = HiveBoxes.settings;
      final modeIndex = box.get(_keyThemeMode, defaultValue: 2) as int; // 2 = dark
      _themeMode = AppThemeMode.values[modeIndex.clamp(0, AppThemeMode.values.length - 1)];

      _useDynamicColor = box.get(_keyDynamicColor, defaultValue: true) as bool;
      _isAmoled = box.get(_keyAmoled, defaultValue: true) as bool;

      // ignore: deprecated_member_use
      final seedVal = box.get(_keySeedColor, defaultValue: defaultMonetBlue.value) as int;
      _seedColor = Color(seedVal);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    try {
      final box = HiveBoxes.settings;
      await box.put(_keyThemeMode, mode.index);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setUseDynamicColor(bool value) async {
    if (isIOS) return;
    _useDynamicColor = value;
    try {
      final box = HiveBoxes.settings;
      await box.put(_keyDynamicColor, value);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setIsAmoled(bool value) async {
    if (isIOS) return;
    _isAmoled = value;
    try {
      final box = HiveBoxes.settings;
      await box.put(_keyAmoled, value);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    try {
      final box = HiveBoxes.settings;
      // ignore: deprecated_member_use
      await box.put(_keySeedColor, color.value);
    } catch (_) {}
    notifyListeners();
  }

  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  ThemeData buildLightTheme(ColorScheme? dynamicLight) {
    final ColorScheme scheme;
    if (!isIOS && _useDynamicColor && dynamicLight != null) {
      scheme = dynamicLight;
    } else {
      scheme = ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      );
    }

    return _buildTheme(scheme, isDark: false);
  }

  ThemeData buildDarkTheme(ColorScheme? dynamicDark) {
    ColorScheme scheme;
    if (!isIOS && _useDynamicColor && dynamicDark != null) {
      scheme = dynamicDark;
    } else {
      scheme = ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      );
    }

    final amoled = isAmoled;
    if (amoled) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainer: const Color(0xFF101010),
        surfaceContainerHigh: const Color(0xFF181818),
        surfaceContainerHighest: const Color(0xFF222222),
        onSurface: Colors.white,
      );
    }

    return _buildTheme(scheme, isDark: true, isAmoled: amoled);
  }

  ThemeData _buildTheme(ColorScheme scheme, {required bool isDark, bool isAmoled = false}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: (isAmoled && isDark) ? Colors.black : scheme.surface,
      cardColor: (isAmoled && isDark) ? const Color(0xFF121212) : scheme.surfaceContainer,
      canvasColor: (isAmoled && isDark) ? Colors.black : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: (isAmoled && isDark) ? Colors.black : Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (BuildContext context) => const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: (isAmoled && isDark) ? const Color(0xFF121212) : scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: (isAmoled && isDark)
                ? scheme.outlineVariant.withValues(alpha: 0.25)
                : scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primaryContainer;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onPrimaryContainer;
            }
            return scheme.onSurface;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return (isAmoled && isDark) ? const Color(0xFF222222) : scheme.surfaceContainerHighest;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: (isAmoled && isDark) ? const Color(0xFF181818) : scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        labelStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: (isAmoled && isDark) ? const Color(0xFF141414) : scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(color: scheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: (isAmoled && isDark) ? const Color(0xFF141414) : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: (isAmoled && isDark) ? const Color(0xFF222222) : scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: (isAmoled && isDark) ? const Color(0xFF141414) : scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.3),
        thickness: 1,
      ),
    );
  }
}
