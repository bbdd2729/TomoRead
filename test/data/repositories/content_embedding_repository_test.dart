import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/content_embedding_repository.dart';
import 'package:tomoread/data/repositories/embedding_provider_repository.dart';
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
      'chapter_count': 1,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
  });

  tearDown(() => database.close());

  test('stores vectors as typed blobs and invalidates them with content', () async {
    final chunk = ContentChunk(
      id: 'chunk-a',
      bookId: 'book-a',
      chapterId: 'chapter-a',
      chapterIndex: 0,
      chapterTitle: 'Chapter',
      href: 'text:chapter-a',
      locatorStart: 'text:v1|0|0|0',
      locatorEnd: 'text:v1|0|4|4',
      rawStart: 0,
      rawEnd: 4,
      ordinal: 0,
      text: 'text',
      textHash: 'text-hash',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
    );
    await chunks.replaceForBook(
      bookId: 'book-a',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
      chunks: [chunk],
    );
    var profile = await profiles.save(
      name: 'OpenAI',
      presetId: 'openai',
      mode: EmbeddingProviderMode.remote,
      authType: EmbeddingProviderAuthType.bearer,
      baseUrl: 'https://api.openai.com/v1',
      modelId: 'text-embedding-3-small',
      modelVersion: 'v1',
      secretKeyId: 'secret',
      distanceMetric: EmbeddingDistanceMetric.cosine,
      dimensions: 3,
      remoteContentConsent: true,
    );
    await embeddings.saveBatch(
      profile: profile,
      chunks: [chunk],
      vectors: const [
        [0.25, -0.5, 1],
      ],
    );

    var candidates = await embeddings.listCandidates(
      bookId: 'book-a',
      profile: profile,
      contentHash: 'book-hash',
    );
    expect(candidates.single.vector, [0.25, -0.5, 1]);

    profile = await profiles.save(
      id: profile.id,
      name: profile.name,
      presetId: profile.presetId,
      mode: profile.mode,
      authType: profile.authType,
      baseUrl: profile.baseUrl,
      modelId: 'text-embedding-3-large',
      modelVersion: 'v2',
      secretKeyId: profile.secretKeyId,
      distanceMetric: profile.distanceMetric,
      dimensions: 3,
      remoteContentConsent: true,
    );
    candidates = await embeddings.listCandidates(
      bookId: 'book-a',
      profile: profile,
      contentHash: 'book-hash',
    );
    expect(candidates, isEmpty);
  });
}
