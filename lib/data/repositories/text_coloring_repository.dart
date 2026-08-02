import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/text_coloring.dart';
import '../database/app_database.dart';

class TextColoringRepository {
  TextColoringRepository(this._database);

  static const _settingsKey = 'reader_text_coloring';
  static const maxTermLength = 100;
  static const maxGlobalTerms = 500;
  static const maxBookTerms = 300;

  final AppDatabase _database;

  Future<TextColoringSettings> loadSettings() async {
    final database = await _database.database;
    final rows = await database.query(
      'app_settings',
      columns: const ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: const [_settingsKey],
      limit: 1,
    );
    if (rows.isEmpty) return TextColoringSettings.defaults();
    try {
      return TextColoringSettings.fromJson(
        jsonDecode(rows.single['setting_value']! as String),
      );
    } on FormatException {
      return TextColoringSettings.defaults();
    }
  }

  Future<void> saveSettings(TextColoringSettings settings) async {
    final database = await _database.database;
    await database.insert('app_settings', {
      'setting_key': _settingsKey,
      'setting_value': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool?> loadBookOverride(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'book_text_coloring_overrides',
      columns: const ['enabled'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty || rows.single['enabled'] == null) return null;
    return rows.single['enabled'] == 1;
  }

  Future<void> saveBookOverride(String bookId, bool? enabled) async {
    final database = await _database.database;
    if (enabled == null) {
      await database.delete(
        'book_text_coloring_overrides',
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      return;
    }
    await database.insert('book_text_coloring_overrides', {
      'book_id': bookId,
      'enabled': enabled ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TextColorTerm>> listTerms({
    String? bookId,
    bool includeGlobal = false,
  }) async {
    final database = await _database.database;
    final rows = await database.query(
      'text_color_terms',
      where: switch ((bookId, includeGlobal)) {
        (null, _) => 'book_id IS NULL',
        (_, true) => '(book_id = ? OR book_id IS NULL)',
        (_, false) => 'book_id = ?',
      },
      whereArgs: bookId == null ? null : [bookId],
      orderBy:
          'CASE WHEN book_id IS NULL THEN 1 ELSE 0 END, updated_at DESC, id DESC',
    );
    return rows.map(_termFromRow).toList();
  }

  Future<TextColorTerm> assignTerm({
    required String term,
    required TextColorTermTone tone,
    String? bookId,
  }) async {
    final displayTerm = term.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalized = normalizeTextColorTerm(displayTerm);
    if (normalized.isEmpty) {
      throw const TextColoringException('文字词条不能为空。');
    }
    if (displayTerm.runes.length > maxTermLength) {
      throw const TextColoringException('文字词条不能超过 100 个字符。');
    }
    final database = await _database.database;
    return database.transaction((transaction) async {
      final existing = await transaction.query(
        'text_color_terms',
        where: bookId == null
            ? 'book_id IS NULL AND normalized_term = ?'
            : 'book_id = ? AND normalized_term = ?',
        whereArgs: bookId == null ? [normalized] : [bookId, normalized],
        limit: 1,
      );
      final now = DateTime.now();
      if (existing.isNotEmpty) {
        final id = existing.single['id']! as String;
        await transaction.update(
          'text_color_terms',
          {
            'term': displayTerm,
            'color_token': tone.name,
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        return TextColorTerm(
          id: id,
          bookId: bookId,
          term: displayTerm,
          normalizedTerm: normalized,
          tone: tone,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            existing.single['created_at']! as int,
          ),
          updatedAt: now,
        );
      }

      final countRows = await transaction.rawQuery(
        bookId == null
            ? 'SELECT COUNT(*) FROM text_color_terms WHERE book_id IS NULL'
            : 'SELECT COUNT(*) FROM text_color_terms WHERE book_id = ?',
        bookId == null ? null : [bookId],
      );
      final count = (countRows.single.values.single as num).toInt();
      final maximum = bookId == null ? maxGlobalTerms : maxBookTerms;
      if (count >= maximum) {
        throw TextColoringException(
          bookId == null ? '全局文字词条最多 500 条。' : '每本书的文字词条最多 300 条。',
        );
      }

      final id = '${now.microsecondsSinceEpoch}-${bookId ?? 'global'}';
      await transaction.insert('text_color_terms', {
        'id': id,
        'book_id': bookId,
        'term': displayTerm,
        'normalized_term': normalized,
        'color_token': tone.name,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });
      return TextColorTerm(
        id: id,
        bookId: bookId,
        term: displayTerm,
        normalizedTerm: normalized,
        tone: tone,
        createdAt: now,
        updatedAt: now,
      );
    });
  }

  Future<void> removeTerm(String id) async {
    final database = await _database.database;
    await database.delete(
      'text_color_terms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  TextColorTerm _termFromRow(Map<String, Object?> row) => TextColorTerm(
    id: row['id']! as String,
    bookId: row['book_id'] as String?,
    term: row['term']! as String,
    normalizedTerm: row['normalized_term']! as String,
    tone: TextColorTermTone.values.byName(row['color_token']! as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}
