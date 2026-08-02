import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/bookmark_repository.dart';
import '../data/repositories/annotation_repository.dart';
import '../data/repositories/ai_provider_repository.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/reading_session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/skill_repository.dart';
import '../data/repositories/text_coloring_repository.dart';
import '../data/services/ai_gateway.dart';
import '../data/services/ai_secret_store.dart';
import '../data/services/ai_tool_registry.dart';
import '../data/services/book_import_service.dart';
import '../data/services/book_storage_service.dart';
import '../data/services/epub_content_service.dart';
import '../data/services/epub_extraction_service.dart';
import '../data/services/epub_reader_session_service.dart';
import '../data/services/epub_section_progress_service.dart';
import '../data/services/reading_activity_tracker.dart';
import '../data/services/stats_report_service.dart';
import '../domain/models/bookmark.dart';
import '../domain/models/epub_manifest.dart';
import '../domain/models/epub_section_progress.dart';
import '../domain/models/library_book.dart';
import '../domain/models/reader_chapter.dart';
import '../domain/models/reading_settings.dart';
import '../domain/models/reading_annotation.dart';
import '../features/chat/ai_agent_runner.dart';
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

final annotationRepositoryProvider = Provider<AnnotationRepository>(
  (ref) => AnnotationRepository(ref.watch(appDatabaseProvider)),
);

final aiProviderRepositoryProvider = Provider<AiProviderRepository>(
  (ref) => AiProviderRepository(ref.watch(appDatabaseProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(appDatabaseProvider)),
);

final skillRepositoryProvider = Provider<SkillRepository>(
  (ref) => SkillRepository(ref.watch(appDatabaseProvider)),
);

final textColoringRepositoryProvider = Provider<TextColoringRepository>(
  (ref) => TextColoringRepository(ref.watch(appDatabaseProvider)),
);

final readingSessionRepositoryProvider = Provider<ReadingSessionRepository>(
  (ref) => ReadingSessionRepository(ref.watch(appDatabaseProvider)),
);

final aiSecretStoreProvider = Provider<AiSecretStore>((ref) => AiSecretStore());

final aiGatewayProvider = Provider<AiGateway>(
  (ref) => const OpenAiCompatibleGateway(),
);

final aiToolRegistryProvider = Provider<AiToolRegistry>(
  (ref) => AiToolRegistry(
    ref.watch(bookRepositoryProvider),
    ref.watch(annotationRepositoryProvider),
    ref.watch(skillRepositoryProvider),
    ref.watch(epubContentServiceProvider),
  ),
);

final aiAgentRunnerProvider = Provider<AiAgentRunner>(
  (ref) => AiAgentRunner(
    ref.watch(aiGatewayProvider),
    ref.watch(aiToolRegistryProvider),
  ),
);

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(ref.watch(appDatabaseProvider)),
);

final annotationRevisionProvider = NotifierProvider<RevisionNotifier, int>(
  RevisionNotifier.new,
);

final statisticsRevisionProvider =
    NotifierProvider<StatisticsRevisionNotifier, int>(
      StatisticsRevisionNotifier.new,
    );

class RevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state += 1;
}

class StatisticsRevisionNotifier extends RevisionNotifier {}

final readingActivityTrackerProvider = Provider<ReadingActivityTracker>((ref) {
  final tracker = ReadingActivityTracker(
    repository: ref.watch(readingSessionRepositoryProvider),
    onChanged: () {
      if (ref.mounted) {
        ref.read(statisticsRevisionProvider.notifier).bump();
      }
    },
  );
  ref.onDispose(() => unawaited(tracker.dispose()));
  return tracker;
});

final statsReportServiceProvider = Provider<StatsReportService>(
  (ref) => StatsReportService(
    sessions: ref.watch(readingSessionRepositoryProvider),
    books: ref.watch(bookRepositoryProvider),
  ),
);

final bookImportServiceProvider = Provider<BookImportService>(
  (ref) => BookImportService(repository: ref.watch(bookRepositoryProvider)),
);

final bookStorageServiceProvider = Provider<BookStorageService>(
  (ref) => BookStorageService(repository: ref.watch(bookRepositoryProvider)),
);

final epubContentServiceProvider = Provider<EpubContentService>(
  (ref) => const EpubContentService(),
);

final epubExtractionServiceProvider = Provider<EpubExtractionService>(
  (ref) => const EpubExtractionService(),
);

final epubSectionProgressServiceProvider = Provider<EpubSectionProgressService>(
  (ref) => const EpubSectionProgressService(),
);

final epubReaderSessionServiceProvider = Provider<EpubReaderSessionService>(
  (ref) => EpubReaderSessionService(
    extractionService: ref.watch(epubExtractionServiceProvider),
  ),
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
        .pickAndImportBooks();
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

final annotationsForBookProvider = FutureProvider.autoDispose
    .family<List<ReadingAnnotation>, String>((ref, bookId) {
      ref.watch(annotationRevisionProvider);
      return ref.watch(annotationRepositoryProvider).listForBook(bookId);
    });

final readerBookProvider = FutureProvider.autoDispose
    .family<LibraryBook?, String>(
      (ref, bookId) => ref.watch(bookRepositoryProvider).findById(bookId),
    );

final readerManifestProvider = FutureProvider.autoDispose
    .family<EpubManifest?, String>(
      (ref, bookId) => ref.watch(bookRepositoryProvider).loadManifest(bookId),
    );

final readerChapterProvider = FutureProvider.autoDispose
    .family<ReaderChapter, ({String bookId, int chapterIndex})>((
      ref,
      request,
    ) async {
      final book = await ref.watch(readerBookProvider(request.bookId).future);
      final manifest = await ref.watch(
        readerManifestProvider(request.bookId).future,
      );
      if (book == null || manifest == null) {
        throw const EpubContentException('书籍或阅读清单不存在');
      }
      return ref
          .read(epubContentServiceProvider)
          .loadChapter(
            book: book,
            manifest: manifest,
            chapterIndex: request.chapterIndex,
          );
    });

final epubExtractedDirectoryProvider = FutureProvider.autoDispose
    .family<String, String>((ref, bookId) async {
      final book = await ref.watch(readerBookProvider(bookId).future);
      if (book == null) {
        throw const EpubExtractionException('书籍不存在');
      }
      return ref.read(epubExtractionServiceProvider).ensureExtracted(book);
    });

final epubSectionProgressProvider = FutureProvider.autoDispose
    .family<EpubSectionProgress, String>((ref, bookId) async {
      final readerSession = await ref.watch(
        epubReaderSessionProvider(bookId).future,
      );
      final manifest = await ref.watch(readerManifestProvider(bookId).future);
      if (manifest == null) return EpubSectionProgress.even(0);
      return ref
          .read(epubSectionProgressServiceProvider)
          .load(
            extractedDirectory: readerSession.directoryPath,
            manifest: manifest,
          );
    });

final epubReaderSessionProvider = FutureProvider.autoDispose
    .family<EpubReaderSession, String>((ref, bookId) async {
      final book = await ref.watch(readerBookProvider(bookId).future);
      final manifest = await ref.watch(readerManifestProvider(bookId).future);
      if (book == null || manifest == null) {
        throw const EpubExtractionException(
          'Book or EPUB manifest does not exist.',
        );
      }
      return ref
          .read(epubReaderSessionServiceProvider)
          .prepare(book: book, manifest: manifest);
    });
