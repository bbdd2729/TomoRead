import '../../domain/models/ai_agent_models.dart';
import '../../domain/models/chat_models.dart';

class MessagePartAccumulator {
  MessagePartAccumulator({required this.messageId});

  final String messageId;
  final List<ChatMessagePart> _parts = [];
  final List<ChatCitation> _citations = [];
  int? _activeTextIndex;
  int? _activeReasoningIndex;
  AiUsage? usage;
  String? stopReason;
  bool cancelled = false;

  List<ChatMessagePart> get parts => List.unmodifiable(_parts);
  List<ChatCitation> get citations => List.unmodifiable(_citations);
  String get content =>
      _parts.whereType<ChatTextPart>().map((part) => part.text).join();

  void apply(AiStreamEvent event) {
    final now = DateTime.now();
    switch (event) {
      case AiTextDeltaEvent():
        _completeReasoning(now);
        final active = _activeTextIndex;
        if (active == null) {
          _activeTextIndex = _parts.length;
          _parts.add(
            ChatTextPart(
              id: _partId('text'),
              messageId: messageId,
              ordinal: _parts.length,
              status: ChatPartStatus.running,
              createdAt: now,
              updatedAt: now,
              text: event.delta,
            ),
          );
        } else {
          final part = _parts[active] as ChatTextPart;
          _parts[active] = part.copyWith(
            text: part.text + event.delta,
            updatedAt: now,
          );
        }
      case AiReasoningDeltaEvent():
        _completeText(now);
        final active = _activeReasoningIndex;
        if (active == null) {
          _activeReasoningIndex = _parts.length;
          _parts.add(
            ChatReasoningPart(
              id: _partId('reasoning'),
              messageId: messageId,
              ordinal: _parts.length,
              status: ChatPartStatus.running,
              createdAt: now,
              updatedAt: now,
              text: event.delta,
            ),
          );
        } else {
          final part = _parts[active] as ChatReasoningPart;
          _parts[active] = part.copyWith(
            text: part.text + event.delta,
            updatedAt: now,
          );
        }
      case AiToolCallStartedEvent():
        _completeStreamingParts(now);
        if (_toolIndex(event.callId) != null) return;
        if (event.kind == AiToolKind.skill) {
          _parts.add(
            ChatSkillCallPart(
              id: _partId('skill'),
              messageId: messageId,
              ordinal: _parts.length,
              status: ChatPartStatus.pending,
              createdAt: now,
              updatedAt: now,
              callId: event.callId,
              skillId: event.skillId ?? event.name,
              skillName: event.displayName,
            ),
          );
        } else {
          _parts.add(
            ChatToolCallPart(
              id: _partId('tool'),
              messageId: messageId,
              ordinal: _parts.length,
              status: ChatPartStatus.pending,
              createdAt: now,
              updatedAt: now,
              callId: event.callId,
              toolName: event.name,
              displayName: event.displayName,
            ),
          );
        }
      case AiToolArgumentsDeltaEvent():
        final index = _toolIndex(event.callId);
        if (index == null) return;
        final part = _parts[index];
        _parts[index] = switch (part) {
          ChatToolCallPart() => part.copyWith(
            argumentsJson: part.argumentsJson + event.delta,
            updatedAt: now,
          ),
          ChatSkillCallPart() => part.copyWith(
            argumentsJson: part.argumentsJson + event.delta,
            updatedAt: now,
          ),
          _ => part,
        };
      case AiToolExecutionStartedEvent():
        _setToolStatus(event.callId, ChatPartStatus.running, now);
      case AiToolExecutionCompletedEvent():
        final index = _toolIndex(event.callId);
        if (index == null) return;
        final part = _parts[index];
        _parts[index] = switch (part) {
          ChatToolCallPart() => part.copyWith(
            status: ChatPartStatus.completed,
            result: event.output,
            durationMillis: event.durationMillis,
            updatedAt: now,
          ),
          ChatSkillCallPart() => part.copyWith(
            status: ChatPartStatus.completed,
            result: event.output,
            durationMillis: event.durationMillis,
            updatedAt: now,
          ),
          _ => part,
        };
      case AiToolExecutionFailedEvent():
        final index = _toolIndex(event.callId);
        if (index == null) return;
        final part = _parts[index];
        _parts[index] = switch (part) {
          ChatToolCallPart() => part.copyWith(
            status: ChatPartStatus.error,
            error: event.message,
            durationMillis: event.durationMillis,
            updatedAt: now,
          ),
          ChatSkillCallPart() => part.copyWith(
            status: ChatPartStatus.error,
            error: event.message,
            durationMillis: event.durationMillis,
            updatedAt: now,
          ),
          _ => part,
        };
      case AiCitationEvent():
        _completeStreamingParts(now);
        final citation = ChatCitation(
          id: 'citation-$messageId-${event.ordinal}',
          messageId: messageId,
          ordinal: event.ordinal,
          bookId: event.source.bookId,
          href: event.source.href,
          locator: event.source.locator,
          chapterIndex: event.source.chapterIndex,
          chapterTitle: event.source.chapterTitle,
          quote: event.source.quote,
        );
        if (_citations.any((item) => item.id == citation.id)) return;
        _citations.add(citation);
        _parts.add(
          ChatCitationPart(
            id: _partId('citation'),
            messageId: messageId,
            ordinal: _parts.length,
            status: ChatPartStatus.completed,
            createdAt: now,
            updatedAt: now,
            citation: citation,
          ),
        );
      case AiArtifactEvent():
        _completeStreamingParts(now);
        _parts.add(
          ChatArtifactPart(
            id: _partId('artifact'),
            messageId: messageId,
            ordinal: _parts.length,
            status: ChatPartStatus.completed,
            createdAt: now,
            updatedAt: now,
            artifactType: event.artifactType,
            title: event.title,
            payloadJson: event.payloadJson,
            artifactId: event.artifactId,
            bookId: event.bookId,
          ),
        );
      case AiUsageEvent():
        usage = (usage ?? const AiUsage()).merge(event.usage);
      case AiRunCompletedEvent():
        stopReason = event.stopReason;
        _completeStreamingParts(now);
      case AiRunCancelledEvent():
        cancelled = true;
        _completeStreamingParts(now);
        _parts.add(
          ChatAbortedPart(
            id: _partId('aborted'),
            messageId: messageId,
            ordinal: _parts.length,
            status: ChatPartStatus.completed,
            createdAt: now,
            updatedAt: now,
            reason: '已停止生成',
          ),
        );
      default:
        break;
    }
  }

