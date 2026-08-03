import 'dart:isolate';
import 'dart:math' as math;

import '../../domain/models/content_chunk.dart';
import '../../domain/models/embedding_models.dart';
import '../repositories/content_chunk_repository.dart';
import '../repositories/content_embedding_repository.dart';
import '../repositories/embedding_provider_repository.dart';
import 'ai_secret_store.dart';
import 'embedding_provider_service.dart';
import 'semantic_index_service.dart';

class HybridSearchService {
  const HybridSearchService({
    required this.chunks,
    required this.embeddings,
    required this.profiles,
    required this.provider,
    required this.secrets,
  });

  final ContentChunkRepository chunks;
  final ContentEmbeddingRepository embeddings;
  final EmbeddingProviderRepository profiles;
  final OpenAiCompatibleEmbeddingService provider;
  final AiSecretStore secrets;

  Future<HybridSearchResponse> search({
    required String bookId,
    required String query,
    required int? maxChapterIndex,
    int? maxRawOffset,
    int limit = 30,
  }) async {
    final normalized = query.trim();
    final spoilerLimited = maxChapterIndex != null;
    if (normalized.isEmpty) {
      return HybridSearchResponse(
        results: const [],
        mode: SemanticSearchMode.keywordOnly,
        spoilerLimited: spoilerLimited,
      );
    }
    final safeLimit = limit.clamp(1, 100).toInt();
    final keywordHits = await chunks.search(
      bookId: bookId,
      query: normalized,
      maxChapterIndex: maxChapterIndex,
      maxRawOffset: maxRawOffset,
      limit: safeLimit,
    );
    final keywordScores = <String, double>{};
    for (var index = 0; index < keywordHits.length; index++) {
      keywordScores[keywordHits[index].chunk.id] =
          1 - (index / math.max(1, keywordHits.length)) * .25;
    }
    final profile = await profiles.loadActive();
    if (profile == null ||
        !profile.isEnabled ||
        !profile.canSendContent ||
        profile.capabilityStatus != EmbeddingCapabilityStatus.ready ||
        profile.dimensions == null) {
      return _keywordOnly(
        keywordHits,
        keywordScores,
        spoilerLimited,
        profile == null ? 'embedding_disabled' : 'embedding_profile_not_ready',
      );
    }
    final indexState = await embeddings.loadState(
      bookId: bookId,
      profileId: profile.id,
    );
    if (indexState == null ||
        indexState.status != SemanticIndexStatus.ready ||
        indexState.modelId != profile.modelId ||
        indexState.modelVersion != profile.modelVersion ||
        indexState.dimensions != profile.dimensions ||
        indexState.indexVersion != SemanticIndexService.indexVersion) {
      return _keywordOnly(
        keywordHits,
        keywordScores,
        spoilerLimited,
        'semantic_index_not_ready',
      );
    }
    final apiKey = profile.authType == EmbeddingProviderAuthType.none
        ? ''
        : await secrets.readEmbedding(profile.secretKeyId) ?? '';
    if (profile.authType != EmbeddingProviderAuthType.none && apiKey.isEmpty) {
      return _keywordOnly(
        keywordHits,
        keywordScores,
        spoilerLimited,
        'missing_key',
      );
    }
    try {
      final queryVectors = await provider.embed(
        profile: profile,
        apiKey: apiKey,
        inputs: [normalized],
      );
      final candidates = await embeddings.listCandidates(
        bookId: bookId,
        profile: profile,
        contentHash: indexState.contentHash,
        maxChapterIndex: maxChapterIndex,
        maxRawOffset: maxRawOffset,
      );
      final semanticScores = await Isolate.run(
        () => _scoreCandidates(
          queryVectors.single,
          candidates,
          profile.distanceMetric,
        ),
      );
      final chunksById = <String, ContentChunk>{
        for (final hit in keywordHits) hit.chunk.id: hit.chunk,
        for (final candidate in candidates) candidate.chunk.id: candidate.chunk,
      };
      final excerptById = <String, String>{
        for (final hit in keywordHits) hit.chunk.id: hit.excerpt,
      };
      final ids = {...keywordScores.keys, ...semanticScores.keys};
      final results = ids.map((id) {
        final chunk = chunksById[id]!;
        final keywordScore = keywordScores[id];
        final semanticScore = semanticScores[id];
        final score = keywordScore != null && semanticScore != null
            ? keywordScore * .35 + semanticScore * .65
            : keywordScore ?? semanticScore ?? 0;
        return _result(
          chunk,
          excerptById[id] ?? _excerpt(chunk.text),
          score,
          keywordScore: keywordScore,
          semanticScore: semanticScore,
        );
      }).toList()
        ..sort((left, right) {
          final scoreOrder = right.score.compareTo(left.score);
          return scoreOrder != 0
              ? scoreOrder
              : left.chapterIndex.compareTo(right.chapterIndex);
        });
      return HybridSearchResponse(
        results: results.take(safeLimit).toList(growable: false),
        mode: SemanticSearchMode.hybrid,
        spoilerLimited: spoilerLimited,
      );
    } on Object catch (error) {
      final code = error is EmbeddingProviderException
          ? error.code
          : 'semantic_search_failed';
      return _keywordOnly(
        keywordHits,
        keywordScores,
        spoilerLimited,
        code,
      );
    }
  }

