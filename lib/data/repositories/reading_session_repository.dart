import '../../domain/models/reading_activity.dart';
import '../database/app_database.dart';

class ReadingSessionRepository {
  ReadingSessionRepository(this._database);

  final AppDatabase _database;

  Future<ReadingActivity> start({
    required String id,
    required String sessionGroupId,
    required ReaderIdentity identity,
    required ReaderPosition position,
    required DateTime nowUtc,
    required int timezoneOffsetMinutes,
  }) async {
    final database = await _database.database;
    await database.insert('reading_sessions', {
      'id': id,
      'book_id': identity.bookId,
      'session_group_id': sessionGroupId,
      'format': identity.format.name,
      'started_at': nowUtc.millisecondsSinceEpoch,
      'ended_at': null,
      'active_millis': 0,
      'timezone_offset_minutes': timezoneOffsetMinutes,
      'progress_start': position.progress.clamp(0, 1),
      'progress_end': position.progress.clamp(0, 1),
      'locator_start': position.locator,
      'locator_end': position.locator,
      'interaction_count': 1,
      'created_at': nowUtc.millisecondsSinceEpoch,
      'updated_at': nowUtc.millisecondsSinceEpoch,
    });
    return ReadingActivity(
      id: id,
      bookId: identity.bookId,
      sessionGroupId: sessionGroupId,
      format: identity.format,
      startedAtUtc: nowUtc,
      activeMillis: 0,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      progressStart: position.progress.clamp(0, 1).toDouble(),
      progressEnd: position.progress.clamp(0, 1).toDouble(),
      locatorStart: position.locator,
      locatorEnd: position.locator,
      interactionCount: 1,
      updatedAtUtc: nowUtc,
    );
  }

  Future<void> checkpoint({
    required String id,
    required DateTime nowUtc,
    required int activeMillis,
    required ReaderPosition position,
    required int interactionCount,
    DateTime? endedAtUtc,
  }) async {
    final database = await _database.database;
    await database.update(
      'reading_sessions',
      {
        'ended_at': endedAtUtc?.millisecondsSinceEpoch,
        'active_millis': activeMillis.clamp(0, 86400000),
        'progress_end': position.progress.clamp(0, 1),
        'locator_end': position.locator,
        'interaction_count': interactionCount,
        'updated_at': nowUtc.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> recoverOpenSessions(DateTime nowUtc) async {
    final database = await _database.database;
    final rows = await database.query(
      'reading_sessions',
      where: 'ended_at IS NULL',
    );
    for (final row in rows) {
      final startedAt = row['started_at']! as int;
      final updatedAt = row['updated_at']! as int;
      final safeEnd = updatedAt.clamp(startedAt, nowUtc.millisecondsSinceEpoch);
      await database.update(
        'reading_sessions',
        {'ended_at': safeEnd, 'updated_at': nowUtc.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<List<ReadingActivity>> listAll() async {
    final database = await _database.database;
    final rows = await database.query(
      'reading_sessions',
      where: 'ended_at IS NOT NULL AND active_millis > 0',
      orderBy: 'started_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  ReadingActivity _fromRow(Map<String, Object?> row) => ReadingActivity(
    id: row['id']! as String,
    bookId: row['book_id']! as String,
    sessionGroupId: row['session_group_id']! as String,
    format: ReaderFormat.values.byName(row['format']! as String),
    startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row['started_at']! as int,
      isUtc: true,
    ),
    endedAtUtc: row['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['ended_at']! as int,
            isUtc: true,
          ),
    activeMillis: row['active_millis']! as int,
    timezoneOffsetMinutes: row['timezone_offset_minutes']! as int,
    progressStart: (row['progress_start']! as num).toDouble(),
    progressEnd: (row['progress_end']! as num).toDouble(),
    locatorStart: row['locator_start'] as String?,
    locatorEnd: row['locator_end'] as String?,
    interactionCount: row['interaction_count']! as int,
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at']! as int,
      isUtc: true,
    ),
  );
}
