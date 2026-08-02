import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/ai_provider_catalog.dart';
import 'package:tomoread/domain/models/chat_models.dart';
import 'package:tomoread/data/services/embedding_provider_catalog.dart';
import 'package:tomoread/domain/models/embedding_models.dart';

void main() {
  test('ships the documented compatible provider preset catalog', () {
    final ids = AiProviderCatalog.presets.map((preset) => preset.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids,
      containsAll([
        'ollama',
        'lm-studio',
        'openai',
        'deepseek',
        'dashscope',
        'zhipu-glm',
        'moonshot',
        'siliconflow',
        'minimax',
        'openrouter',
        'gemini-openai',
        'custom',
      ]),
    );
    expect(
      const AiProviderCatalog().byId('ollama').authType,
      AiProviderAuthType.none,
    );
    for (final preset in AiProviderCatalog.presets.where(
      (item) => item.baseUrl.isNotEmpty,
    )) {
      expect(
        preset.baseUrl.startsWith('https://') || preset.allowLocalHttp,
        isTrue,
        reason: preset.id,
      );
    }
  });

  test('ships independent local and remote embedding presets', () {
    final ids = EmbeddingProviderCatalog.presets
        .map((preset) => preset.id)
        .toList();

    expect(
      ids,
      containsAll([
        'ollama',
        'lm-studio',
        'openai',
        'deepseek',
        'dashscope',
        'gemini-openai',
        'custom',
      ]),
    );
    expect(
      const EmbeddingProviderCatalog().byId('ollama').mode,
      EmbeddingProviderMode.localService,
    );
    expect(
      const EmbeddingProviderCatalog()
          .byId('ollama')
          .recommendedModels,
      isNotEmpty,
    );
  });
}
