import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/font_choice.dart';
import '../features/workspace/app_shell.dart';
import 'appearance.dart';
import 'providers.dart';

class TomoReadApp extends StatelessWidget {
  const TomoReadApp({super.key, this.database});

  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (database != null) appDatabaseProvider.overrideWithValue(database!),
      ],
      child: const _TomoReadRoot(),
    );
  }
}

class _TomoReadRoot extends ConsumerWidget {
  const _TomoReadRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final appearance = settings.value?.appearance ?? const AppAppearance();
    final theme = _buildTheme(appearance);
    final darkTheme = _buildTheme(appearance, brightness: Brightness.dark);

    return MaterialApp(
      title: 'TomoRead',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: appearance.mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(appearance.textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: settings.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => Scaffold(
          body: Center(
            child: FilledButton.icon(
              onPressed: () => ref.invalidate(appSettingsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载设置'),
            ),
          ),
        ),
        data: (stored) => AppShell(
          appearance: stored.appearance,
          readingSettings: stored.readingSettings,
          onImportBooks: () async {
            await ref.read(libraryBooksProvider.notifier).importFromPicker();
          },
          onAppearanceChanged: (value) {
            ref.read(appSettingsProvider.notifier).updateAppearance(value);
          },
          onReadingSettingsChanged: (value) {
            ref.read(appSettingsProvider.notifier).updateReadingSettings(value);
          },
        ),
      ),
    );
  }
}

ThemeData _buildTheme(AppAppearance appearance, {Brightness? brightness}) {
  final isDark = brightness == Brightness.dark;
  final generatedScheme = ColorScheme.fromSeed(
    seedColor: appearance.seed.color,
    brightness: brightness ?? Brightness.light,
  );
  final colorScheme = generatedScheme.copyWith(
    surface: isDark ? const Color(0xFF181D1D) : const Color(0xFFFFFFFF),
    onSurface: isDark ? const Color(0xFFE2E8E6) : const Color(0xFF1A2020),
    onSurfaceVariant: isDark
        ? const Color(0xFFC0C9C7)
        : const Color(0xFF5B6563),
    surfaceContainerLowest: isDark
        ? const Color(0xFF111515)
        : const Color(0xFFFFFFFF),
    surfaceContainerLow: isDark
        ? const Color(0xFF1D2423)
        : const Color(0xFFF0F4F3),
    surfaceContainer: isDark
        ? const Color(0xFF242C2B)
        : const Color(0xFFE9EFED),
    surfaceContainerHigh: isDark
        ? const Color(0xFF2B3433)
        : const Color(0xFFE2E8E6),
    surfaceContainerHighest: isDark
        ? const Color(0xFF333D3B)
        : const Color(0xFFDCE3E0),
    outline: isDark ? const Color(0xFF8A9693) : const Color(0xFF737F7C),
    outlineVariant: isDark ? const Color(0xFF3F4947) : const Color(0xFFD4DCD9),
  );
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: appearance.uiFont.fontFamily,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF111515)
        : const Color(0xFFF6F8F7),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      toolbarHeight: 56,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontFamily: appearance.uiFont.fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer),
      selectedLabelTextStyle: TextStyle(color: colorScheme.onSurface),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colorScheme.secondaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: colorScheme.outlineVariant),
      backgroundColor: colorScheme.surface,
      selectedColor: colorScheme.secondaryContainer,
      labelStyle: TextStyle(color: colorScheme.onSurface),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      selectedTileColor: colorScheme.secondaryContainer,
      selectedColor: colorScheme.onSecondaryContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: colorScheme.onInverseSurface),
    ),
  );
}
