import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/embedding_provider_service.dart';
import '../../domain/models/embedding_models.dart';

final embeddingSettingsControllerProvider = AsyncNotifierProvider<
  EmbeddingSettingsController,
  List<EmbeddingProviderProfile>
>(EmbeddingSettingsController.new);

class EmbeddingSettingsController
    extends AsyncNotifier<List<EmbeddingProviderProfile>> {
  @override
  Future<List<EmbeddingProviderProfile>> build() =>
      ref.watch(embeddingProviderRepositoryProvider).listProfiles();

  Future<EmbeddingProviderProfile> save({
    String? profileId,
    required String presetId,
    required String name,
    required EmbeddingProviderMode mode,
    required EmbeddingProviderAuthType authType,
    required String baseUrl,
    required String modelId,
    required String modelVersion,
    required String apiKey,
    required EmbeddingDistanceMetric distanceMetric,
    required bool remoteContentConsent,
    required int maxInputCharacters,
    required int batchSize,
  }) async {
    final repository = ref.read(embeddingProviderRepositoryProvider);
    final existing = profileId == null
        ? null
        : await repository.findById(profileId);
    final secretId =
        existing?.secretKeyId ??
        'embedding-secret-${DateTime.now().microsecondsSinceEpoch}';
    final normalizedKey = apiKey.trim();
    final previousSecret = normalizedKey.isNotEmpty && existing != null
        ? await ref.read(aiSecretStoreProvider).readEmbedding(secretId)
        : null;
    var wroteSecret = false;
    if (normalizedKey.isNotEmpty) {
      await ref.read(aiSecretStoreProvider).writeEmbedding(
        secretId,
        normalizedKey,
      );
      wroteSecret = true;
    } else if (existing == null &&
        authType != EmbeddingProviderAuthType.none) {
      throw const EmbeddingProviderException(
        'missing_key',
        'A new remote embedding profile requires an API key.',
        recoverable: false,
      );
    }
    try {
      final profile = await repository.save(
        id: existing?.id,
        presetId: presetId,
        name: name,
        mode: mode,
        authType: authType,
        baseUrl: baseUrl,
        modelId: modelId,
        modelVersion: modelVersion,
        secretKeyId: secretId,
        distanceMetric: distanceMetric,
        dimensions: existing?.dimensions,
        remoteContentConsent: remoteContentConsent,
        maxInputCharacters: maxInputCharacters,
        batchSize: batchSize,
      );
      await _refresh();
      return profile;
    } on Object {
      if (wroteSecret) {
        if (previousSecret == null) {
          await ref.read(aiSecretStoreProvider).deleteEmbedding(secretId);
        } else {
          await ref.read(aiSecretStoreProvider).writeEmbedding(
            secretId,
            previousSecret,
          );
        }
      }
      rethrow;
    }
  }

  Future<EmbeddingProbeResult> probe(String id) async {
    final repository = ref.read(embeddingProviderRepositoryProvider);
    final profile = await repository.findById(id);
    if (profile == null) {
      throw const EmbeddingProviderException(
        'profile_missing',
        'Embedding profile does not exist.',
        recoverable: false,
      );
    }
    final apiKey = profile.authType == EmbeddingProviderAuthType.none
        ? ''
        : await ref.read(aiSecretStoreProvider).readEmbedding(
                profile.secretKeyId,
              ) ??
              '';
    if (profile.authType != EmbeddingProviderAuthType.none && apiKey.isEmpty) {
      throw const EmbeddingProviderException(
        'missing_key',
        'The API key is missing from secure storage.',
        recoverable: false,
      );
    }
    final result = await ref
        .read(embeddingProviderProbeServiceProvider)
        .probe(profile, apiKey: apiKey);
    await repository.recordProbe(id, result);
    await _refresh();
    return result;
  }

  Future<void> activate(String id) async {
    await ref.read(embeddingProviderRepositoryProvider).activate(id);
    await _refresh();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await ref.read(embeddingProviderRepositoryProvider).setEnabled(id, enabled);
    await _refresh();
  }

  Future<void> delete(String id) async {
    final secretId = await ref.read(embeddingProviderRepositoryProvider).delete(id);
    if (secretId != null) {
      await ref.read(aiSecretStoreProvider).deleteEmbedding(secretId);
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    state = AsyncData(
      await ref.read(embeddingProviderRepositoryProvider).listProfiles(),
    );
    ref.read(semanticIndexRevisionProvider.notifier).bump();
  }
}
