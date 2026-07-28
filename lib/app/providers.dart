import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/bookmark_repository.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/book_import_service.dart';
import '../domain/models/bookmark.dart';
import '../domain/models/library_book.dart';
import '../domain/models/reading_settings.dart';
import 'appearance.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

final bookmarkRepositoryProvider = Provider<BookmarkRepository>(
  (ref) => BookmarkRepository(ref.watch(appDatabaseProvider)),
);

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(ref.watch(appDatabaseProvider)),
);

final bookImportServiceProvider = Provider<BookImportService>(
  (ref) => BookImportService(repository: ref.watch(bookRepositoryProvider)),
);

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, StoredSettings>(
      AppSettingsNotifier.new,
    );

class AppSettingsNotifier extends AsyncNotifier<StoredSettings> {
  @override
  Future<StoredSettings> build() =>
      ref.watch(settingsRepositoryProvider).load();

  Future<void> updateAppearance(AppAppearance appearance) async {
    final current =
        state.value ??
        const StoredSettings(
          appearance: AppAppearance(),
          readingSettings: ReadingSettings(),
        );
    state = AsyncData(
      StoredSettings(
        appearance: appearance,
        readingSettings: current.readingSettings,
      ),
    );
    await ref.read(settingsRepositoryProvider).saveAppearance(appearance);
  }

  Future<void> updateReadingSettings(ReadingSettings readingSettings) async {
    final current =
        state.value ??
        const StoredSettings(
          appearance: AppAppearance(),
          readingSettings: ReadingSettings(),
        );
    state = AsyncData(
      StoredSettings(
        appearance: current.appearance,
        readingSettings: readingSettings,
      ),
    );
    await ref
        .read(settingsRepositoryProvider)
        .saveReadingSettings(readingSettings);
  }
}

final libraryBooksProvider =
    AsyncNotifierProvider<LibraryBooksNotifier, List<LibraryBook>>(
      LibraryBooksNotifier.new,
    );

class LibraryBooksNotifier extends AsyncNotifier<List<LibraryBook>> {
  @override
  Future<List<LibraryBook>> build() =>
      ref.watch(bookRepositoryProvider).listBooks();

  Future<List<BookImportResult>> importFromPicker() async {
    final results = await ref
        .read(bookImportServiceProvider)
        .pickAndImportEpubs();
    if (results.any((result) => result.status == BookImportStatus.imported)) {
      state = AsyncData(await ref.read(bookRepositoryProvider).listBooks());
    }
    return results;
  }
}

final bookReadingOverrideProvider = FutureProvider.autoDispose
    .family<BookReadingOverride?, String>(
      (ref, bookId) =>
          ref.watch(settingsRepositoryProvider).loadBookOverride(bookId),
    );

final bookmarksForBookProvider = FutureProvider.autoDispose
    .family<List<Bookmark>, String>(
      (ref, bookId) =>
          ref.watch(bookmarkRepositoryProvider).listForBook(bookId),
    );
