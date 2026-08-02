import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/reader_commands.dart';
import '../database/app_database.dart';

class ReaderCommandRepository {
  ReaderCommandRepository(this._database);

  static const _settingsKey = 'reader_commands';

  final AppDatabase _database;

  Future<ReaderCommandSettings> load() async {
    final database = await _database.database;
    final rows = await database.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [_settingsKey],
      limit: 1,
    );
    if (rows.isEmpty) return ReaderCommandSettings.defaults();
    try {
      return ReaderCommandSettings.fromJson(
        jsonDecode(rows.single['setting_value']! as String),
      );
    } on FormatException {
      return ReaderCommandSettings.defaults();
    }
  }

  Future<void> save(ReaderCommandSettings settings) async {
    final database = await _database.database;
    await database.insert('app_settings', {
      'setting_key': _settingsKey,
      'setting_value': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
