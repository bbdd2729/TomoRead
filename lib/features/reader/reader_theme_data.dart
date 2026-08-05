import 'package:flutter/material.dart';

import '../../domain/models/reader_theme.dart';
import '../../domain/models/reading_settings.dart';

class ReaderThemeColors {
  const ReaderThemeColors({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.isDark,
  });

  final Color background;
  final Color foreground;
  final Color accent;
  final bool isDark;
}

/// Resolves reader-only colors independently from the app shell. The result is
/// a real [ThemeData], so reader chrome, sheets and EPUB CSS all receive the
/// same palette on Android and desktop.
abstract final class ReaderThemeData {
  static ThemeData build(
    ThemeData appTheme,
    ReadingSettings settings,
    Iterable<CustomReaderTheme> customThemes,
  ) {
    final colors = resolveColors(appTheme, settings.theme, customThemes);
    if (settings.theme.preset == ReaderThemePreset.followApp ||
        (settings.theme.isCustom &&
            !customThemes.any(
              (theme) => theme.id == settings.theme.customThemeId,
            ))) {
      return appTheme;
    }
    final scheme = _colorScheme(colors);
    final textTheme = appTheme.textTheme.apply(
      bodyColor: colors.foreground,
      displayColor: colors.foreground,
      decorationColor: colors.foreground,
    );
    return appTheme.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme,
      appBarTheme: appTheme.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      cardTheme: appTheme.cardTheme.copyWith(color: scheme.surface),
      dividerTheme: appTheme.dividerTheme.copyWith(
        color: scheme.outlineVariant,
      ),
      inputDecorationTheme: appTheme.inputDecorationTheme.copyWith(
        fillColor: scheme.surfaceContainerLow,
      ),
      dialogTheme: appTheme.dialogTheme.copyWith(
        backgroundColor: scheme.surface,
      ),
      bottomSheetTheme: appTheme.bottomSheetTheme.copyWith(
        backgroundColor: scheme.surface,
      ),
      navigationBarTheme: appTheme.navigationBarTheme.copyWith(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }

  static ReaderThemeColors resolveColors(
    ThemeData appTheme,
    ReaderThemeSelection selection,
    Iterable<CustomReaderTheme> customThemes,
  ) {
    if (selection.preset == ReaderThemePreset.followApp) {
      final scheme = appTheme.colorScheme;
      return ReaderThemeColors(
        background: scheme.surface,
        foreground: scheme.onSurface,
        accent: scheme.primary,
        isDark: appTheme.brightness == Brightness.dark,
      );
    }
    if (selection.preset == ReaderThemePreset.custom) {
      final custom = customThemes.firstWhere(
        (theme) => theme.id == selection.customThemeId,
        orElse: () => const CustomReaderTheme(
          id: '',
          name: '',
          backgroundArgb: 0,
          foregroundArgb: 0,
          accentArgb: 0,
        ),
      );
      if (custom.id.isNotEmpty) {
        final background = Color(custom.backgroundArgb);
        return ReaderThemeColors(
          background: background,
          foreground: Color(custom.foregroundArgb),
          accent: Color(custom.accentArgb),
          isDark: background.computeLuminance() < .42,
        );
      }
    }
    return switch (selection.preset) {
      ReaderThemePreset.white => const ReaderThemeColors(
        background: Color(0xFFFCFCFA),
        foreground: Color(0xFF2A2A2A),
        accent: Color(0xFF466E92),
        isDark: false,
      ),
      ReaderThemePreset.mist => const ReaderThemeColors(
        background: Color(0xFFEAF0EC),
        foreground: Color(0xFF2A302E),
        accent: Color(0xFF3F6B5B),
        isDark: false,
      ),
      ReaderThemePreset.paper => const ReaderThemeColors(
        background: Color(0xFFFAF3E6),
        foreground: Color(0xFF32302A),
        accent: Color(0xFF76512D),
        isDark: false,
      ),
      ReaderThemePreset.eyeCare => const ReaderThemeColors(
        background: Color(0xFFF1F6E9),
        foreground: Color(0xFF2C312A),
        accent: Color(0xFF526B42),
        isDark: false,
      ),
      ReaderThemePreset.dark => const ReaderThemeColors(
        background: Color(0xFF141414),
        foreground: Color(0xFFCCCCCC),
        accent: Color(0xFFAAC7A1),
        isDark: true,
      ),
      ReaderThemePreset.amoled => const ReaderThemeColors(
        background: Color(0xFF000000),
        foreground: Color(0xFFB8B8B8),
        accent: Color(0xFFAAC7A1),
        isDark: true,
      ),
      ReaderThemePreset.followApp ||
      ReaderThemePreset.custom => ReaderThemeColors(
        background: appTheme.colorScheme.surface,
        foreground: appTheme.colorScheme.onSurface,
        accent: appTheme.colorScheme.primary,
        isDark: appTheme.brightness == Brightness.dark,
      ),
    };
  }

  static ColorScheme _colorScheme(ReaderThemeColors colors) {
    final containerLow = colors.isDark
        ? _mix(colors.background, Colors.white, .11)
        : _mix(colors.background, Colors.black, .035);
    final container = colors.isDark
        ? _mix(colors.background, Colors.white, .16)
        : _mix(colors.background, Colors.black, .07);
    final containerHigh = colors.isDark
        ? _mix(colors.background, Colors.white, .22)
        : _mix(colors.background, Colors.black, .11);
    final containerHighest = colors.isDark
        ? _mix(colors.background, Colors.white, .29)
        : _mix(colors.background, Colors.black, .16);
    final muted = colors.foreground.withValues(alpha: .66);
    final outline = colors.foreground.withValues(alpha: .5);
    final outlineVariant = colors.foreground.withValues(alpha: .16);
    final onPrimary = colors.accent.computeLuminance() > .45
        ? Colors.black
        : Colors.white;
    return ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: colors.isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: colors.accent,
      onPrimary: onPrimary,
      primaryContainer: _mix(
        colors.background,
        colors.accent,
        colors.isDark ? .3 : .18,
      ),
      onPrimaryContainer: colors.foreground,
      // EPUB CSS and the text reader consume `surface` as the paper color.
      // Keep it exact so a user-entered background swatch is never shifted.
      surface: colors.background,
      onSurface: colors.foreground,
      onSurfaceVariant: muted,
      surfaceContainerLowest: colors.background,
      surfaceContainerLow: containerLow,
      surfaceContainer: container,
      surfaceContainerHigh: containerHigh,
      surfaceContainerHighest: containerHighest,
      outline: outline,
      outlineVariant: outlineVariant,
    );
  }

  static Color _mix(Color start, Color end, double amount) =>
      Color.lerp(start, end, amount)!;
}
