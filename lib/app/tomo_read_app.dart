import 'package:flutter/material.dart';

import '../data/database/app_database.dart';
import '../data/repositories/bookmark_repository.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/book_import_service.dart';
import '../domain/models/font_choice.dart';
import '../domain/models/reading_settings.dart';
import '../features/library/library_controller.dart';
import '../features/workspace/app_shell.dart';
import 'appearance.dart';

class TomoReadApp extends StatefulWidget {
  const TomoReadApp({super.key, this.database});

  final AppDatabase? database;

  @override
  State<TomoReadApp> createState() => _TomoReadAppState();
}

class _TomoReadAppState extends State<TomoReadApp> {
  AppAppearance _appearance = const AppAppearance();
  ReadingSettings _readingSettings = const ReadingSettings();
  late final AppDatabase _database;
  late final SettingsRepository _settingsRepository;
  late final BookmarkRepository _bookmarkRepository;
  late final LibraryController _libraryController;
  var _isReady = false;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase();
    _settingsRepository = SettingsRepository(_database);
    _bookmarkRepository = BookmarkRepository(_database);
    final bookRepository = BookRepository(_database);
    _libraryController = LibraryController(
      repository: bookRepository,
      importService: BookImportService(repository: bookRepository),
    );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsRepository.load();
    if (!mounted) return;
    setState(() {
      _appearance = settings.appearance;
      _readingSettings = settings.readingSettings;
      _isReady = true;
    });
  }

  void _updateAppearance(AppAppearance appearance) {
    setState(() => _appearance = appearance);
    _settingsRepository.saveAppearance(appearance);
  }

  void _updateReadingSettings(ReadingSettings settings) {
    setState(() => _readingSettings = settings);
    _settingsRepository.saveReadingSettings(settings);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _appearance.seed.color),
      useMaterial3: true,
      fontFamily: _appearance.uiFont.fontFamily,
    );
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _appearance.seed.color,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: _appearance.uiFont.fontFamily,
    );

    return MaterialApp(
      title: 'TomoRead',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: _appearance.mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_appearance.textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: _isReady
          ? AppShell(
              appearance: _appearance,
              readingSettings: _readingSettings,
              settingsRepository: _settingsRepository,
              bookmarkRepository: _bookmarkRepository,
              libraryController: _libraryController,
              onAppearanceChanged: _updateAppearance,
              onReadingSettingsChanged: _updateReadingSettings,
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
