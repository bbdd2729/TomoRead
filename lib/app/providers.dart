import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/bookmark_repository.dart';
import '../data/repositories/annotation_repository.dart';
import '../data/repositories/ai_provider_repository.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/content_chunk_repository.dart';
import '../data/repositories/content_embedding_repository.dart';
import '../data/repositories/embedding_provider_repository.dart';
import '../data/repositories/font_repository.dart';
import '../data/repositories/reading_session_repository.dart';
import '../data/repositories/pomodoro_repository.dart';
import '../data/repositories/reader_command_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/skill_repository.dart';
import '../data/repositories/text_coloring_repository.dart';
import '../data/repositories/text_content_repository.dart';
import '../data/repositories/text_projection_repository.dart';
import '../data/repositories/tts_repository.dart';
import '../data/repositories/visual_artifact_repository.dart';
import '../data/services/ai_gateway.dart';
import '../data/services/ai_provider_catalog.dart';
import '../data/services/ai_provider_probe_service.dart';
import '../data/services/ai_secret_store.dart';
import '../data/services/ai_tool_registry.dart';
import '../data/services/book_import_service.dart';
import '../data/services/book_import_scan_service.dart';
import '../data/services/book_storage_service.dart';
import '../data/services/chapter_parser_service.dart';
import '../data/services/content_chunk_service.dart';
import '../data/services/epub_content_service.dart';
import '../data/services/epub_extraction_service.dart';
import '../data/services/epub_reader_session_service.dart';
import '../data/services/epub_section_progress_service.dart';
import '../data/services/embedding_provider_catalog.dart';
import '../data/services/embedding_provider_probe_service.dart';
import '../data/services/embedding_provider_service.dart';
import '../data/services/hybrid_search_service.dart';
import '../data/services/backup_service.dart';
import '../data/services/installation_identity_service.dart';
import '../data/services/restore_service.dart';
import '../data/services/storage_diagnostics_service.dart';
import '../data/services/font_catalog_service.dart';
import '../data/services/reading_activity_tracker.dart';
import '../data/services/reading_context_assembler.dart';
import '../data/services/semantic_index_service.dart';
import '../data/services/reader_shortcut_service.dart';
import '../data/services/pomodoro_timer_service.dart';
import '../data/services/platform_tts_engine.dart';
import '../data/services/platform_tts_wake_lock.dart';
import '../data/services/stats_report_service.dart';
import '../data/services/text_coloring_layout_service.dart';
import '../data/services/text_decoder_service.dart';
import '../data/services/text_display_transform_service.dart';
import '../data/services/tts_queue_service.dart';
import '../data/services/mind_map_generation_service.dart';
import '../data/services/visual_artifact_export_service.dart';
import '../data/services/word_frequency_service.dart';
import '../domain/models/bookmark.dart';
import '../domain/models/content_chunk.dart';
import '../domain/models/embedding_models.dart';
import '../domain/models/epub_manifest.dart';
import '../domain/models/epub_section_progress.dart';
import '../domain/models/library_book.dart';
import '../domain/models/reader_chapter.dart';
import '../domain/models/text_chapter.dart';
import '../domain/models/text_content_profile.dart';
import '../domain/models/reading_settings.dart';
import '../domain/models/reading_font.dart';
import '../domain/models/reading_annotation.dart';
import '../domain/models/tts.dart';
import '../domain/models/visual_artifact.dart';
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

final readerCommandRepositoryProvider = Provider<ReaderCommandRepository>(
  (ref) => ReaderCommandRepository(ref.watch(appDatabaseProvider)),
);

final readerShortcutServiceProvider = Provider<ReaderShortcutService>(
  (ref) => const ReaderShortcutService(),
);

final textContentRepositoryProvider = Provider<TextContentRepository>(
  (ref) => TextContentRepository(ref.watch(appDatabaseProvider)),
);

final textProjectionRepositoryProvider = Provider<TextProjectionRepository>(
  (ref) => TextProjectionRepository(ref.watch(appDatabaseProvider)),
);

final textDisplayTransformServiceProvider = Provider<TextDisplayTransformService>(
  (ref) => const TextDisplayTransformService(),
);

