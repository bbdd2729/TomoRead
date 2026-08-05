import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/app/app_theme.dart';
import 'package:tomoread/app/appearance.dart';

void main() {
  group('TomoReadTheme', () {
    test(
      'uses the paper palette for the light application and reader surface',
      () {
        final theme = TomoReadTheme.build(
          const AppAppearance(themeStyle: AppThemeStyle.paper),
        );

        expect(theme.scaffoldBackgroundColor, const Color(0xFFF0E6D2));
        expect(theme.colorScheme.surface, const Color(0xFFF5EBD7));
        expect(theme.colorScheme.onSurface, const Color(0xFF3D2B1F));
      },
    );

    test('keeps a comfortable dark paper variant', () {
      final theme = TomoReadTheme.build(
        const AppAppearance(themeStyle: AppThemeStyle.paper),
        brightness: Brightness.dark,
      );

      expect(theme.scaffoldBackgroundColor, const Color(0xFF211B16));
      expect(theme.colorScheme.surface, const Color(0xFF2C241D));
      expect(theme.colorScheme.onSurface, const Color(0xFFF0E6D2));
    });

    test('uses a neutral white palette when requested', () {
      final theme = TomoReadTheme.build(
        const AppAppearance(themeStyle: AppThemeStyle.white),
      );

      expect(theme.scaffoldBackgroundColor, const Color(0xFFFAFAFA));
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.colorScheme.onSurface, const Color(0xFF1C1C1E));
    });
  });
}
