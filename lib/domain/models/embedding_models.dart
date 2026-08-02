enum EmbeddingProviderProtocol { openAiCompatible }

enum EmbeddingProviderAuthType { bearer, apiKey, none }

enum EmbeddingProviderMode { localService, remote }

enum EmbeddingDistanceMetric { cosine, dotProduct, euclidean }

enum EmbeddingCapabilityStatus { untested, ready, unavailable, incompatible }

enum ContentEmbeddingStatus { ready, failed, stale }

enum SemanticIndexStatus { pending, indexing, ready, cancelled, failed, stale }

enum SemanticSearchMode { keywordOnly, hybrid }

enum HybridMatchSource { keyword, semantic }

class EmbeddingProviderProfile {
  const EmbeddingProviderProfile({
    required this.id,
    required this.name,
    required this.mode,
    required this.baseUrl,
    required this.modelId,
    required this.modelVersion,
    required this.secretKeyId,
    required this.distanceMetric,
    required this.maxInputCharacters,
    required this.batchSize,
    required this.isActive,
    required this.isEnabled,
    required this.remoteContentConsent,
    required this.capabilityStatus,
    required this.createdAt,
    required this.updatedAt,
    this.protocol = EmbeddingProviderProtocol.openAiCompatible,
    this.authType = EmbeddingProviderAuthType.bearer,
    this.presetId,
    this.dimensions,
    this.capabilityErrorCode,
  });

  final String id;
  final String name;
  final EmbeddingProviderProtocol protocol;
  final String? presetId;
  final EmbeddingProviderMode mode;
  final EmbeddingProviderAuthType authType;
  final String baseUrl;
  final String modelId;
  final String modelVersion;
  final String secretKeyId;
  final EmbeddingDistanceMetric distanceMetric;
  final int? dimensions;
  final int maxInputCharacters;
  final int batchSize;
  final bool isActive;
  final bool isEnabled;
  final bool remoteContentConsent;
  final EmbeddingCapabilityStatus capabilityStatus;
  final String? capabilityErrorCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get modelIdentity => '$modelId@$modelVersion';

  bool get canSendContent =>
      mode == EmbeddingProviderMode.localService || remoteContentConsent;
}

class EmbeddingProviderPreset {
  const EmbeddingProviderPreset({
    required this.id,
    required this.displayName,
    required this.mode,
    required this.baseUrl,
    required this.authType,
    required this.documentationUrl,
    this.defaultModelId = '',
    this.recommendedModels = const [],
    this.supportsModelList = true,
  });

  final String id;
  final String displayName;
  final EmbeddingProviderMode mode;
  final String baseUrl;
  final EmbeddingProviderAuthType authType;
  final String documentationUrl;
  final String defaultModelId;
  final List<EmbeddingModelRecommendation> recommendedModels;
  final bool supportsModelList;
}

class EmbeddingModelRecommendation {
  const EmbeddingModelRecommendation({
    required this.modelId,
    required this.displayName,
    required this.languages,
    required this.license,
    required this.sourceUrl,
  });

  final String modelId;
  final String displayName;
  final String languages;
  final String license;
  final String sourceUrl;
}

class EmbeddingProbeResult {
  const EmbeddingProbeResult({
    required this.profileId,
    required this.latencyMillis,
    required this.models,
    required this.capabilityStatus,
    this.statusCode,
    this.dimensions,
    this.errorCode,
  });

  final String profileId;
  final int? statusCode;
  final int latencyMillis;
  final List<String> models;
  final EmbeddingCapabilityStatus capabilityStatus;
  final int? dimensions;
  final String? errorCode;

  bool get succeeded => capabilityStatus == EmbeddingCapabilityStatus.ready;
}

class ContentEmbedding {
  const ContentEmbedding({
    required this.chunkId,
    required this.profileId,
    required this.modelId,
    required this.modelVersion,
    required this.dimensions,
    required this.distanceMetric,
    required this.contentHash,
    required this.textHash,
    required this.vector,
    required this.status,
    required this.generatedAt,
    required this.updatedAt,
    this.errorCode,
  });

  final String chunkId;
  final String profileId;
  final String modelId;
  final String modelVersion;
  final int dimensions;
  final EmbeddingDistanceMetric distanceMetric;
  final String contentHash;
  final String textHash;
  final List<double> vector;
  final ContentEmbeddingStatus status;
  final String? errorCode;
  final DateTime generatedAt;
  final DateTime updatedAt;
}

class SemanticIndexState {
  const SemanticIndexState({
    required this.bookId,
    required this.profileId,
    required this.contentHash,
    required this.modelId,
    required this.modelVersion,
    required this.indexVersion,
    required this.status,
    required this.totalChunks,
    required this.indexedChunks,
    required this.failedChunks,
    required this.updatedAt,
    this.dimensions,
    this.errorCode,
  });

  final String bookId;
  final String profileId;
  final String contentHash;
  final String modelId;
  final String modelVersion;
  final int? dimensions;
  final int indexVersion;
  final SemanticIndexStatus status;
  final int totalChunks;
  final int indexedChunks;
  final int failedChunks;
  final String? errorCode;
  final DateTime updatedAt;

  double get progress => totalChunks == 0
      ? status == SemanticIndexStatus.ready
            ? 1
            : 0
      : (indexedChunks / totalChunks).clamp(0, 1).toDouble();
}

class HybridSearchResult {
  const HybridSearchResult({
    required this.chunkId,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.href,
    required this.locator,
    required this.rawStart,
    required this.excerpt,
    required this.score,
    required this.sources,
    this.keywordScore,
    this.semanticScore,
  });

  final String chunkId;
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final String href;
  final String locator;
  final int rawStart;
  final String excerpt;
  final double score;
  final double? keywordScore;
  final double? semanticScore;
  final Set<HybridMatchSource> sources;
}

class HybridSearchResponse {
  const HybridSearchResponse({
    required this.results,
    required this.mode,
    required this.spoilerLimited,
    this.semanticStatusCode,
  });

  final List<HybridSearchResult> results;
  final SemanticSearchMode mode;
  final bool spoilerLimited;
  final String? semanticStatusCode;
}
