import 'chat_models.dart';

class AiCapabilities {
  const AiCapabilities({
    required this.streaming,
    required this.tools,
    required this.reasoningSummary,
    required this.usage,
  });

  final bool streaming;
  final bool tools;
  final bool reasoningSummary;
  final bool usage;
}

class AiRequestedToolCall {
  const AiRequestedToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
}

class AiProviderMessage {
  const AiProviderMessage({
    required this.role,
    this.content,
    this.reasoningContent,
    this.toolCalls = const [],
    this.toolCallId,
  });

  final String role;
  final String? content;
  final String? reasoningContent;
  final List<AiRequestedToolCall> toolCalls;
  final String? toolCallId;
}

class AiToolDeclaration {
  const AiToolDeclaration({
    required this.name,
    required this.displayName,
    required this.description,
    required this.kind,
    required this.inputSchema,
    this.skillId,
  });

  final String name;
  final String displayName;
  final String description;
  final AiToolKind kind;
  final Map<String, Object?> inputSchema;
  final String? skillId;
}

class AiToolExecutionResult {
  const AiToolExecutionResult({
    required this.output,
    this.citations = const [],
  });

  final String output;
  final List<AiCitationSource> citations;
}

class AiCitationSource {
  const AiCitationSource({
    required this.bookId,
    required this.href,
    required this.locator,
    required this.quote,
    this.chapterIndex,
    this.chapterTitle,
  });

  final String bookId;
  final String href;
  final String locator;
  final String quote;
  final int? chapterIndex;
  final String? chapterTitle;
}

sealed class AiStreamEvent {
  const AiStreamEvent();
}

class AiRunStartedEvent extends AiStreamEvent {
  const AiRunStartedEvent({required this.runId, required this.modelId});

  final String runId;
  final String modelId;
}

class AiTextDeltaEvent extends AiStreamEvent {
  const AiTextDeltaEvent(this.delta);

  final String delta;
}

class AiReasoningDeltaEvent extends AiStreamEvent {
  const AiReasoningDeltaEvent(this.delta);

  final String delta;
}

class AiToolCallStartedEvent extends AiStreamEvent {
  const AiToolCallStartedEvent({
    required this.callId,
    required this.name,
    required this.displayName,
    required this.kind,
    this.skillId,
  });

  final String callId;
  final String name;
  final String displayName;
  final AiToolKind kind;
  final String? skillId;
}

class AiToolArgumentsDeltaEvent extends AiStreamEvent {
  const AiToolArgumentsDeltaEvent({required this.callId, required this.delta});

  final String callId;
  final String delta;
}

class AiToolCallReadyEvent extends AiStreamEvent {
  const AiToolCallReadyEvent(this.call);

  final AiRequestedToolCall call;
}

class AiToolExecutionStartedEvent extends AiStreamEvent {
  const AiToolExecutionStartedEvent(this.callId);

  final String callId;
}

class AiToolExecutionCompletedEvent extends AiStreamEvent {
  const AiToolExecutionCompletedEvent({
    required this.callId,
    required this.output,
    required this.durationMillis,
  });

  final String callId;
  final String output;
  final int durationMillis;
}

class AiToolExecutionFailedEvent extends AiStreamEvent {
  const AiToolExecutionFailedEvent({
    required this.callId,
    required this.message,
    required this.durationMillis,
  });

  final String callId;
  final String message;
  final int durationMillis;
}

class AiCitationEvent extends AiStreamEvent {
  const AiCitationEvent({required this.ordinal, required this.source});

  final int ordinal;
  final AiCitationSource source;
}

class AiArtifactEvent extends AiStreamEvent {
  const AiArtifactEvent({
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

class AiUsageEvent extends AiStreamEvent {
  const AiUsageEvent(this.usage);

  final AiUsage usage;
}

class AiProviderCompletedEvent extends AiStreamEvent {
  const AiProviderCompletedEvent({this.stopReason});

  final String? stopReason;
}

class AiRunCompletedEvent extends AiStreamEvent {
  const AiRunCompletedEvent({this.stopReason});

  final String? stopReason;
}

class AiRunCancelledEvent extends AiStreamEvent {
  const AiRunCancelledEvent();
}
