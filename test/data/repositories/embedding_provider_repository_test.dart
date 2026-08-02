import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/embedding_provider_repository.dart';
import 'package:tomoread/domain/models/embedding_models.dart';

void main() {
  late AppDatabase database;
  late EmbeddingProviderRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = EmbeddingProviderRepository(database);
  });

  tearDown(() => database.close());

  test('keeps embedding profiles separate from chat providers', () async {
    final profile = await repository.save(
      name: 'Local embeddings',
      presetId: 'ollama',
      mode: EmbeddingProviderMode.localService,
      authType: EmbeddingProviderAuthType.none,
      baseUrl: 'http://localhost:11434/v1',
      modelId: 'qwen3-embedding:0.6b',
      modelVersion: 'ollama-managed',
      secretKeyId: 'unused',
      distanceMetric: EmbeddingDistanceMetric.cosine,
      remoteContentConsent: false,
    );

    expect((await repository.loadActive())?.id, profile.id);
    final raw = await database.database;
    expect(await raw.query('ai_provider_profiles'), isEmpty);
    expect(await raw.query('embedding_provider_profiles'), hasLength(1));
  });

  test('rejects a remote URL for a local service profile', () async {
    expect(
      () => repository.save(
        name: 'Unsafe local profile',
        mode: EmbeddingProviderMode.localService,
        authType: EmbeddingProviderAuthType.none,
        baseUrl: 'https://example.com/v1',
        modelId: 'model',
        modelVersion: 'v1',
        secretKeyId: 'unused',
        distanceMetric: EmbeddingDistanceMetric.cosine,
        remoteContentConsent: false,
      ),
      throwsFormatException,
    );
  });
}
