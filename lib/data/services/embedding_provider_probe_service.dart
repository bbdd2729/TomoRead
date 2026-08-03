import '../../domain/models/embedding_models.dart';
import 'embedding_provider_service.dart';

class EmbeddingProviderProbeService {
  const EmbeddingProviderProbeService(this._provider);

  final OpenAiCompatibleEmbeddingService _provider;

  Future<EmbeddingProbeResult> probe(
    EmbeddingProviderProfile profile, {
    required String apiKey,
  }) async {
    final stopwatch = Stopwatch()..start();
    final models = await _provider.listModels(profile: profile, apiKey: apiKey);
    try {
      final vectors = await _provider.embed(
        profile: profile,
        apiKey: apiKey,
        inputs: const ['TomoRead embedding capability probe.'],
        capabilityProbe: true,
        validateConfiguredDimensions: false,
      );
      final dimensions = vectors.single.length;
      if (profile.dimensions != null && profile.dimensions != dimensions) {
        return EmbeddingProbeResult(
          profileId: profile.id,
          statusCode: 200,
          latencyMillis: stopwatch.elapsedMilliseconds,
          models: models,
          dimensions: dimensions,
          capabilityStatus: EmbeddingCapabilityStatus.incompatible,
          errorCode: 'dimension_mismatch',
        );
      }
      return EmbeddingProbeResult(
        profileId: profile.id,
        statusCode: 200,
        latencyMillis: stopwatch.elapsedMilliseconds,
        models: models,
        dimensions: dimensions,
        capabilityStatus: EmbeddingCapabilityStatus.ready,
      );
    } on EmbeddingProviderException catch (error) {
      return EmbeddingProbeResult(
        profileId: profile.id,
        statusCode: error.statusCode,
        latencyMillis: stopwatch.elapsedMilliseconds,
        models: models,
        capabilityStatus: error.code == 'invalid_response'
            ? EmbeddingCapabilityStatus.incompatible
            : EmbeddingCapabilityStatus.unavailable,
        errorCode: error.code,
      );
    }
  }
}
