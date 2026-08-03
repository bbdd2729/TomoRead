import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';

void main() {
  test(
    'reader position updates the visible library cache immediately',
    () async {
      final database = AppDatabase.inMemory();
      final repository = BookRepository(database);
      final book = LibraryBook(
        id: 'reader-book',
        fileHash: 'reader-book',
        title: 'Reader book',
        author: 'Author',
        filePath: 'C:/books/reader.pdf',
        progress: 0,
        importedAt: DateTime(2026, 1, 1),
        format: 'pdf',
        chapterCount: 20,
        direction: ReadingDirection.ltr,
      );
      await repository.saveImportedPdfBook(book);
      final container = ProviderContainer(
        overrides: [bookRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(libraryBooksProvider.future);
      await container
          .read(libraryBooksProvider.notifier)
          .updateReadingPosition(
            bookId: book.id,
            chapterIndex: 7,
            progress: .42,
            locator: 'pdf:v2|8|',
          );

      final cached = container.read(libraryBooksProvider).value!.single;
      expect(cached.chapterIndex, 7);
      expect(cached.progress, closeTo(.42, .0001));
      expect(cached.locator, 'pdf:v2|8|');
      expect(cached.updatedAt, isNotNull);

      final persisted = await repository.findById(book.id);
      expect(persisted?.chapterIndex, 7);
      expect(persisted?.progress, closeTo(.42, .0001));
      expect(persisted?.locator, 'pdf:v2|8|');
    },
  );
}
