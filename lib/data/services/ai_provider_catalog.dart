import '../../domain/models/ai_provider_preset.dart';
import '../../domain/models/chat_models.dart';

class AiProviderCatalog {
  const AiProviderCatalog();

  static const presets = <AiProviderPreset>[
    AiProviderPreset(
      id: 'ollama',
      displayName: 'Ollama',
      baseUrl: 'http://localhost:11434/v1',
      authType: AiProviderAuthType.none,
      allowLocalHttp: true,
      documentationUrl: 'https://docs.ollama.com/api/openai-compatibility',
    ),
    AiProviderPreset(
      id: 'lm-studio',
      displayName: 'LM Studio',
      baseUrl: 'http://localhost:1234/v1',
      authType: AiProviderAuthType.none,
      allowLocalHttp: true,
      documentationUrl: 'https://lmstudio.ai/docs/developer/openai-compat',
    ),
    AiProviderPreset(
      id: 'openai',
      displayName: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      authType: AiProviderAuthType.bearer,
      toolsByDefault: true,
      documentationUrl: 'https://platform.openai.com/docs/api-reference',
    ),
    AiProviderPreset(
      id: 'deepseek',
      displayName: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      authType: AiProviderAuthType.bearer,
      documentationUrl: 'https://api-docs.deepseek.com',
    ),
    AiProviderPreset(
      id: 'dashscope',
      displayName: 'DashScope（通义）',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      authType: AiProviderAuthType.bearer,
      documentationUrl: 'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope',
    ),
    AiProviderPreset(
      id: 'zhipu-glm',
      displayName: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      authType: AiProviderAuthType.bearer,
      documentationUrl: 'https://docs.bigmodel.cn/cn/guide/develop/openai/introduction',
    ),
    AiProviderPreset(
      id: 'moonshot',
      displayName: 'Moonshot',
      baseUrl: 'https://api.moonshot.cn/v1',
      authType: AiProviderAuthType.bearer,
      documentationUrl: 'https://platform.moonshot.cn/docs/api/chat',
    ),
    AiProviderPreset(
      id: 'siliconflow',
      displayName: 'SiliconFlow',
      baseUrl: 'https://api.siliconflow.cn/v1',
      authType: AiProviderAuthType.bearer,
      documentationUrl: 'https://docs.siliconflow.cn/cn/api-reference/chat-completions/chat-completions',
    ),
    AiProviderPreset(
      id: 'minimax',
      displayName: 'MiniMax',
      baseUrl: 'https://api.minimax.chat/v1',
      authType: AiProviderAuthType.bearer,
      documentationUrl: 'https://platform.minimaxi.com/document/ChatCompletion%20v2',
    ),
    AiProviderPreset(
      id: 'openrouter',
      displayName: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      authType: AiProviderAuthType.bearer,
      toolsByDefault: true,
      documentationUrl: 'https://openrouter.ai/docs/api/reference/overview',
    ),
    AiProviderPreset(
      id: 'gemini-openai',
      displayName: 'Gemini（OpenAI 兼容）',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      authType: AiProviderAuthType.bearer,
      documentationUrl: 'https://ai.google.dev/gemini-api/docs/openai',
    ),
    AiProviderPreset(
      id: 'custom',
      displayName: '自定义 OpenAI 兼容服务',
      baseUrl: '',
      authType: AiProviderAuthType.bearer,
      supportsModelList: false,
      documentationUrl: '',
    ),
  ];

  AiProviderPreset byId(String? id) => presets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => presets.last,
  );
}
