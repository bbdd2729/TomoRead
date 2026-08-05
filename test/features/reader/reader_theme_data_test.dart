import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/reader_theme.dart';
import 'package:tomoread/domain/models/reading_settings.dart';
import 'package:tomoread/features/reader/reader_theme_data.dart';

void main() {
  final appTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
  );

  test('uses the app theme when the reader follows the application', () {
    final resolved = ReaderThemeData.build(
      appTheme,
      const ReadingSettings(),
      const [],
    );

    expect(resolved, same(appTheme));
  });

  test('builds the AMOLED reader palette independently from the app', () {
    final resolved = ReaderThemeData.build(
      appTheme,
      const ReadingSettings(
        theme: ReaderThemeSelection(preset: ReaderThemePreset.amoled),
      ),
      const [],
    );

    expect(resolved.scaffoldBackgroundColor, Colors.black);
    expect(resolved.colorScheme.onSurface, const Color(0xFFB8B8B8));
    expect(resolved.brightness, Brightness.dark);
  });

  test('derives reader colors from a saved three-color theme', () {
    const custom = CustomReaderTheme(
      id: 'night-ink',
      name: '夜墨',
      backgroundArgb: 0xFF101418,
      foregroundArgb: 0xFFE4E7EA,
      accentArgb: 0xFF74B9A8,
    );
    final resolved = ReaderThemeData.build(
      appTheme,
      const ReadingSettings(
        theme: ReaderThemeSelection(
          preset: ReaderThemePreset.custom,
          customThemeId: 'night-ink',
        ),
      ),
      const [custom],
    );

    expect(resolved.scaffoldBackgroundColor, const Color(0xFF101418));
    expect(resolved.colorScheme.surface, const Color(0xFF101418));
    expect(resolved.colorScheme.onSurface, const Color(0xFFE4E7EA));
    expect(resolved.colorScheme.primary, const Color(0xFF74B9A8));
  });

  test('falls back to the app theme when a custom theme was deleted', () {
    final resolved = ReaderThemeData.build(
      appTheme,
      const ReadingSettings(
        theme: ReaderThemeSelection(
          preset: ReaderThemePreset.custom,
          customThemeId: 'deleted-theme',
        ),
      ),
      const [],
    );

    expect(resolved, same(appTheme));
  });
}
