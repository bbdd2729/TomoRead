import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import '../database/app_database.dart';

class BookRepository {
  BookRepository(this._database);

  final AppDatabase _database;

  Future<List<LibraryBook>> listBooks() async {
    final database = await _database.database;
    final rows = await database.query('books', orderBy: 'created_at DESC');
    return rows.map(_bookFromRow).toList();
  }

  Future<LibraryBook?> findByHash(String hash) async {
    final database = await _database.database;
    final rows = await database.query(
      'books',
      where: 'file_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isEmpty ? null : _bookFromRow(rows.single);
  }

  Future<LibraryBook?> findById(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'books',
      where: 'id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : _bookFromRow(rows.single);
  }

  Future<void> updateReadingPosition({
    required String bookId,
    required int chapterIndex,
    required double progress,
    String? locator,
  }) async {
    final database = await _database.database;
    await database.update(
      'books',
      {
        'chapter_index': chapterIndex,
        'progress': progress.clamp(0, 1),
        'locator': locator,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> saveImportedBook(ImportedBook importedBook) async {
    final database = await _database.database;
    final book = importedBook.book;
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.transaction((transaction) async {
      await transaction.insert('books', {
        'id': book.id,
        'file_hash': book.fileHash,
        'title': book.title,
        'author': book.author,
        'file_path': book.filePath,
        'cover_path': book.coverPath,
        'format': book.format,
        'description': book.description,
        'progress': book.progress,
        'chapter_index': 0,
        'chapter_count': book.chapterCount,
        'epub_version': importedBook.manifest.version,
        'read_direction': book.direction.name,
        'created_at': book.importedAt.millisecondsSinceEpoch,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.insert('book_manifests', {
        'book_id': book.id,
        'manifest_json': jsonEncode(importedBook.manifest.toJson()),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<EpubManifest?> loadManifest(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'book_manifests',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final source = rows.single['manifest_json']! as String;
    return EpubManifest.fromJson(jsonDecode(source) as Map<String, Object?>);
  }

  LibraryBook _bookFromRow(Map<String, Object?> row) => LibraryBook(
    id: row['id']! as String,
    fileHash: row['file_hash'] as String? ?? row['id']! as String,
    title: row['title']! as String,
    author: row['author']! as String,
    filePath: row['file_path'] as String? ?? '',
    coverPath: row['cover_path'] as String?,
    description: row['description'] as String?,
    progress: (row['progress']! as num).toDouble(),
    importedAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    format: row['format'] as String? ?? 'epub',
    chapterCount: row['chapter_count'] as int? ?? 0,
    chapterIndex: row['chapter_index'] as int? ?? 0,
    locator: row['locator'] as String?,
    direction: ReadingDirection.values.byName(
      row['read_direction'] as String? ?? ReadingDirection.ltr.name,
    ),
  );
}
