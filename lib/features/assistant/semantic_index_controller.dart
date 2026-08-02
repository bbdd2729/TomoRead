import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/content_embedding_repository.dart';
import '../../data/repositories/embedding_provider_repository.dart';
import '../../data/services/embedding_provider_service.dart';
import '../../data/services/semantic_index_service.dart';

final semanticIndexControllerProvider = Provider<SemanticIndexController>(
  (ref) => SemanticIndexController(
    service: ref.watch(semanticIndexServiceProvider),
    profiles: ref.watch(embeddingProviderRepositoryProvider),
    embeddings: ref.watch(contentEmbeddingRepositoryProvider),
    onChanged: () => ref.read(semanticIndexRevisionProvider.notifier).bump(),
  ),
);

class SemanticIndexController {
  SemanticIndexController({
    required this.service,
    required this.profiles,
    required this.embeddings,
    required this.onChanged,
  });

  final SemanticIndexService service;
  final EmbeddingProviderRepository profiles;
  final ContentEmbeddingRepository embeddings;
  final void Function() onChanged;
  final Map<String, EmbeddingCancellationToken> _running = {};

  bool isRunning(String bookId) => _running.containsKey(bookId);

  Future<void> indexBook(String bookId) async {
    if (_running.containsKey(bookId)) return;
    final profile = await profiles.loadActive();
    if (profile == null) {
      throw const EmbeddingProviderException(
        'profile_missing',
        'Configure and activate an embedding profile first.',
        recoverable: false,
      );
    }
    final token = EmbeddingCancellationToken();
    _running[bookId] = token;
    onChanged();
    try {
      await service.indexBook(
        bookId: bookId,
        profile: profile,
        cancellationToken: token,
        onProgress: (_) => onChanged(),
      );
    } finally {
      _running.remove(bookId);
      onChanged();
    }
  }

  void cancel(String bookId) => _running[bookId]?.cancel();

  Future<void> deleteIndex(String bookId) async {
    final profile = await profiles.loadActive();
    if (profile == null) return;
    cancel(bookId);
    await embeddings.deleteForBook(
      bookId: bookId,
      profileId: profile.id,
    );
    onChanged();
  }
}
