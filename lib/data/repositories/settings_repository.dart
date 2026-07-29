import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../app/appearance.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reading_settings.dart';
import '../database/app_database.dart';

class StoredSettings {
  const StoredSettings({
    required this.appearance,
    required this.readingSettings,
  });

  final AppAppearance appearance;
  final ReadingSettings readingSettings;
}

class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  Future<StoredSettings> load() async {
    final database = await _database.database;
    final rows = await database.query('app_settings');
    final values = <String, String>{
      for (final row in rows)
        row['setting_key']! as String: row['setting_value']! as String,
    };
    return StoredSettings(
      appearance: _appearanceFromJson(values['appearance']),
      readingSettings: _readingFromJson(values['reading_defaults']),
    );
  }

  Future<void> saveAppearance(AppAppearance appearance) {
    return _put(
      'appearance',
      jsonEncode({
        'mode': appearance.mode.name,
        'seed': appearance.seed.name,
        'textScale': appearance.textScale,
        'uiFont': appearance.uiFont.name,
        'desktopNavigationWidth': appearance.desktopNavigationWidth,
        'desktopNavigationCollapsed': appearance.desktopNavigationCollapsed,
      }),
    );
  }

  Future<void> saveReadingSettings(ReadingSettings settings) {
    return _put('reading_defaults', jsonEncode(_readingToMap(settings)));
  }

  Future<BookReadingOverride?> loadBookOverride(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'book_reading_overrides',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return null;
    return BookReadingOverride(
      bookId: bookId,
      settings: _readingFromMap(rows.single),
    );
  }

  Future<void> saveBookOverride(BookReadingOverride override) async {
    final database = await _database.database;
    await database.insert('book_reading_overrides', {
      'book_id': override.bookId,
      ..._readingToMap(override.settings),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearBookOverride(String bookId) async {
    final database = await _database.database;
    await database.delete(
      'book_reading_overrides',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> _put(String key, String value) async {
    final database = await _database.database;
    await database.insert('app_settings', {
      'setting_key': key,
      'setting_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  AppAppearance _appearanceFromJson(String? source) {
    if (source == null) return const AppAppearance();
    final value = jsonDecode(source) as Map<String, Object?>;
    return AppAppearance(
      mode: ThemeMode.values.byName(value['mode']! as String),
      seed: ThemeSeed.values.byName(value['seed']! as String),
      textScale: (value['textScale']! as num).toDouble(),
      uiFont: FontChoice.values.byName(value['uiFont']! as String),
      desktopNavigationWidth:
          ((value['desktopNavigationWidth'] as num?)?.toDouble() ?? 240)
              .clamp(220, 320)
              .toDouble(),
      desktopNavigationCollapsed: value['desktopNavigationCollapsed'] == true,
    );
  }

  ReadingSettings _readingFromJson(String? source) {
    if (source == null) return const ReadingSettings();
    return _readingFromMap(jsonDecode(source) as Map<String, Object?>);
  }

  ReadingSettings _readingFromMap(Map<String, Object?> value) {
    return ReadingSettings(
      font: FontChoice.values.byName(value['font']! as String),
      fontSize: (value['font_size']! as num).toDouble(),
      lineHeight: (value['line_height']! as num).toDouble(),
      pageMargin: (value['page_margin']! as num).toDouble(),
      doubleColumn:
          value['double_column'] == true || value['double_column'] == 1,
      layoutMode: ReaderLayoutMode.values.byName(
        value['layout_mode'] as String? ?? ReaderLayoutMode.scroll.name,
      ),
    );
  }

  Map<String, Object> _readingToMap(ReadingSettings settings) => {
    'font': settings.font.name,
    'font_size': settings.fontSize,
    'line_height': settings.lineHeight,
    'page_margin': settings.pageMargin,
    'double_column': settings.doubleColumn ? 1 : 0,
    'layout_mode': settings.layoutMode.name,
  };
}