final textColoringLayoutServiceProvider = Provider<TextColoringLayoutService>(
  (ref) => const TextColoringLayoutService(),
);

final textProjectionRevisionProvider = NotifierProvider<RevisionNotifier, int>(
  RevisionNotifier.new,
);

final contentChunkRepositoryProvider = Provider<ContentChunkRepository>(
  (ref) => ContentChunkRepository(ref.watch(appDatabaseProvider)),
);

final embeddingProviderRepositoryProvider =
    Provider<EmbeddingProviderRepository>(
      (ref) => EmbeddingProviderRepository(ref.watch(appDatabaseProvider)),
    );

final contentEmbeddingRepositoryProvider =
    Provider<ContentEmbeddingRepository>(
      (ref) => ContentEmbeddingRepository(ref.watch(appDatabaseProvider)),
    );

final ttsRepositoryProvider = Provider<TtsRepository>(
  (ref) => TtsRepository(ref.watch(appDatabaseProvider)),
);

final ttsQueueServiceProvider = Provider<TtsQueueService>(
  (ref) => TtsQueueService(ref.watch(contentChunkRepositoryProvider)),
);

final ttsEngineProvider = Provider<TtsEngine>((ref) {
  final engine = PlatformTtsEngine();
  ref.onDispose(() => unawaited(engine.stop()));
  return engine;
});

final ttsWakeLockProvider = Provider<TtsWakeLock>(
  (ref) => const PlatformTtsWakeLock(),
);

final contentChunkServiceProvider = Provider<ContentChunkService>(
  (ref) => ContentChunkService(
    repository: ref.watch(contentChunkRepositoryProvider),
    epubContent: ref.watch(epubContentServiceProvider),
  ),
);

final contentIndexRevisionProvider = NotifierProvider<RevisionNotifier, int>(
  RevisionNotifier.new,
);

final semanticIndexRevisionProvider = NotifierProvider<RevisionNotifier, int>(
  RevisionNotifier.new,
);

final contentIndexStateProvider = FutureProvider.autoDispose
    .family<ContentIndexState?, String>((ref, bookId) {
      ref.watch(contentIndexRevisionProvider);
      return ref.watch(contentChunkRepositoryProvider).loadState(bookId);
    });

final contentCharacterCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, bookId) {
      ref.watch(contentIndexRevisionProvider);
      return ref
          .watch(contentChunkRepositoryProvider)
          .characterCountForBook(bookId);
    });

typedef ContentSearchRequest = ({
  String bookId,
  String query,
  int? maxChapterIndex,
  int limit,
});

final installationIdentityServiceProvider = Provider<InstallationIdentityService>(
  (ref) => InstallationIdentityService(),
);

final installationIdProvider = FutureProvider<String>(
  (ref) => ref.watch(installationIdentityServiceProvider).getOrCreate(),
);

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final installationId = await ref.watch(installationIdProvider.future);
  return BackupService(
    database: ref.watch(appDatabaseProvider),
    appVersion: '1.0.0+1',
    deviceId: installationId,
  );
});

final restoreServiceProvider = FutureProvider<RestoreService>((ref) async {
  return RestoreService(
    database: ref.watch(appDatabaseProvider),
    backupService: await ref.watch(backupServiceProvider.future),
  );
});

final storageDiagnosticsServiceProvider = Provider<StorageDiagnosticsService>(
  (ref) => StorageDiagnosticsService(database: ref.watch(appDatabaseProvider)),
);

final contentSearchProvider = FutureProvider.autoDispose
    .family<List<ContentSearchResult>, ContentSearchRequest>((ref, request) {
      ref.watch(contentIndexRevisionProvider);
      return ref.watch(contentChunkRepositoryProvider).search(
        bookId: request.bookId,
        query: request.query,
        maxChapterIndex: request.maxChapterIndex,
        limit: request.limit,
      );
    });

typedef SemanticIndexRequest = ({String bookId, String profileId});

final semanticIndexStateProvider = FutureProvider.autoDispose
    .family<SemanticIndexState?, SemanticIndexRequest>((ref, request) {
      ref.watch(semanticIndexRevisionProvider);
      return ref.watch(contentEmbeddingRepositoryProvider).loadState(
        bookId: request.bookId,
        profileId: request.profileId,
      );
    });

