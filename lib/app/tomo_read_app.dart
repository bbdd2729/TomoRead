import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/database/app_database.dart';
import '../features/workspace/app_shell.dart';
import 'app_theme.dart';
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
    final theme = TomoReadTheme.build(appearance);
    final darkTheme = TomoReadTheme.build(
      appearance,
      brightness: Brightness.dark,
    );

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
