import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/annotation_repository.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/repositories/bookmark_repository.dart';
import 'package:tomoread/data/repositories/settings_repository.dart';
import 'package:tomoread/data/services/book_storage_service.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_annotation.dart';
import 'package:tomoread/domain/models/reading_settings.dart';

void main() {
  late AppDatabase database;
  late BookRepository books;
  late BookmarkRepository bookmarks;
  late AnnotationRepository annotations;
  late SettingsRepository settings;
  late Directory root;

  setUp(() async {
    database = AppDatabase.inMemory();
    books = BookRepository(database);
    bookmarks = BookmarkRepository(database);
    annotations = AnnotationRepository(database);
    settings = SettingsRepository(database);
    root = await Directory.systemTemp.createTemp('tomoread_storage_test_');
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('removes book records and managed files', () async {
    final library = Directory(path.join(root.path, 'library'));
    final bookFile = File(path.join(library.path, 'books', 'book-a.pdf'));
    final coverFile = File(path.join(library.path, 'covers', 'book-a.png'));
    final extracted = Directory(path.join(library.path, 'extracted', 'book-a'));
    await bookFile.parent.create(recursive: true);
    await coverFile.parent.create(recursive: true);
    await extracted.create(recursive: true);
    await bookFile.writeAsBytes([1, 2, 3]);
    await coverFile.writeAsBytes([4, 5, 6]);
    await File(
      path.join(extracted.path, '.complete'),
    ).writeAsString('complete');

    final book = LibraryBook(
      id: 'book-a',
      fileHash: 'book-a',
      title: 'Book A',
      author: '',
      filePath: bookFile.path,
      coverPath: coverFile.path,
      progress: 0,
      importedAt: DateTime(2026),
      format: 'pdf',
      chapterCount: 1,
      direction: ReadingDirection.ltr,
    );
    await books.saveImportedPdfBook(book);
    await bookmarks.add(
      bookId: book.id,
      locator: 'page:1',
      chapterTitle: 'Page 1',
    );
    await annotations.add(
      bookId: book.id,
      href: 'page:1',
      locator: '0:4',
      selectedText: 'Text',
      color: AnnotationColor.yellow,
    );
    await settings.saveBookOverride(
      const BookReadingOverride(bookId: 'book-a', settings: ReadingSettings()),
    );

    final result = await BookStorageService(
      repository: books,
      libraryRootProvider: () async => root,
    ).removeBook(book);

    expect(result.hasCleanupErrors, isFalse);
    expect(await books.findById(book.id), isNull);
    expect(await bookmarks.listForBook(book.id), isEmpty);
    expect(await annotations.listForBook(book.id), isEmpty);
    expect(await settings.loadBookOverride(book.id), isNull);
    expect(await bookFile.exists(), isFalse);
    expect(await coverFile.exists(), isFalse);
    expect(await extracted.exists(), isFalse);
  });

  test('does not remove files outside the managed library directory', () async {
    final externalFile = File(path.join(root.path, 'external.pdf'));
    await externalFile.writeAsBytes([1, 2, 3]);
    final book = LibraryBook(
      id: 'book-external',
      fileHash: 'book-external',
      title: 'External Book',
      author: '',
      filePath: externalFile.path,
      progress: 0,
      importedAt: DateTime(2026),
      format: 'pdf',
      chapterCount: 1,
      direction: ReadingDirection.ltr,
    );
    await books.saveImportedPdfBook(book);

    await BookStorageService(
      repository: books,
      libraryRootProvider: () async => root,
    ).removeBook(book);

    expect(await books.findById(book.id), isNull);
    expect(await externalFile.exists(), isTrue);
  });
}