typedef HybridSearchRequest = ({
  String bookId,
  String query,
  int? maxChapterIndex,
  int limit,
});

final hybridSearchProvider = FutureProvider.autoDispose
    .family<HybridSearchResponse, HybridSearchRequest>((ref, request) {
      ref.watch(contentIndexRevisionProvider);
      ref.watch(semanticIndexRevisionProvider);
      return ref.watch(hybridSearchServiceProvider).search(
        bookId: request.bookId,
        query: request.query,
        maxChapterIndex: request.maxChapterIndex,
        limit: request.limit,
      );
    });

final visualArtifactRepositoryProvider = Provider<VisualArtifactRepository>(
  (ref) => VisualArtifactRepository(ref.watch(appDatabaseProvider)),
);

final visualArtifactRevisionProvider = NotifierProvider<RevisionNotifier, int>(
  RevisionNotifier.new,
);

final visualArtifactsForBookProvider = FutureProvider.autoDispose
    .family<List<VisualArtifact>, String>((ref, bookId) {
      ref.watch(visualArtifactRevisionProvider);
      return ref.watch(visualArtifactRepositoryProvider).listForBook(bookId);
    });

final wordFrequencyServiceProvider = Provider<WordFrequencyService>(
  (ref) => WordFrequencyService(
    chunks: ref.watch(contentChunkRepositoryProvider),
    artifacts: ref.watch(visualArtifactRepositoryProvider),
  ),
);

final mindMapGenerationServiceProvider = Provider<MindMapGenerationService>(
  (ref) => MindMapGenerationService(
    chunks: ref.watch(contentChunkRepositoryProvider),
    artifacts: ref.watch(visualArtifactRepositoryProvider),
    gateway: ref.watch(aiGatewayProvider),
  ),
);

final visualArtifactExportServiceProvider =
    Provider<VisualArtifactExportService>(
      (ref) => const VisualArtifactExportService(),
    );

final fontRepositoryProvider = Provider<FontRepository>(
  (ref) => FontRepository(ref.watch(appDatabaseProvider)),
);

final fontCatalogServiceProvider = Provider<FontCatalogService>(
  (ref) => const PlatformFontCatalogService(),
);

final readingFontReadyProvider = FutureProvider.autoDispose
    .family<void, ReadingFontRef>((ref, font) async {
      await ref.watch(fontRepositoryProvider).ensureLoaded(font);
    });

final epubFontFaceCssProvider = FutureProvider.autoDispose
    .family<String?, ReadingFontRef>(
      (ref, font) => ref.watch(fontRepositoryProvider).epubFontFaceCss(font),
    );

final readingSessionRepositoryProvider = Provider<ReadingSessionRepository>(
  (ref) => ReadingSessionRepository(ref.watch(appDatabaseProvider)),
);

final pomodoroRepositoryProvider = Provider<PomodoroRepository>(
  (ref) => PomodoroRepository(ref.watch(appDatabaseProvider)),
);

final pomodoroTimerServiceProvider = Provider<PomodoroTimerService>(
  (ref) => const PomodoroTimerService(),
);

final aiSecretStoreProvider = Provider<AiSecretStore>((ref) => AiSecretStore());

final aiGatewayProvider = Provider<AiGateway>(
  (ref) => const OpenAiCompatibleGateway(),
);

final aiProviderCatalogProvider = Provider<AiProviderCatalog>(
  (ref) => const AiProviderCatalog(),
);

final aiProviderProbeServiceProvider = Provider<AiProviderProbeService>(
  (ref) => const AiProviderProbeService(),
);

final embeddingProviderCatalogProvider = Provider<EmbeddingProviderCatalog>(
  (ref) => const EmbeddingProviderCatalog(),
);

final embeddingProviderServiceProvider =
    Provider<OpenAiCompatibleEmbeddingService>(
      (ref) => const OpenAiCompatibleEmbeddingService(),
    );

