import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/display_projection.dart';
import '../database/app_database.dart';

class TextProjectionRepository {
  TextProjectionRepository(this._database);

  static const _globalSettingsKey = 'text_projection_defaults';
  final AppDatabase _database;

  Future<TextProjectionSettings> loadSettings(String bookId) async {
    final database = await _database.database;
    final bookRows = await database.query(
      'book_text_projection_settings',
      columns: ['settings_json'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (bookRows.isNotEmpty) {
      return _decodeSettings(bookRows.single['settings_json']);
    }
    final globalRows = await database.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [_globalSettingsKey],
      limit: 1,
    );
    return globalRows.isEmpty
        ? const TextProjectionSettings()
        : _decodeSettings(globalRows.single['setting_value']);
  }

  Future<void> saveSettings(
    TextProjectionSettings settings, {
    String? bookId,
  }) async {
    final database = await _database.database;
    final encoded = jsonEncode(settings.toJson());
    if (bookId == null) {
      await database.insert('app_settings', {
        'setting_key': _globalSettingsKey,
        'setting_value': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }
    await database.insert('book_text_projection_settings', {
      'book_id': bookId,
      'settings_json': encoded,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearBookSettings(String bookId) async {
    final database = await _database.database;
    await database.delete(
      'book_text_projection_settings',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<TextDisplayRule>> listRules(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'text_display_rules',
      where: 'book_id IS NULL OR book_id = ?',
      whereArgs: [bookId],
      orderBy:
          'CASE WHEN book_id IS NULL THEN 1 ELSE 0 END, priority DESC, '
          'length(find_text) DESC, created_at ASC',
    );
    return rows.map(_ruleFromRow).toList();
  }

  Future<TextDisplayRule> saveRule({
    String? id,
    String? bookId,
    required String name,
    required String findText,
    required String replaceText,
    bool enabled = true,
    int priority = 0,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 120) {
      throw const FormatException('规则名称应为 1–120 个字符。');
    }
    if (findText.isEmpty || findText.length > 200 || replaceText.length > 200) {
      throw const FormatException('查找文本应为 1–200 个字符，替换文本最多 200 个字符。');
    }
    final database = await _database.database;
    if (id == null) {
      final countRows = await database.rawQuery(
          bookId == null
              ? 'SELECT COUNT(*) FROM text_display_rules WHERE book_id IS NULL'
              : 'SELECT COUNT(*) FROM text_display_rules WHERE book_id = ?',
          bookId == null ? null : [bookId],
      );
      final count = (countRows.first.values.first as num).toInt();
      if (count >= 100) {
        throw const FormatException('每个作用域最多保存 100 条替换规则。');
      }
    }
    final now = DateTime.now();
    final ruleId = id ??
        sha256
            .convert(
              utf8.encode(
                '${bookId ?? 'global'}:$findText:${now.microsecondsSinceEpoch}',
              ),
            )
            .toString()
            .substring(0, 24);
    final old = id == null
        ? const <Map<String, Object?>>[]
        : await database.query(
            'text_display_rules',
            columns: ['created_at'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
    final createdAt = old.isEmpty
        ? now.millisecondsSinceEpoch
        : old.single['created_at']! as int;
    await database.insert('text_display_rules', {
      'id': ruleId,
      'book_id': bookId,
      'name': cleanName,
      'find_text': findText,
      'replace_text': replaceText,
      'enabled': enabled ? 1 : 0,
      'priority': priority.clamp(-1000, 1000).toInt(),
      'created_at': createdAt,
      'updated_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return TextDisplayRule(
      id: ruleId,
      bookId: bookId,
      name: cleanName,
      findText: findText,
      replaceText: replaceText,
      enabled: enabled,
      priority: priority.clamp(-1000, 1000).toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: now,
    );
  }

  Future<void> deleteRule(String id) async {
    final database = await _database.database;
    await database.delete(
      'text_display_rules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  TextProjectionSettings _decodeSettings(Object? source) {
    if (source is! String) return const TextProjectionSettings();
    try {
      return TextProjectionSettings.fromJson(
        jsonDecode(source) as Map<String, Object?>,
      );
    } on Object {
      return const TextProjectionSettings();
    }
  }

  TextDisplayRule _ruleFromRow(Map<String, Object?> row) => TextDisplayRule(
    id: row['id']! as String,
    bookId: row['book_id'] as String?,
    name: row['name']! as String,
    findText: row['find_text']! as String,
    replaceText: row['replace_text']! as String,
    enabled: row['enabled'] == 1,
    priority: row['priority']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}
