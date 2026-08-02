enum ChatScope { general, book }

enum ChatRole { system, user, assistant }

enum ChatMessageStatus { complete, streaming, failed, cancelled }

enum AiProviderProtocol { openAiCompatible }

enum AiProviderAuthType { bearer, apiKey, none }

enum ChatPartStatus { pending, running, completed, error }

enum ChatNoticeLevel { info, warning, error }

enum AiToolKind { read, write, skill }

enum AiRunStatus {
  queued,
  streaming,
  waitingForTool,
  completed,
  failed,
  cancelled,
}

class AiUsage {
  const AiUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.cachedTokens = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int cachedTokens;

  int get totalTokens => inputTokens + outputTokens;

  AiUsage merge(AiUsage other) => AiUsage(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    reasoningTokens: reasoningTokens + other.reasoningTokens,
    cachedTokens: cachedTokens + other.cachedTokens,
  );
}

class AiProviderProfile {
  const AiProviderProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.modelId,
    required this.secretKeyId,
    required this.temperature,
    required this.maxOutputTokens,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.protocol = AiProviderProtocol.openAiCompatible,
    this.presetId,
    this.authType = AiProviderAuthType.bearer,
    this.capabilitiesJson = '{}',
    this.customHeadersSecretId,
    this.isEnabled = true,
    this.toolsEnabled = false,
    this.reasoningEnabled = true,
  });

  final String id;
  final String name;
  final AiProviderProtocol protocol;
  final String? presetId;
  final AiProviderAuthType authType;
  final String baseUrl;
  final String modelId;
  final String secretKeyId;
  final double temperature;
  final int maxOutputTokens;
  final bool isActive;
  final bool isEnabled;
  final bool toolsEnabled;
  final bool reasoningEnabled;
  final String capabilitiesJson;
  final String? customHeadersSecretId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ChatThread {
  const ChatThread({
    required this.id,
    required this.scope,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.bookId,
  });

  final String id;
  final ChatScope scope;
  final String? bookId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatThread copyWith({String? title, DateTime? updatedAt}) => ChatThread(
    id: id,
    scope: scope,
    bookId: bookId,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

sealed class ChatMessagePart {
  const ChatMessagePart({
    required this.id,
    required this.messageId,
    required this.ordinal,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String messageId;
  final int ordinal;
  final ChatPartStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ChatTextPart extends ChatMessagePart {
  const ChatTextPart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.text,
  });

  final String text;

  ChatTextPart copyWith({
    String? text,
    ChatPartStatus? status,
    DateTime? updatedAt,
  }) => ChatTextPart(
    id: id,
    messageId: messageId,
    ordinal: ordinal,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    text: text ?? this.text,
  );
}

class ChatReasoningPart extends ChatMessagePart {
  const ChatReasoningPart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.text,
    this.reasoningType = 'thinking',
  });

  final String text;
  final String reasoningType;

  ChatReasoningPart copyWith({
    String? text,
    ChatPartStatus? status,
    DateTime? updatedAt,
  }) => ChatReasoningPart(
    id: id,
    messageId: messageId,
    ordinal: ordinal,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    text: text ?? this.text,
    reasoningType: reasoningType,
  );
}

class ChatQuotePart extends ChatMessagePart {
  const ChatQuotePart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.bookId,
    required this.bookTitle,
    required this.href,
    required this.locator,
    required this.quote,
    this.chapterIndex,
    this.chapterTitle,
  });

  final String bookId;
  final String bookTitle;
  final String href;
  final String locator;
  final int? chapterIndex;
  final String? chapterTitle;
  final String quote;
}

class ChatToolCallPart extends ChatMessagePart {
  const ChatToolCallPart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.callId,
    required this.toolName,
    required this.displayName,
    this.argumentsJson = '',
    this.result,
    this.error,
    this.durationMillis,
  });

  final String callId;
  final String toolName;
  final String displayName;
  final String argumentsJson;
  final String? result;
  final String? error;
  final int? durationMillis;

  ChatToolCallPart copyWith({
    ChatPartStatus? status,
    String? argumentsJson,
    String? result,
    String? error,
    int? durationMillis,
    DateTime? updatedAt,
  }) => ChatToolCallPart(
    id: id,
    messageId: messageId,
    ordinal: ordinal,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    callId: callId,
    toolName: toolName,
    displayName: displayName,
    argumentsJson: argumentsJson ?? this.argumentsJson,
    result: result ?? this.result,
    error: error ?? this.error,
    durationMillis: durationMillis ?? this.durationMillis,
  );
}

