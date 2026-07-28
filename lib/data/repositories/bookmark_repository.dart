import '../../domain/models/bookmark.dart';
import '../database/app_database.dart';

class BookmarkRepository {
  BookmarkRepository(this._database);

  final AppDatabase _database;

  Future<List<Bookmark>> listForBook(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => Bookmark(
            id: row['id']! as String,
            bookId: row['book_id']! as String,
            locator: row['locator']! as String,
            chapterTitle: row['chapter_title']! as String,
            label: row['label'] as String?,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at']! as int,
            ),
          ),
        )
        .toList();
  }

  Future<Bookmark> add({
    required String bookId,
    required String locator,
    required String chapterTitle,
    String? label,
  }) async {
    final bookmark = Bookmark(
      id: '${DateTime.now().microsecondsSinceEpoch}-$bookId',
      bookId: bookId,
      locator: locator,
      chapterTitle: chapterTitle,
      label: label,
      createdAt: DateTime.now(),
    );
    final database = await _database.database;
    await database.insert('bookmarks', {
      'id': bookmark.id,
      'book_id': bookmark.bookId,
      'locator': bookmark.locator,
      'chapter_title': bookmark.chapterTitle,
      'label': bookmark.label,
      'created_at': bookmark.createdAt.millisecondsSinceEpoch,
    });
    return bookmark;
  }

  Future<void> remove(String bookmarkId) async {
    final database = await _database.database;
    await database.delete(
      'bookmarks',
      where: 'id = ?',
      whereArgs: [bookmarkId],
    );
  }
}
