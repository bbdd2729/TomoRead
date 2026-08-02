import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/tts.dart';
import '../database/app_database.dart';

class TtsRepository implements TtsStateStore {
  TtsRepository(this._database);

  final AppDatabase _database;

  static const _settingsKey = 'tts_preferences';
  static String _cursorKey(String bookId) => 'tts_cursor:$bookId';

  @override
  Future<TtsSettings> loadSettings() async {
    final value = await _get(_settingsKey);
    if (value == null) return const TtsSettings();
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      return TtsSettings(
        rate: ((json['rate'] as num?)?.toDouble() ?? .5)
            .clamp(.1, 1)
            .toDouble(),
        volume: ((json['volume'] as num?)?.toDouble() ?? 1)
            .clamp(0, 1)
            .toDouble(),
        language: json['language'] as String? ?? 'zh-CN',
        voiceId: json['voiceId'] as String?,
        keepAwake: json['keepAwake'] == true,
      );
    } on Object {
      return const TtsSettings();
    }
  }

  @override
  Future<void> saveSettings(TtsSettings settings) => _put(
    _settingsKey,
    jsonEncode({
      'rate': settings.rate,
      'volume': settings.volume,
      'language': settings.language,
      'voiceId': settings.voiceId,
      'keepAwake': settings.keepAwake,
    }),
  );

  @override
  Future<TtsCursor?> loadCursor(String bookId) async {
    final value = await _get(_cursorKey(bookId));
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      return TtsCursor(
        bookId: bookId,
        segmentId: json['segmentId']! as String,
        locator: json['locator']! as String,
        chapterIndex: json['chapterIndex']! as int,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          json['updatedAt']! as int,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveCursor(TtsCursor cursor) => _put(
    _cursorKey(cursor.bookId),
    jsonEncode({
      'segmentId': cursor.segmentId,
      'locator': cursor.locator,
      'chapterIndex': cursor.chapterIndex,
      'updatedAt': cursor.updatedAt.millisecondsSinceEpoch,
    }),
  );

  Future<String?> _get(String key) async {
    final database = await _database.database;
    final rows = await database.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['setting_value'] as String?;
  }

  Future<void> _put(String key, String value) async {
    final database = await _database.database;
    await database.insert('app_settings', {
      'setting_key': key,
      'setting_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
