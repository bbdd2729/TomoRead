import '../../domain/models/embedding_models.dart';

class EmbeddingProviderCatalog {
  const EmbeddingProviderCatalog();

  static const presets = <EmbeddingProviderPreset>[
    EmbeddingProviderPreset(
      id: 'ollama',
      displayName: 'Ollama',
      mode: EmbeddingProviderMode.localService,
      baseUrl: 'http://localhost:11434/v1',
      authType: EmbeddingProviderAuthType.none,
      documentationUrl: 'https://docs.ollama.com/api/openai-compatibility',
      defaultModelId: 'qwen3-embedding:0.6b',
      recommendedModels: [
        EmbeddingModelRecommendation(
          modelId: 'qwen3-embedding:0.6b',
          displayName: 'Qwen3 Embedding 0.6B',
          languages: 'Chinese and multilingual',
          license: 'Apache-2.0; verify the downloaded model card',
          sourceUrl: 'https://ollama.com/library/qwen3-embedding',
        ),
        EmbeddingModelRecommendation(
          modelId: 'nomic-embed-text',
          displayName: 'Nomic Embed Text',
          languages: 'Multilingual',
          license: 'Apache-2.0; verify the downloaded model card',
          sourceUrl: 'https://ollama.com/library/nomic-embed-text',
        ),
      ],
    ),
    EmbeddingProviderPreset(
      id: 'lm-studio',
      displayName: 'LM Studio',
      mode: EmbeddingProviderMode.localService,
      baseUrl: 'http://localhost:1234/v1',
      authType: EmbeddingProviderAuthType.none,
      documentationUrl: 'https://lmstudio.ai/docs/developer/openai-compat',
    ),
    EmbeddingProviderPreset(
      id: 'openai',
      displayName: 'OpenAI',
      mode: EmbeddingProviderMode.remote,
      baseUrl: 'https://api.openai.com/v1',
      authType: EmbeddingProviderAuthType.bearer,
      documentationUrl: 'https://platform.openai.com/docs/api-reference/embeddings',
      defaultModelId: 'text-embedding-3-small',
    ),
    EmbeddingProviderPreset(
      id: 'deepseek',
      displayName: 'DeepSeek (capability must be verified)',
      mode: EmbeddingProviderMode.remote,
      baseUrl: 'https://api.deepseek.com',
      authType: EmbeddingProviderAuthType.bearer,
      documentationUrl: 'https://api-docs.deepseek.com',
    ),
    EmbeddingProviderPreset(
      id: 'dashscope',
      displayName: 'DashScope',
      mode: EmbeddingProviderMode.remote,
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      authType: EmbeddingProviderAuthType.bearer,
      documentationUrl:
          'https://help.aliyun.com/zh/model-studio/text-embedding-synchronous-api',
      defaultModelId: 'text-embedding-v4',
    ),
    EmbeddingProviderPreset(
      id: 'gemini-openai',
      displayName: 'Gemini OpenAI-compatible',
      mode: EmbeddingProviderMode.remote,
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      authType: EmbeddingProviderAuthType.bearer,
      documentationUrl: 'https://ai.google.dev/gemini-api/docs/embeddings',
      defaultModelId: 'gemini-embedding-001',
    ),
    EmbeddingProviderPreset(
      id: 'custom',
      displayName: 'Custom OpenAI-compatible endpoint',
      mode: EmbeddingProviderMode.remote,
      baseUrl: '',
      authType: EmbeddingProviderAuthType.bearer,
      documentationUrl: '',
      supportsModelList: false,
    ),
  ];

  EmbeddingProviderPreset byId(String? id) => presets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => presets.last,
  );
}
