import 'package:flutter/material.dart';

import '../domain/models/font_choice.dart';
import 'appearance.dart';

class _TomoReadSurfacePalette {
  const _TomoReadSurfacePalette({
    required this.scaffold,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
  });

  final Color scaffold;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outline;
  final Color outlineVariant;
}

abstract final class TomoReadTheme {
  static ThemeData build(AppAppearance appearance, {Brightness? brightness}) {
    final isDark = brightness == Brightness.dark;
    final palette = _surfacePalette(appearance.themeStyle, isDark);
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: appearance.seed.color,
      brightness: brightness ?? Brightness.light,
    );
    final colorScheme = generatedScheme.copyWith(
      surface: palette.surface,
      onSurface: palette.onSurface,
      onSurfaceVariant: palette.onSurfaceVariant,
      surfaceContainerLowest: palette.surfaceContainerLowest,
      surfaceContainerLow: palette.surfaceContainerLow,
      surfaceContainer: palette.surfaceContainer,
      surfaceContainerHigh: palette.surfaceContainerHigh,
      surfaceContainerHighest: palette.surfaceContainerHighest,
      outline: palette.outline,
      outlineVariant: palette.outlineVariant,
    );
    final fontFamily = appearance.uiFont.fontFamily;
    final textTheme = _textTheme(colorScheme, fontFamily);
    final outlineShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: colorScheme.outlineVariant),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.scaffold,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 56,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: outlineShape,
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: colorScheme.outlineVariant,
      ),
      navigationRailTheme: NavigationRailThemeData(
        groupAlignment: -1,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        selectedIconTheme: IconThemeData(
          color: colorScheme.onSecondaryContainer,
        ),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: colorScheme.outlineVariant),
        backgroundColor: colorScheme.surface,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: textTheme.labelMedium!.copyWith(
          color: colorScheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selectedTileColor: colorScheme.secondaryContainer,
        selectedColor: colorScheme.onSecondaryContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minVerticalPadding: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme colors, String? fontFamily) {
    final base = ThemeData(
      brightness: colors.brightness,
      fontFamily: fontFamily,
    ).textTheme;
    return base.copyWith(
      headlineMedium: base.headlineMedium?.copyWith(
        color: colors.onSurface,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.18,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: colors.onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: colors.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: colors.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: colors.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: colors.onSurfaceVariant,
        fontSize: 16,
        height: 1.55,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
        fontSize: 12,
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: colors.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: colors.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static _TomoReadSurfacePalette _surfacePalette(
    AppThemeStyle style,
    bool isDark,
  ) {
    if (isDark) {
      return switch (style) {
        AppThemeStyle.mist => const _TomoReadSurfacePalette(
          scaffold: Color(0xFF101715),
          surface: Color(0xFF17201E),
          onSurface: Color(0xFFE7EFEB),
          onSurfaceVariant: Color(0xFFBAC8C1),
          surfaceContainerLowest: Color(0xFF101715),
          surfaceContainerLow: Color(0xFF1D2825),
          surfaceContainer: Color(0xFF25312D),
          surfaceContainerHigh: Color(0xFF2D3935),
          surfaceContainerHighest: Color(0xFF37433F),
          outline: Color(0xFF85958D),
          outlineVariant: Color(0xFF3E4D47),
        ),
        AppThemeStyle.white => const _TomoReadSurfacePalette(
          scaffold: Color(0xFF18181A),
          surface: Color(0xFF202023),
          onSurface: Color(0xFFE8E8ED),
          onSurfaceVariant: Color(0xFFC8C7CE),
          surfaceContainerLowest: Color(0xFF18181A),
          surfaceContainerLow: Color(0xFF28282B),
          surfaceContainer: Color(0xFF303034),
          surfaceContainerHigh: Color(0xFF39393E),
          surfaceContainerHighest: Color(0xFF444449),
          outline: Color(0xFF929198),
          outlineVariant: Color(0xFF46464C),
        ),
        AppThemeStyle.paper => const _TomoReadSurfacePalette(
          scaffold: Color(0xFF211B16),
          surface: Color(0xFF2C241D),
          onSurface: Color(0xFFF0E6D2),
          onSurfaceVariant: Color(0xFFD5C6AF),
          surfaceContainerLowest: Color(0xFF211B16),
          surfaceContainerLow: Color(0xFF352C24),
          surfaceContainer: Color(0xFF40362C),
          surfaceContainerHigh: Color(0xFF4B4035),
          surfaceContainerHighest: Color(0xFF594C40),
          outline: Color(0xFFA99A84),
          outlineVariant: Color(0xFF51463B),
        ),
      };
    }
    return switch (style) {
      AppThemeStyle.mist => const _TomoReadSurfacePalette(
        scaffold: Color(0xFFF7F9F8),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF17211F),
        onSurfaceVariant: Color(0xFF53615C),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFF2F6F4),
        surfaceContainer: Color(0xFFECF1EF),
        surfaceContainerHigh: Color(0xFFE4EBE8),
        surfaceContainerHighest: Color(0xFFDCE5E1),
        outline: Color(0xFF6F7D76),
        outlineVariant: Color(0xFFD3DDD8),
      ),
      AppThemeStyle.white => const _TomoReadSurfacePalette(
        scaffold: Color(0xFFFAFAFA),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1C1C1E),
        onSurfaceVariant: Color(0xFF606167),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFF7F7F8),
        surfaceContainer: Color(0xFFF1F1F3),
        surfaceContainerHigh: Color(0xFFEBEBED),
        surfaceContainerHighest: Color(0xFFE4E4E7),
        outline: Color(0xFF74747A),
        outlineVariant: Color(0xFFDEDEE3),
      ),
      AppThemeStyle.paper => const _TomoReadSurfacePalette(
        scaffold: Color(0xFFF0E6D2),
        surface: Color(0xFFF5EBD7),
        onSurface: Color(0xFF3D2B1F),
        onSurfaceVariant: Color(0xFF7A6652),
        surfaceContainerLowest: Color(0xFFFFF7E8),
        surfaceContainerLow: Color(0xFFFAF0DD),
        surfaceContainer: Color(0xFFF0E3CC),
        surfaceContainerHigh: Color(0xFFE9DCC5),
        surfaceContainerHighest: Color(0xFFE1D2B9),
        outline: Color(0xFF7A6652),
        outlineVariant: Color(0xFFD4C4A8),
      ),
    };
  }
}
