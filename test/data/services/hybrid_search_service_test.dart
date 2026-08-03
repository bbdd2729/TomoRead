import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/content_embedding_repository.dart';
import 'package:tomoread/data/repositories/embedding_provider_repository.dart';
import 'package:tomoread/data/services/ai_secret_store.dart';
import 'package:tomoread/data/services/embedding_provider_service.dart';
import 'package:tomoread/data/services/hybrid_search_service.dart';
import 'package:tomoread/data/services/semantic_index_service.dart';
import 'package:tomoread/domain/models/content_chunk.dart';
import 'package:tomoread/domain/models/embedding_models.dart';

void main() {
  late AppDatabase database;
  late ContentChunkRepository chunks;
  late ContentEmbeddingRepository embeddings;
  late EmbeddingProviderRepository profiles;

  setUp(() async {
    database = AppDatabase.inMemory();
    chunks = ContentChunkRepository(database);
    embeddings = ContentEmbeddingRepository(database);
    profiles = EmbeddingProviderRepository(database);
    final raw = await database.database;
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'progress': 0.0,
      'chapter_index': 0,
      'chapter_count': 2,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
  });

  tearDown(() => database.close());

  test('keeps keyword search available without an embedding profile', () async {
    await chunks.replaceForBook(
      bookId: 'book-a',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
      chunks: [_chunk(0, 'visible keyword')],
    );
    final service = HybridSearchService(
      chunks: chunks,
      embeddings: embeddings,
      profiles: profiles,
      provider: _QueryEmbeddingService(),
      secrets: AiSecretStore(),
    );

    final response = await service.search(
      bookId: 'book-a',
      query: 'keyword',
      maxChapterIndex: 0,
    );

    expect(response.mode, SemanticSearchMode.keywordOnly);
    expect(response.results.single.locator, 'text:v1|0|0|0');
  });

  test('combines keyword and semantic matches within spoiler boundary', () async {
    final current = _chunk(0, 'visible keyword');
    final future = _chunk(1, 'future semantic idea');
    await chunks.replaceForBook(
      bookId: 'book-a',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
      chunks: [current, future],
    );
    final saved = await profiles.save(
      name: 'Local',
      presetId: 'ollama',
      mode: EmbeddingProviderMode.localService,
      authType: EmbeddingProviderAuthType.none,
      baseUrl: 'http://localhost:11434/v1',
      modelId: 'embedding-model',
      modelVersion: 'v1',
      secretKeyId: 'unused',
      distanceMetric: EmbeddingDistanceMetric.cosine,
      remoteContentConsent: false,
    );
    final profile = await profiles.recordProbe(
      saved.id,
      EmbeddingProbeResult(
        profileId: saved.id,
        statusCode: 200,
        latencyMillis: 1,
        models: const ['embedding-model'],
        dimensions: 2,
        capabilityStatus: EmbeddingCapabilityStatus.ready,
      ),
    );
    await embeddings.saveBatch(
      profile: profile,
      chunks: [current, future],
      vectors: const [
        [1, 0],
        [0, 1],
      ],
    );
    await embeddings.saveState(
      SemanticIndexState(
        bookId: 'book-a',
        profileId: profile.id,
        contentHash: 'book-hash',
        modelId: profile.modelId,
        modelVersion: profile.modelVersion,
        dimensions: 2,
        indexVersion: SemanticIndexService.indexVersion,
        status: SemanticIndexStatus.ready,
        totalChunks: 2,
        indexedChunks: 2,
        failedChunks: 0,
        updatedAt: DateTime(2026),
      ),
    );
    final service = HybridSearchService(
      chunks: chunks,
      embeddings: embeddings,
      profiles: profiles,
      provider: _QueryEmbeddingService(),
      secrets: AiSecretStore(),
    );

    final response = await service.search(
      bookId: 'book-a',
      query: 'keyword',
      maxChapterIndex: 0,
    );

    expect(response.mode, SemanticSearchMode.hybrid);
    expect(response.results, hasLength(1));
    expect(response.results.single.chapterIndex, 0);
    expect(
      response.results.single.sources,
      containsAll([HybridMatchSource.keyword, HybridMatchSource.semantic]),
    );
  });
}

ContentChunk _chunk(int chapterIndex, String text) => ContentChunk(
  id: 'chunk-$chapterIndex',
  bookId: 'book-a',
  chapterId: 'chapter-$chapterIndex',
  chapterIndex: chapterIndex,
  chapterTitle: 'Chapter $chapterIndex',
  href: 'text:chapter-$chapterIndex',
  locatorStart: 'text:v1|$chapterIndex|0|0',
  locatorEnd: 'text:v1|$chapterIndex|${text.length}|${text.length}',
  rawStart: 0,
  rawEnd: text.length,
  ordinal: chapterIndex,
  text: text,
  textHash: 'text-hash-$chapterIndex',
  contentHash: 'book-hash',
  parserVersion: 1,
  indexVersion: 1,
);

class _QueryEmbeddingService extends OpenAiCompatibleEmbeddingService {
  @override
  Future<List<List<double>>> embed({
    required EmbeddingProviderProfile profile,
    required String apiKey,
    required List<String> inputs,
    EmbeddingCancellationToken? cancellationToken,
    bool capabilityProbe = false,
    bool validateConfiguredDimensions = true,
  }) async => const [
    [1, 0],
  ];
}