  void addAttachmentCitation(ChatContextAttachment attachment) {
    if (!content.contains('[1]') ||
        _citations.any((item) => item.ordinal == 1)) {
      return;
    }
    final now = DateTime.now();
    final citation = ChatCitation(
      id: 'citation-$messageId-1',
      messageId: messageId,
      ordinal: 1,
      bookId: attachment.bookId,
      href: attachment.href,
      locator: attachment.locator,
      chapterIndex: attachment.chapterIndex,
      chapterTitle: attachment.chapterTitle,
      quote: attachment.quote,
    );
    _citations.insert(0, citation);
    _parts.add(
      ChatCitationPart(
        id: _partId('citation'),
        messageId: messageId,
        ordinal: _parts.length,
        status: ChatPartStatus.completed,
        createdAt: now,
        updatedAt: now,
        citation: citation,
      ),
    );
  }

  void fail(String message, String? code) {
    final now = DateTime.now();
    _completeStreamingParts(now);
    _parts.add(
      ChatNoticePart(
        id: _partId('notice'),
        messageId: messageId,
        ordinal: _parts.length,
        status: ChatPartStatus.error,
        createdAt: now,
        updatedAt: now,
        message: message,
        level: ChatNoticeLevel.error,
        code: code,
      ),
    );
  }

  void _setToolStatus(String callId, ChatPartStatus status, DateTime now) {
    final index = _toolIndex(callId);
    if (index == null) return;
    final part = _parts[index];
    _parts[index] = switch (part) {
      ChatToolCallPart() => part.copyWith(status: status, updatedAt: now),
      ChatSkillCallPart() => part.copyWith(status: status, updatedAt: now),
      _ => part,
    };
  }

  int? _toolIndex(String callId) {
    final index = _parts.indexWhere(
      (part) => switch (part) {
        ChatToolCallPart() => part.callId == callId,
        ChatSkillCallPart() => part.callId == callId,
        _ => false,
      },
    );
    return index < 0 ? null : index;
  }

  void _completeStreamingParts(DateTime now) {
    _completeText(now);
    _completeReasoning(now);
  }

  void _completeText(DateTime now) {
    final index = _activeTextIndex;
    if (index == null) return;
    final part = _parts[index] as ChatTextPart;
    _parts[index] = part.copyWith(
      status: ChatPartStatus.completed,
      updatedAt: now,
    );
    _activeTextIndex = null;
  }

  void _completeReasoning(DateTime now) {
    final index = _activeReasoningIndex;
    if (index == null) return;
    final part = _parts[index] as ChatReasoningPart;
    _parts[index] = part.copyWith(
      status: ChatPartStatus.completed,
      updatedAt: now,
    );
    _activeReasoningIndex = null;
  }

  String _partId(String type) =>
      '$type-$messageId-${_parts.length}-${DateTime.now().microsecondsSinceEpoch}';
}
