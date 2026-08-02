import '../../domain/models/content_chunk.dart';
import '../../domain/models/embedding_models.dart';
import '../repositories/content_chunk_repository.dart';
import '../repositories/content_embedding_repository.dart';
import 'ai_secret_store.dart';
import 'embedding_provider_service.dart';

class SemanticIndexService {
  const SemanticIndexService({
    required this.chunks,
    required this.embeddings,
    required this.provider,
    required this.secrets,
  });

  static const indexVersion = 1;

  final ContentChunkRepository chunks;
  final ContentEmbeddingRepository embeddings;
  final OpenAiCompatibleEmbeddingService provider;
  final AiSecretStore secrets;

  Future<SemanticIndexState> indexBook({
    required String bookId,
    required EmbeddingProviderProfile profile,
    EmbeddingCancellationToken? cancellationToken,
    void Function(SemanticIndexState state)? onProgress,
  }) async {
    if (!profile.isEnabled ||
        profile.capabilityStatus != EmbeddingCapabilityStatus.ready ||
        profile.dimensions == null) {
      throw const EmbeddingProviderException(
        'profile_not_ready',
        'Test the embedding profile successfully before indexing.',
        recoverable: false,
      );
    }
    if (!profile.canSendContent) {
      throw const EmbeddingProviderException(
        'remote_consent_required',
        'Enable remote content sharing before indexing.',
        recoverable: false,
      );
    }
    final apiKey = profile.authType == EmbeddingProviderAuthType.none
        ? ''
        : await secrets.readEmbedding(profile.secretKeyId) ?? '';
    if (profile.authType != EmbeddingProviderAuthType.none && apiKey.isEmpty) {
      throw const EmbeddingProviderException(
        'missing_key',
        'The embedding API key is missing from secure storage.',
        recoverable: false,
      );
    }
    final allChunks = await chunks.listForBook(bookId);
    if (allChunks.isEmpty) {
      throw const EmbeddingProviderException(
        'content_index_empty',
        'Build the trusted local content index before semantic indexing.',
        recoverable: false,
      );
    }
    final contentHashes = allChunks.map((chunk) => chunk.contentHash).toSet();
    if (contentHashes.length != 1) {
      throw const EmbeddingProviderException(
        'content_index_inconsistent',
        'Trusted content chunks use inconsistent content hashes.',
        recoverable: false,
      );
    }
    final contentHash = contentHashes.single;
    await embeddings.invalidateMismatched(
      bookId: bookId,
      profile: profile,
      contentHash: contentHash,
    );
    final readyIds = await embeddings.readyChunkIds(
      bookId: bookId,
      profile: profile,
      contentHash: contentHash,
    );
    final pending = allChunks
        .where((chunk) => !readyIds.contains(chunk.id))
        .toList(growable: false);
    var indexed = readyIds.length;
    var state = _state(
      bookId: bookId,
      profile: profile,
      contentHash: contentHash,
      status: SemanticIndexStatus.indexing,
      totalChunks: allChunks.length,
      indexedChunks: indexed,
    );
    await embeddings.saveState(state);
    onProgress?.call(state);
    try {
      for (var offset = 0; offset < pending.length; offset += profile.batchSize) {
        cancellationToken?.throwIfCancelled();
        final end = (offset + profile.batchSize)
            .clamp(0, pending.length)
            .toInt();
        final batch = pending.sublist(offset, end);
        _validateInputLengths(batch, profile.maxInputCharacters);
        final vectors = await provider.embed(
          profile: profile,
          apiKey: apiKey,
          inputs: batch.map((chunk) => chunk.text).toList(growable: false),
          cancellationToken: cancellationToken,
        );
        await embeddings.saveBatch(
          profile: profile,
          chunks: batch,
          vectors: vectors,
        );
        indexed += batch.length;
        state = _state(
          bookId: bookId,
          profile: profile,
          contentHash: contentHash,
          status: SemanticIndexStatus.indexing,
          totalChunks: allChunks.length,
          indexedChunks: indexed,
        );
        await embeddings.saveState(state);
        onProgress?.call(state);
      }
      cancellationToken?.throwIfCancelled();
      state = _state(
        bookId: bookId,
        profile: profile,
        contentHash: contentHash,
        status: SemanticIndexStatus.ready,
        totalChunks: allChunks.length,
        indexedChunks: allChunks.length,
      );
      await embeddings.saveState(state);
      onProgress?.call(state);
      return state;
    } on EmbeddingProviderException catch (error) {
      final status = error.code == 'cancelled'
          ? SemanticIndexStatus.cancelled
          : SemanticIndexStatus.failed;
      state = _state(
        bookId: bookId,
        profile: profile,
        contentHash: contentHash,
        status: status,
        totalChunks: allChunks.length,
        indexedChunks: indexed,
        failedChunks: status == SemanticIndexStatus.failed ? 1 : 0,
        errorCode: error.code,
      );
      await embeddings.saveState(state);
      onProgress?.call(state);
      rethrow;
    } on Object {
      state = _state(
        bookId: bookId,
        profile: profile,
        contentHash: contentHash,
        status: SemanticIndexStatus.failed,
        totalChunks: allChunks.length,
        indexedChunks: indexed,
        failedChunks: 1,
        errorCode: 'index_failed',
      );
      await embeddings.saveState(state);
      onProgress?.call(state);
      rethrow;
    }
  }

  SemanticIndexState _state({
    required String bookId,
    required EmbeddingProviderProfile profile,
    required String contentHash,
    required SemanticIndexStatus status,
    required int totalChunks,
    required int indexedChunks,
    int failedChunks = 0,
    String? errorCode,
  }) => SemanticIndexState(
    bookId: bookId,
    profileId: profile.id,
    contentHash: contentHash,
    modelId: profile.modelId,
    modelVersion: profile.modelVersion,
    dimensions: profile.dimensions,
    indexVersion: indexVersion,
    status: status,
    totalChunks: totalChunks,
    indexedChunks: indexedChunks,
    failedChunks: failedChunks,
    errorCode: errorCode,
    updatedAt: DateTime.now(),
  );

  void _validateInputLengths(
    List<ContentChunk> batch,
    int maxInputCharacters,
  ) {
    if (batch.any(
      (chunk) =>
          chunk.text.isEmpty || chunk.text.length > maxInputCharacters,
    )) {
      throw const EmbeddingProviderException(
        'input_too_long',
        'A trusted content chunk exceeds the configured model input limit.',
        recoverable: false,
      );
    }
  }
}
