import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';

void main() {
  late AppDatabase database;
  late BookRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = BookRepository(database);
  });

  tearDown(() => database.close());

  test('persists editable metadata, tags, and favorite status', () async {
    final book = _book();
    await repository.saveImportedPdfBook(book);

    await repository.updateMetadata(
      bookId: book.id,
      title: 'Edited title',
      author: 'Edited author',
      description: 'Edited description',
      category: 'Technology',
      tags: const ['Dart', 'Flutter'],
    );
    await repository.setFavorite(book.id, true);

    final saved = await repository.findById(book.id);
    expect(saved, isNotNull);
    expect(saved!.title, 'Edited title');
    expect(saved.author, 'Edited author');
    expect(saved.description, 'Edited description');
    expect(saved.category, 'Technology');
    expect(saved.tags, ['Dart', 'Flutter']);
    expect(saved.isFavorite, isTrue);
  });

  test('resets saved reading position', () async {
    final book = _book();
    await repository.saveImportedPdfBook(book);
    await repository.updateReadingPosition(
      bookId: book.id,
      chapterIndex: 4,
      progress: 0.6,
      locator: 'chapter:4',
    );

    await repository.resetReadingPosition(book.id);

    final saved = await repository.findById(book.id);
    expect(saved!.chapterIndex, 0);
    expect(saved.progress, 0);
    expect(saved.locator, isNull);
  });

  test('updates favorite and category values for multiple books', () async {
    final first = _book();
    final second = _book(id: 'book-second', hash: 'hash-second');
    await repository.saveImportedPdfBook(first);
    await repository.saveImportedPdfBook(second);

    await repository.setFavoriteForBooks([first.id, second.id], true);
    await repository.setCategoryForBooks([first.id, second.id], 'Reference');

    final books = await repository.listBooks();
    expect(books.map((book) => book.isFavorite), everyElement(isTrue));
    expect(books.map((book) => book.category), everyElement('Reference'));
  });
}

LibraryBook _book({String id = 'book-id', String hash = 'hash'}) => LibraryBook(
  id: id,
  fileHash: hash,
  title: 'Original title',
  author: 'Original author',
  filePath: '/tmp/book.pdf',
  progress: 0,
  importedAt: DateTime(2026),
  format: 'pdf',
  chapterCount: 10,
  direction: ReadingDirection.ltr,
);