  HybridSearchResponse _keywordOnly(
    List<ContentSearchResult> hits,
    Map<String, double> scores,
    bool spoilerLimited,
    String statusCode,
  ) => HybridSearchResponse(
    results: hits
        .map(
          (hit) => _result(
            hit.chunk,
            hit.excerpt,
            scores[hit.chunk.id] ?? 1,
            keywordScore: scores[hit.chunk.id] ?? 1,
          ),
        )
        .toList(growable: false),
    mode: SemanticSearchMode.keywordOnly,
    spoilerLimited: spoilerLimited,
    semanticStatusCode: statusCode,
  );

  HybridSearchResult _result(
    ContentChunk chunk,
    String excerpt,
    double score, {
    double? keywordScore,
    double? semanticScore,
  }) => HybridSearchResult(
    chunkId: chunk.id,
    bookId: chunk.bookId,
    chapterIndex: chunk.chapterIndex,
    chapterTitle: chunk.chapterTitle,
    href: chunk.href,
    locator: chunk.locatorStart,
    rawStart: chunk.rawStart,
    textHash: chunk.textHash,
    excerpt: excerpt,
    score: score,
    keywordScore: keywordScore,
    semanticScore: semanticScore,
    sources: {
      if (keywordScore != null) HybridMatchSource.keyword,
      if (semanticScore != null) HybridMatchSource.semantic,
    },
  );

  String _excerpt(String text) {
    final end = text.length.clamp(0, 220).toInt();
    return '${text.substring(0, end)}${end < text.length ? '…' : ''}';
  }
}

Map<String, double> _scoreCandidates(
  List<double> query,
  List<SemanticEmbeddingCandidate> candidates,
  EmbeddingDistanceMetric metric,
) {
  final result = <String, double>{};
  for (final candidate in candidates) {
    if (candidate.vector.length != query.length) continue;
    final score = switch (metric) {
      EmbeddingDistanceMetric.cosine =>
        (_cosine(query, candidate.vector) + 1) / 2,
      EmbeddingDistanceMetric.dotProduct =>
        1 / (1 + math.exp(-_dot(query, candidate.vector).clamp(-60, 60))),
      EmbeddingDistanceMetric.euclidean =>
        1 / (1 + _euclidean(query, candidate.vector)),
    };
    result[candidate.chunk.id] = score.clamp(0, 1).toDouble();
  }
  return result;
}

double _dot(List<double> left, List<double> right) {
  var value = 0.0;
  for (var index = 0; index < left.length; index++) {
    value += left[index] * right[index];
  }
  return value;
}

double _cosine(List<double> left, List<double> right) {
  var leftNorm = 0.0;
  var rightNorm = 0.0;
  for (var index = 0; index < left.length; index++) {
    leftNorm += left[index] * left[index];
    rightNorm += right[index] * right[index];
  }
  if (leftNorm == 0 || rightNorm == 0) return 0;
  return _dot(left, right) / math.sqrt(leftNorm * rightNorm);
}

double _euclidean(List<double> left, List<double> right) {
  var squared = 0.0;
  for (var index = 0; index < left.length; index++) {
    final difference = left[index] - right[index];
    squared += difference * difference;
  }
  return math.sqrt(squared);
}
