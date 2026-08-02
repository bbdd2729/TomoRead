import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/content_chunk.dart';
import '../database/app_database.dart';

class ContentChunkRepository {
  ContentChunkRepository(this._database);

  final AppDatabase _database;

  Future<ContentIndexState?> loadState(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'content_index_states',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : _stateFromRow(rows.single);
  }

  Future<void> beginRebuild({
    required String bookId,
    required String contentHash,
    required int parserVersion,
    required int indexVersion,
  }) => _saveState(
    ContentIndexState(
      bookId: bookId,
      contentHash: contentHash,
      parserVersion: parserVersion,
      indexVersion: indexVersion,
      status: ContentIndexStatus.indexing,
      progress: 0,
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> reportProgress(String bookId, double progress) async {
    final database = await _database.database;
    await database.update(
      'content_index_states',
      {
        'progress': progress.clamp(0, 1),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: "book_id = ? AND status = 'indexing'",
      whereArgs: [bookId],
    );
  }

  Future<void> markFailed({
    required String bookId,
    required String contentHash,
    required int parserVersion,
    required int indexVersion,
    required Object error,
  }) => _saveState(
    ContentIndexState(
      bookId: bookId,
      contentHash: contentHash,
      parserVersion: parserVersion,
      indexVersion: indexVersion,
      status: ContentIndexStatus.failed,
      progress: 0,
      error: error.toString().substring(
        0,
        error.toString().length.clamp(0, 500).toInt(),
      ),
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> replaceForBook({
    required String bookId,
    required String contentHash,
    required int parserVersion,
    required int indexVersion,
    required List<ContentChunk> chunks,
  }) async {
    final database = await _database.database;
    final now = DateTime.now();
    await database.transaction((transaction) async {
      await transaction.delete(
        'content_chunks',
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      for (final chunk in chunks) {
        await transaction.insert('content_chunks', _chunkToRow(chunk));
      }
      await transaction.insert('content_index_states', {
        'book_id': bookId,
        'content_hash': contentHash,
        'parser_version': parserVersion,
        'index_version': indexVersion,
        'status': ContentIndexStatus.ready.name,
        'progress': 1.0,
        'error': null,
        'updated_at': now.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<ContentChunk>> listForBook(
    String bookId, {
    int? maxChapterIndex,
    int limit = 10000,
  }) async {
    final database = await _database.database;
    final safeLimit = limit.clamp(1, 10000).toInt();
    final rows = await database.query(
      'content_chunks',
      where: maxChapterIndex == null
          ? 'book_id = ?'
          : 'book_id = ? AND chapter_index <= ?',
      whereArgs: maxChapterIndex == null
          ? [bookId]
          : [bookId, maxChapterIndex],
      orderBy: 'ordinal ASC',
      limit: safeLimit,
    );
    return rows.map(_chunkFromRow).toList();
  }

  Future<List<ContentChunk>> listChapter(
    String bookId,
    int chapterIndex,
  ) async {
    final database = await _database.database;
    final rows = await database.query(
      'content_chunks',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      orderBy: 'ordinal ASC',
    );
    return rows.map(_chunkFromRow).toList();
  }

  Future<int> characterCountForBook(String bookId) async {
    final database = await _database.database;
    final rows = await database.rawQuery(
      'SELECT COALESCE(SUM(LENGTH(text_content)), 0) AS character_count '
      'FROM content_chunks WHERE book_id = ?',
      [bookId],
    );
    return (rows.single['character_count'] as num?)?.toInt() ?? 0;
  }

  Future<List<ContentSearchResult>> search({
    required String bookId,
    required String query,
    int? maxChapterIndex,
    int limit = 20,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final database = await _database.database;
    final conditions = <String>[
      'book_id = ?',
      "LOWER(text_content) LIKE LOWER(?) ESCAPE '\\'",
    ];
    final arguments = <Object?>[bookId, '%${_escapeLike(normalized)}%'];
    if (maxChapterIndex != null) {
      conditions.add('chapter_index <= ?');
      arguments.add(maxChapterIndex);
    }
    final rows = await database.query(
      'content_chunks',
      where: conditions.join(' AND '),
      whereArgs: arguments,
      orderBy: 'chapter_index ASC, ordinal ASC',
      limit: limit.clamp(1, 100).toInt(),
    );
    return rows.map((row) {
      final chunk = _chunkFromRow(row);
      return ContentSearchResult(
        chunk: chunk,
        excerpt: _excerpt(chunk.text, normalized),
      );
    }).toList();
  }

  Future<void> _saveState(ContentIndexState state) async {
    final database = await _database.database;
    await database.insert('content_index_states', {
      'book_id': state.bookId,
      'content_hash': state.contentHash,
      'parser_version': state.parserVersion,
      'index_version': state.indexVersion,
      'status': state.status.name,
      'progress': state.progress,
      'error': state.error,
      'updated_at': state.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, Object?> _chunkToRow(ContentChunk chunk) => {
    'id': chunk.id,
    'book_id': chunk.bookId,
    'chapter_id': chunk.chapterId,
    'chapter_index': chunk.chapterIndex,
    'chapter_title': chunk.chapterTitle,
    'href': chunk.href,
    'locator_start': chunk.locatorStart,
    'locator_end': chunk.locatorEnd,
    'raw_start': chunk.rawStart,
    'raw_end': chunk.rawEnd,
    'ordinal': chunk.ordinal,
    'text_content': chunk.text,
    'text_hash': chunk.textHash,
    'content_hash': chunk.contentHash,
    'parser_version': chunk.parserVersion,
    'index_version': chunk.indexVersion,
  };

  ContentChunk _chunkFromRow(Map<String, Object?> row) => ContentChunk(
    id: row['id']! as String,
    bookId: row['book_id']! as String,
    chapterId: row['chapter_id']! as String,
    chapterIndex: row['chapter_index']! as int,
    chapterTitle: row['chapter_title']! as String,
    href: row['href']! as String,
    locatorStart: row['locator_start']! as String,
    locatorEnd: row['locator_end']! as String,
    rawStart: row['raw_start']! as int,
    rawEnd: row['raw_end']! as int,
    ordinal: row['ordinal']! as int,
    text: row['text_content']! as String,
    textHash: row['text_hash']! as String,
    contentHash: row['content_hash']! as String,
    parserVersion: row['parser_version']! as int,
    indexVersion: row['index_version']! as int,
  );

  ContentIndexState _stateFromRow(Map<String, Object?> row) =>
      ContentIndexState(
        bookId: row['book_id']! as String,
        contentHash: row['content_hash']! as String,
        parserVersion: row['parser_version']! as int,
        indexVersion: row['index_version']! as int,
        status: ContentIndexStatus.values.firstWhere(
          (status) => status.name == row['status'],
          orElse: () => ContentIndexStatus.failed,
        ),
        progress: (row['progress']! as num).toDouble(),
        error: row['error'] as String?,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at']! as int,
        ),
      );

  String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  String _excerpt(String text, String query) {
    final index = text.toLowerCase().indexOf(query.toLowerCase());
    if (index < 0) return text.substring(0, text.length.clamp(0, 180).toInt());
    final start = (index - 56).clamp(0, text.length).toInt();
    final end = (index + query.length + 96).clamp(0, text.length).toInt();
    return '${start > 0 ? '…' : ''}${text.substring(start, end)}'
        '${end < text.length ? '…' : ''}';
  }
}
