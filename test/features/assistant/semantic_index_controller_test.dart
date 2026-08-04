import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/content_embedding_repository.dart';
import 'package:tomoread/data/repositories/embedding_provider_repository.dart';
import 'package:tomoread/data/services/ai_secret_store.dart';
import 'package:tomoread/data/services/embedding_provider_service.dart';
import 'package:tomoread/data/services/semantic_index_service.dart';
import 'package:tomoread/features/assistant/semantic_index_controller.dart';

void main() {
  late AppDatabase database;
  late SemanticIndexController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    controller = SemanticIndexController(
      service: SemanticIndexService(
        chunks: ContentChunkRepository(database),
        embeddings: ContentEmbeddingRepository(database),
        provider: const OpenAiCompatibleEmbeddingService(),
        secrets: AiSecretStore(),
      ),
      profiles: EmbeddingProviderRepository(database),
      embeddings: ContentEmbeddingRepository(database),
      onChanged: () {},
    );
    addTearDown(database.close);
  });

  test('indexBook requires an active embedding profile', () async {
    await expectLater(
      controller.indexBook('book-a'),
      throwsA(
        isA<EmbeddingProviderException>().having(
          (error) => error.code,
          'code',
          'profile_missing',
        ),
      ),
    );
    expect(controller.isRunning('book-a'), isFalse);
  });

  test('rebuildBook without a profile throws and stays idle', () async {
    await expectLater(
      controller.rebuildBook('book-a'),
      throwsA(
        isA<EmbeddingProviderException>().having(
          (error) => error.code,
          'code',
          'profile_missing',
        ),
      ),
    );
    expect(controller.isRunning('book-a'), isFalse);
  });

  test('deleteIndex without a profile is a no-op', () async {
    await controller.deleteIndex('book-a');
    expect(controller.isRunning('book-a'), isFalse);
  });
}
