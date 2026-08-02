import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/content_embedding_repository.dart';
import 'package:tomoread/data/repositories/embedding_provider_repository.dart';
import 'package:tomoread/data/services/ai_secret_store.dart';
import 'package:tomoread/data/services/embedding_provider_service.dart';
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
    await chunks.replaceForBook(
      bookId: 'book-a',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
      chunks: [
        _chunk(0, 'first text'),
        _chunk(1, 'second text'),
      ],
    );
  });

  tearDown(() => database.close());

  test('resumes incrementally without embedding unchanged chunks', () async {
    final provider = _FakeEmbeddingService();
    final profile = await _readyProfile(profiles);
    final service = SemanticIndexService(
      chunks: chunks,
      embeddings: embeddings,
      provider: provider,
      secrets: AiSecretStore(),
    );

    final first = await service.indexBook(bookId: 'book-a', profile: profile);
    final second = await service.indexBook(bookId: 'book-a', profile: profile);

    expect(first.status, SemanticIndexStatus.ready);
    expect(second.indexedChunks, 2);
    expect(provider.inputCount, 2);
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

Future<EmbeddingProviderProfile> _readyProfile(
  EmbeddingProviderRepository repository,
) async {
  final profile = await repository.save(
    name: 'Local',
    presetId: 'ollama',
    mode: EmbeddingProviderMode.localService,
    authType: EmbeddingProviderAuthType.none,
    baseUrl: 'http://localhost:11434/v1',
    modelId: 'qwen3-embedding:0.6b',
    modelVersion: 'v1',
    secretKeyId: 'unused',
    distanceMetric: EmbeddingDistanceMetric.cosine,
    remoteContentConsent: false,
  );
  return repository.recordProbe(
    profile.id,
    EmbeddingProbeResult(
      profileId: profile.id,
      statusCode: 200,
      latencyMillis: 1,
      models: const ['qwen3-embedding:0.6b'],
      dimensions: 3,
      capabilityStatus: EmbeddingCapabilityStatus.ready,
    ),
  );
}

class _FakeEmbeddingService extends OpenAiCompatibleEmbeddingService {
  int inputCount = 0;

  @override
  Future<List<List<double>>> embed({
    required EmbeddingProviderProfile profile,
    required String apiKey,
    required List<String> inputs,
    EmbeddingCancellationToken? cancellationToken,
    bool capabilityProbe = false,
    bool validateConfiguredDimensions = true,
  }) async {
    inputCount += inputs.length;
    return inputs
        .map((text) => [text.length.toDouble(), 1.0, 0.0])
        .toList(growable: false);
  }
}