class ChatSkillCallPart extends ChatMessagePart {
  const ChatSkillCallPart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.callId,
    required this.skillId,
    required this.skillName,
    this.argumentsJson = '',
    this.result,
    this.error,
    this.durationMillis,
  });

  final String callId;
  final String skillId;
  final String skillName;
  final String argumentsJson;
  final String? result;
  final String? error;
  final int? durationMillis;

  ChatSkillCallPart copyWith({
    ChatPartStatus? status,
    String? argumentsJson,
    String? result,
    String? error,
    int? durationMillis,
    DateTime? updatedAt,
  }) => ChatSkillCallPart(
    id: id,
    messageId: messageId,
    ordinal: ordinal,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    callId: callId,
    skillId: skillId,
    skillName: skillName,
    argumentsJson: argumentsJson ?? this.argumentsJson,
    result: result ?? this.result,
    error: error ?? this.error,
    durationMillis: durationMillis ?? this.durationMillis,
  );
}

class ChatCitationPart extends ChatMessagePart {
  const ChatCitationPart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.citation,
  });

  final ChatCitation citation;
}

class ChatArtifactPart extends ChatMessagePart {
  const ChatArtifactPart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.artifactType,
    required this.title,
    required this.payloadJson,
    this.artifactId,
    this.bookId,
  });

  final String artifactType;
  final String title;
  final String payloadJson;
  final String? artifactId;
  final String? bookId;
}

class ChatNoticePart extends ChatMessagePart {
  const ChatNoticePart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.message,
    required this.level,
    this.code,
  });

  final String message;
  final ChatNoticeLevel level;
  final String? code;
}

class ChatAbortedPart extends ChatMessagePart {
  const ChatAbortedPart({
    required super.id,
    required super.messageId,
    required super.ordinal,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.reason,
  });

  final String reason;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    required this.status,
    required this.createdAt,
    this.modelId,
    this.errorCode,
    this.completedAt,
    this.citations = const [],
    this.parts = const [],
    this.usage,
    this.stopReason,
  });

  final String id;
  final String threadId;
  final ChatRole role;
  final String content;
  final ChatMessageStatus status;
  final String? modelId;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime? completedAt;
  final List<ChatCitation> citations;
  final List<ChatMessagePart> parts;
  final AiUsage? usage;
  final String? stopReason;

  ChatMessage copyWith({
    String? content,
    ChatMessageStatus? status,
    String? errorCode,
    DateTime? completedAt,
    List<ChatCitation>? citations,
    List<ChatMessagePart>? parts,
    AiUsage? usage,
    String? stopReason,
  }) => ChatMessage(
    id: id,
    threadId: threadId,
    role: role,
    content: content ?? this.content,
    status: status ?? this.status,
    modelId: modelId,
    errorCode: errorCode ?? this.errorCode,
    createdAt: createdAt,
    completedAt: completedAt ?? this.completedAt,
    citations: citations ?? this.citations,
    parts: parts ?? this.parts,
    usage: usage ?? this.usage,
    stopReason: stopReason ?? this.stopReason,
  );
}

class ChatCitation {
  const ChatCitation({
    required this.id,
    required this.messageId,
    required this.ordinal,
    required this.bookId,
    required this.href,
    required this.locator,
    required this.quote,
    this.chapterIndex,
    this.chapterTitle,
  });

  final String id;
  final String messageId;
  final int ordinal;
  final String bookId;
  final String href;
  final String locator;
  final int? chapterIndex;
  final String? chapterTitle;
  final String quote;
}

class ChatContextAttachment {
  const ChatContextAttachment({
    required this.bookId,
    required this.bookTitle,
    required this.href,
    required this.locator,
    required this.quote,
    this.chapterIndex,
    this.chapterTitle,
  });

  final String bookId;
  final String bookTitle;
  final String href;
  final String locator;
  final int? chapterIndex;
  final String? chapterTitle;
  final String quote;
}

class AiSkillDefinition {
  const AiSkillDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.iconKey,
    required this.enabled,
    required this.builtIn,
    required this.version,
    required this.promptTemplate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String iconKey;
  final bool enabled;
  final bool builtIn;
  final int version;
  final String promptTemplate;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiSkillDefinition copyWith({
    String? name,
    String? description,
    String? iconKey,
    bool? enabled,
    String? promptTemplate,
    DateTime? updatedAt,
  }) => AiSkillDefinition(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    iconKey: iconKey ?? this.iconKey,
    enabled: enabled ?? this.enabled,
    builtIn: builtIn,
    version: version,
    promptTemplate: promptTemplate ?? this.promptTemplate,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
