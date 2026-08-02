import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/text_chapter.dart';
import '../../domain/models/text_content_profile.dart';
import '../database/app_database.dart';

class TextContentRepository {
  TextContentRepository(this._database);

  final AppDatabase _database;

  Future<void> saveProfileAndChapters(
    TextContentProfile profile,
    List<TextChapter> chapters,
  ) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.insert('text_content_profiles', {
        'book_id': profile.bookId,
        'encoding': profile.encoding,
        'encoding_confidence': profile.encodingConfidence,
        'parser_version': profile.parserVersion,
        'content_hash': profile.contentHash,
        'updated_at': profile.updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _replaceChapters(transaction, profile.bookId, chapters);
      await transaction.update(
        'books',
        {
          'chapter_count': chapters.length,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [profile.bookId],
      );
    });
  }

  Future<TextContentProfile?> loadProfile(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'text_content_profiles',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : _profileFromRow(rows.single);
  }

  Future<List<TextChapter>> listChapters(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'text_chapters',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'ordinal ASC',
    );
    return rows.map(_chapterFromRow).toList();
  }

  Future<void> replaceChapters(
    String bookId,
    List<TextChapter> chapters,
  ) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await _replaceChapters(transaction, bookId, chapters);
      await transaction.update(
        'books',
        {
          'chapter_count': chapters.length,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [bookId],
      );
    });
  }

  Future<void> _replaceChapters(
    DatabaseExecutor database,
    String bookId,
    List<TextChapter> chapters,
  ) async {
    await database.delete(
      'text_chapters',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    for (var ordinal = 0; ordinal < chapters.length; ordinal++) {
      final chapter = chapters[ordinal];
      await database.insert('text_chapters', {
        'id': chapter.id,
        'book_id': bookId,
        'ordinal': ordinal,
        'title': chapter.title,
        'raw_start': chapter.rawStart,
        'raw_end': chapter.rawEnd,
        'source_rule_id': chapter.sourceRuleId,
        'content_hash': chapter.contentHash,
      });
    }
  }

  TextContentProfile _profileFromRow(Map<String, Object?> row) =>
      TextContentProfile(
        bookId: row['book_id']! as String,
        encoding: row['encoding']! as String,
        encodingConfidence: (row['encoding_confidence'] as num?)?.toDouble(),
        parserVersion: row['parser_version']! as int,
        contentHash: row['content_hash']! as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at']! as int,
        ),
      );

  TextChapter _chapterFromRow(Map<String, Object?> row) => TextChapter(
    id: row['id']! as String,
    bookId: row['book_id']! as String,
    ordinal: row['ordinal']! as int,
    title: row['title']! as String,
    rawStart: row['raw_start']! as int,
    rawEnd: row['raw_end']! as int,
    sourceRuleId: row['source_rule_id'] as String?,
    contentHash: row['content_hash']! as String,
  );
}