final embeddingProviderProbeServiceProvider =
    Provider<EmbeddingProviderProbeService>(
      (ref) => EmbeddingProviderProbeService(
        ref.watch(embeddingProviderServiceProvider),
      ),
    );

final semanticIndexServiceProvider = Provider<SemanticIndexService>(
  (ref) => SemanticIndexService(
    chunks: ref.watch(contentChunkRepositoryProvider),
    embeddings: ref.watch(contentEmbeddingRepositoryProvider),
    provider: ref.watch(embeddingProviderServiceProvider),
    secrets: ref.watch(aiSecretStoreProvider),
  ),
);

final hybridSearchServiceProvider = Provider<HybridSearchService>(
  (ref) => HybridSearchService(
    chunks: ref.watch(contentChunkRepositoryProvider),
    embeddings: ref.watch(contentEmbeddingRepositoryProvider),
    profiles: ref.watch(embeddingProviderRepositoryProvider),
    provider: ref.watch(embeddingProviderServiceProvider),
    secrets: ref.watch(aiSecretStoreProvider),
  ),
);

final aiToolRegistryProvider = Provider<AiToolRegistry>(
  (ref) => AiToolRegistry(
    ref.watch(bookRepositoryProvider),
    ref.watch(annotationRepositoryProvider),
    ref.watch(skillRepositoryProvider),
    ref.watch(contentChunkRepositoryProvider),
  ),
);

final readingContextAssemblerProvider = Provider<ReadingContextAssembler>(
  (ref) => ReadingContextAssembler(
    chunks: ref.watch(contentChunkRepositoryProvider),
    annotations: ref.watch(annotationRepositoryProvider),
    hybridSearch: ref.watch(hybridSearchServiceProvider),
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
  (ref) => BookImportService(
    repository: ref.watch(bookRepositoryProvider),
    textDecoder: ref.watch(textDecoderServiceProvider),
    chapterParser: ref.watch(chapterParserServiceProvider),
    textContentRepository: ref.watch(textContentRepositoryProvider),
    contentChunkService: ref.watch(contentChunkServiceProvider),
    scanService: ref.watch(bookImportScanServiceProvider),
  ),
);

final bookImportScanServiceProvider = Provider<BookImportScanService>(
  (ref) => const BookImportScanService(),
);

final textDecoderServiceProvider = Provider<TextDecoderService>(
  (ref) => const TextDecoderService(),
);

final chapterParserServiceProvider = Provider<ChapterParserService>(
  (ref) => const ChapterParserService(),
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

  Future<BookImportResult> importTextWithEncoding(
    String sourcePath,
    String encoding,
  ) async {
    final result = await ref
        .read(bookImportServiceProvider)
        .importTextFile(sourcePath, encodingOverride: encoding);
    if (result.status == BookImportStatus.imported) {
      state = AsyncData(await ref.read(bookRepositoryProvider).listBooks());
    }
    return result;
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

final textContentProfileProvider = FutureProvider.autoDispose
    .family<TextContentProfile?, String>(
      (ref, bookId) =>
          ref.watch(textContentRepositoryProvider).loadProfile(bookId),
    );

final textChaptersProvider = FutureProvider.autoDispose
    .family<List<TextChapter>, String>(
      (ref, bookId) =>
          ref.watch(textContentRepositoryProvider).listChapters(bookId),
    );

final textBookDocumentProvider = FutureProvider.autoDispose
    .family<TextBookDocument, String>((ref, bookId) async {
      final results = await Future.wait<Object?>([
        ref.watch(readerBookProvider(bookId).future),
        ref.watch(textContentProfileProvider(bookId).future),
        ref.watch(textChaptersProvider(bookId).future),
      ]);
      final book = results[0] as LibraryBook?;
      final profile = results[1] as TextContentProfile?;
      final chapters = results[2]! as List<TextChapter>;
      if (book == null || profile == null) {
        throw const TextDecodeException('文本书籍或编码配置不存在。');
      }
      final decoded = await ref
          .read(textDecoderServiceProvider)
          .decodeFile(book.filePath, encodingOverride: profile.encoding);
      return TextBookDocument(
        book: book,
        profile: profile,
        chapters: chapters,
        rawText: decoded.text,
      );
    });

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
