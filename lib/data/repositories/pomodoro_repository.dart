import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/pomodoro.dart';
import '../database/app_database.dart';

class PomodoroRepository {
  PomodoroRepository(this._database);

  static const _configKey = 'pomodoro_config';
  static const _stateKey = 'pomodoro_active_state';

  final AppDatabase _database;

  Future<PomodoroConfig> loadConfig() async {
    final value = await _get(_configKey);
    if (value == null) return const PomodoroConfig();
    try {
      return PomodoroConfig.fromJson(
        jsonDecode(value) as Map<String, Object?>,
      );
    } on Object {
      return const PomodoroConfig();
    }
  }

  Future<PomodoroTimerState> loadState(PomodoroConfig config) async {
    final value = await _get(_stateKey);
    if (value == null) return PomodoroTimerState(config: config);
    try {
      return PomodoroTimerState.fromJson(
        jsonDecode(value) as Map<String, Object?>,
        config,
      );
    } on Object {
      return PomodoroTimerState(config: config);
    }
  }

  Future<void> saveConfig(PomodoroConfig config) =>
      _put(_configKey, jsonEncode(config.toJson()));

  Future<void> saveState(PomodoroTimerState state) =>
      _put(_stateKey, jsonEncode(state.toJson()));

  Future<void> finishSession(
    PomodoroSession session,
    PomodoroTimerState nextState,
  ) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.insert('pomodoro_sessions', {
        'id': session.id,
        'book_id': session.bookId,
        'phase': session.phase.name,
        'planned_millis': session.plannedMillis,
        'elapsed_millis': session.elapsedMillis,
        'status': session.status.name,
        'started_at': session.startedAtUtc.millisecondsSinceEpoch,
        'ended_at': session.endedAtUtc.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await _putWithExecutor(
        transaction,
        _stateKey,
        jsonEncode(nextState.toJson()),
      );
    });
  }

  Future<List<PomodoroSession>> listHistory({int limit = 100}) async {
    final database = await _database.database;
    final rows = await database.query(
      'pomodoro_sessions',
      orderBy: 'started_at DESC',
      limit: limit.clamp(1, 500),
    );
    return rows.map(_fromRow).toList();
  }

  Future<String?> _get(String key) async {
    final database = await _database.database;
    final rows = await database.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['setting_value']! as String;
  }

  Future<void> _put(String key, String value) async {
    final database = await _database.database;
    await _putWithExecutor(database, key, value);
  }

  Future<void> _putWithExecutor(
    DatabaseExecutor database,
    String key,
    String value,
  ) async {
    await database.insert('app_settings', {
      'setting_key': key,
      'setting_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  PomodoroSession _fromRow(Map<String, Object?> row) => PomodoroSession(
    id: row['id']! as String,
    bookId: row['book_id'] as String?,
    phase: PomodoroPhase.values.byName(row['phase']! as String),
    plannedMillis: row['planned_millis']! as int,
    elapsedMillis: row['elapsed_millis']! as int,
    status: PomodoroSessionStatus.values.byName(row['status']! as String),
    startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row['started_at']! as int,
      isUtc: true,
    ),
    endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row['ended_at']! as int,
      isUtc: true,
    ),
  );
}
