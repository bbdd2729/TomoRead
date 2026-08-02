import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/ai_provider_repository.dart';
import '../../data/repositories/visual_artifact_repository.dart';
import '../../data/services/ai_secret_store.dart';
import '../../data/services/mind_map_generation_service.dart';
import '../../data/services/visual_artifact_export_service.dart';
import '../../data/services/word_frequency_service.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/visual_artifact.dart';

final visualizationControllerProvider = Provider.autoDispose
    .family<VisualizationController, String>((ref, _) {
      final controller = VisualizationController(
        wordFrequency: ref.watch(wordFrequencyServiceProvider),
        mindMaps: ref.watch(mindMapGenerationServiceProvider),
        artifacts: ref.watch(visualArtifactRepositoryProvider),
        providers: ref.watch(aiProviderRepositoryProvider),
        secrets: ref.watch(aiSecretStoreProvider),
        exporter: ref.watch(visualArtifactExportServiceProvider),
        onChanged: () {
          if (ref.mounted) {
            ref.read(visualArtifactRevisionProvider.notifier).bump();
          }
        },
      );
      ref.onDispose(() => unawaited(controller.cancel()));
      return controller;
    });

class VisualizationException implements Exception {
  const VisualizationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VisualizationController {
  VisualizationController({
    required this.wordFrequency,
    required this.mindMaps,
    required this.artifacts,
    required this.providers,
    required this.secrets,
    required this.exporter,
    required this.onChanged,
  });

  final WordFrequencyService wordFrequency;
  final MindMapGenerationService mindMaps;
  final VisualArtifactRepository artifacts;
  final AiProviderRepository providers;
  final AiSecretStore secrets;
  final VisualArtifactExportService exporter;
  final void Function() onChanged;

  Future<WordCloudGeneration> generateWordCloud({
    required String bookId,
    required String bookTitle,
    required VisualArtifactScope scope,
    required int currentChapterIndex,
  }) async {
    final result = await wordFrequency.generate(
      bookId: bookId,
      bookTitle: bookTitle,
      scope: scope,
      currentChapterIndex: currentChapterIndex,
      layoutSeed: _newSeed(),
    );
    onChanged();
    return result;
  }

  Future<MindMapGeneration> generateMindMap({
    required String bookId,
    required String bookTitle,
    required VisualArtifactScope scope,
    required int currentChapterIndex,
  }) async {
    final profile = await providers.loadActive();
    if (profile == null) {
      throw const VisualizationException('请先在 AI 设置中启用并激活一个服务商配置。');
    }
    final apiKey = profile.authType == AiProviderAuthType.none
        ? ''
        : (await secrets.read(profile.secretKeyId)) ?? '';
    if (profile.authType != AiProviderAuthType.none && apiKey.trim().isEmpty) {
      throw const VisualizationException('当前 AI 服务商缺少安全存储中的 API Key。');
    }
    final result = await mindMaps.generate(
      bookId: bookId,
      bookTitle: bookTitle,
      scope: scope,
      currentChapterIndex: currentChapterIndex,
      profile: profile,
      apiKey: apiKey,
    );
    onChanged();
    return result;
  }

  Future<VisualArtifact> reseedWordCloud(VisualArtifact artifact) async {
    if (artifact.kind != VisualArtifactKind.wordCloud) {
      throw const VisualizationException('只有词云可以重新排布。');
    }
    final payload = WordCloudPayload.fromJson(
      jsonDecode(artifact.payloadJson) as Map<String, Object?>,
    ).copyWith(layoutSeed: _newSeed());
    final saved = await artifacts.save(
      bookId: artifact.bookId,
      kind: artifact.kind,
      scope: artifact.scope,
      title: artifact.title,
      contentHash: artifact.contentHash,
      payload: payload.toJson(),
    );
    onChanged();
    return saved;
  }

  Future<void> delete(VisualArtifact artifact) async {
    await artifacts.delete(artifact.id);
    onChanged();
  }

  Future<String?> export(
    VisualArtifact artifact,
    VisualArtifactExportFormat format,
  ) => exporter.saveWithPicker(artifact, format);

  Future<void> cancel() async {
    mindMaps.cancel();
    await wordFrequency.cancel();
  }

  int _newSeed() => Random.secure().nextInt(0x7fffffff);
}
