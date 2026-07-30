import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/bookmark_repository.dart';

void main() {
  late AppDatabase database;
  late BookmarkRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = BookmarkRepository(database);
  });

  tearDown(() => database.close());

  test('updates and clears a bookmark label', () async {
    final bookmark = await repository.add(
      bookId: 'book-id',
      locator: 'chapter:1',
      chapterTitle: 'Chapter 1',
    );

    await repository.updateLabel(bookmark.id, 'Important section');
    var bookmarks = await repository.listForBook(bookmark.bookId);
    expect(bookmarks.single.label, 'Important section');

    await repository.updateLabel(bookmark.id, null);
    bookmarks = await repository.listForBook(bookmark.bookId);
    expect(bookmarks.single.label, isNull);
  });
}
