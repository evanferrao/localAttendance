import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_att/services/theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeService & Monet Theming Tests', () {
    final themeService = ThemeService();

    test('buildLightTheme generates light theme with custom seed color (e.g. Emerald)', () {
      const emerald = Color(0xFF059669);
      themeService.setSeedColor(emerald);

      final lightTheme = themeService.buildLightTheme(null);

      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.colorScheme.primary.value, isNotNull);
      // In Material 3, ColorScheme.fromSeed with Brightness.light generates primary tonal color from the seed
      expect(lightTheme.colorScheme.brightness, Brightness.light);
      // Background must NOT be black in light mode
      expect(lightTheme.scaffoldBackgroundColor, isNot(Colors.black));
      // Card color must be light container
      expect(lightTheme.cardTheme.color, lightTheme.colorScheme.surfaceContainer);
      // ElevatedButton must use scheme.primary
      expect(
        lightTheme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
        lightTheme.colorScheme.primary,
      );
    });

    test('buildDarkTheme with AMOLED generates pitch black surfaces', () {
      const emerald = Color(0xFF059669);
      themeService.setSeedColor(emerald);
      themeService.setIsAmoled(true);

      final darkTheme = themeService.buildDarkTheme(null);

      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, Colors.black);
      expect(darkTheme.cardTheme.color, const Color(0xFF121212));
      expect(
        darkTheme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
        darkTheme.colorScheme.primary,
      );
    });

    test('DynamicColor override is applied when dynamic color is active', () {
      const dynamicLight = ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF00AA55),
        onPrimary: Colors.white,
        secondary: Color(0xFF005522),
        onSecondary: Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: Color(0xFFF9F9F9),
        onSurface: Color(0xFF111111),
      );

      themeService.setUseDynamicColor(true);
      final theme = themeService.buildLightTheme(dynamicLight);

      expect(theme.colorScheme.primary, const Color(0xFF00AA55));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF9F9F9));
    });
  });
}
