import 'dart:async';

import '../../data/services/ai_gateway.dart';
import '../../data/services/ai_tool_registry.dart';
import '../../domain/models/ai_agent_models.dart';
import '../../domain/models/chat_models.dart';

class AiAgentRunHandle {
  const AiAgentRunHandle({required this.events, required this.cancel});

  final Stream<AiStreamEvent> events;
  final void Function() cancel;
}

class AiAgentRunner {
  AiAgentRunner(this._gateway, this._tools);

  final AiGateway _gateway;
  final AiToolRegistry _tools;

  AiAgentRunHandle run({
    required String runId,
    required AiProviderProfile profile,
    required String apiKey,
    required List<ChatMessage> history,
    required String systemPrompt,
    required ChatThread thread,
    ChatContextAttachment? attachment,
    String? preferredSkillId,
  }) {
    final controller = StreamController<AiStreamEvent>();
    AiStreamHandle? providerHandle;
    var cancelled = false;

    Future<void> execute() async {
      try {
        controller.add(
          AiRunStartedEvent(runId: runId, modelId: profile.modelId),
        );
        final toolSet = profile.toolsEnabled || preferredSkillId != null
            ? await _tools.createToolSet(
                AiToolContext(bookId: thread.bookId, attachment: attachment),
              )
            : AiToolSet({});
        final conversation = _buildConversation(systemPrompt, history);
        var citationOrdinal = attachment == null ? 1 : 2;
        String? finalStopReason;

        if (preferredSkillId != null && !cancelled) {
          final declaration = toolSet.declarations
              .where((tool) => tool.skillId == preferredSkillId)
              .firstOrNull;
          if (declaration != null) {
            final callId = 'selected-skill-$runId';
            controller
              ..add(
                AiToolCallStartedEvent(
                  callId: callId,
                  name: declaration.name,
                  displayName: declaration.displayName,
                  kind: AiToolKind.skill,
                  skillId: preferredSkillId,
                ),
              )
              ..add(AiToolArgumentsDeltaEvent(callId: callId, delta: '{}'))
              ..add(AiToolExecutionStartedEvent(callId));
            final stopwatch = Stopwatch()..start();
            try {
              final result = await toolSet.execute(declaration.name, '{}');
              stopwatch.stop();
              controller.add(
                AiToolExecutionCompletedEvent(
                  callId: callId,
                  output: result.output,
                  durationMillis: stopwatch.elapsedMilliseconds,
                ),
              );
              conversation.add(
                AiProviderMessage(
                  role: 'system',
                  content:
                      '用户已显式选择“${declaration.displayName}”技能。本轮回答必须遵循以下技能结果，不必再次调用该技能：\n${result.output}',
                ),
              );
            } on Object catch (error) {
              stopwatch.stop();
              controller.add(
                AiToolExecutionFailedEvent(
                  callId: callId,
                  message: error.toString(),
                  durationMillis: stopwatch.elapsedMilliseconds,
                ),
              );
            }
          }
        }

        for (var iteration = 0; iteration < 6; iteration++) {
          if (cancelled) break;
          providerHandle = await _gateway.streamReply(
            profile: profile,
            apiKey: apiKey,
            messages: conversation,
            tools: toolSet.declarations,
          );
          final requestedTools = <AiRequestedToolCall>[];
          var responseText = '';
          var responseReasoning = '';
          String? responseStopReason;
          await for (final event in providerHandle!.events) {
            if (cancelled) break;
            switch (event) {
              case AiTextDeltaEvent():
                responseText += event.delta;
                controller.add(event);
              case AiReasoningDeltaEvent():
                responseReasoning += event.delta;
                controller.add(event);
              case AiToolCallStartedEvent() ||
                  AiToolArgumentsDeltaEvent() ||
                  AiArtifactEvent() ||
                  AiUsageEvent():
                controller.add(event);
              case AiToolCallReadyEvent():
                requestedTools.add(event.call);
              case AiProviderCompletedEvent():
                responseStopReason = event.stopReason;
              default:
                break;
            }
          }
          if (cancelled) break;
          finalStopReason = responseStopReason;
          if (requestedTools.isEmpty) {
            controller.add(AiRunCompletedEvent(stopReason: finalStopReason));
            await controller.close();
            return;
          }

          conversation.add(
            AiProviderMessage(
              role: 'assistant',
              content: responseText.isEmpty ? null : responseText,
              reasoningContent: responseReasoning.isEmpty
                  ? null
                  : responseReasoning,
              toolCalls: requestedTools,
            ),
          );
          for (final call in requestedTools) {
            if (cancelled) break;
            controller.add(AiToolExecutionStartedEvent(call.id));
            final stopwatch = Stopwatch()..start();
            String output;
            try {
              final result = await toolSet.execute(
                call.name,
                call.argumentsJson,
              );
              final sourceLines = <String>[];
              for (final source in result.citations) {
                final ordinal = citationOrdinal++;
                controller.add(
                  AiCitationEvent(ordinal: ordinal, source: source),
                );
                sourceLines.add(
                  '[$ordinal] ${source.chapterTitle ?? '书中原文'}：${source.quote}',
                );
              }
              output = sourceLines.isEmpty
                  ? result.output
                  : '${result.output}\n\n可引用来源：\n${sourceLines.join('\n')}';
              stopwatch.stop();
              controller.add(
                AiToolExecutionCompletedEvent(
                  callId: call.id,
                  output: output,
                  durationMillis: stopwatch.elapsedMilliseconds,
                ),
              );
            } on Object catch (error) {
              stopwatch.stop();
              output = '工具执行失败：$error';
              controller.add(
                AiToolExecutionFailedEvent(
                  callId: call.id,
                  message: error.toString(),
                  durationMillis: stopwatch.elapsedMilliseconds,
                ),
              );
            }
            conversation.add(
              AiProviderMessage(
                role: 'tool',
                content: _limitToolOutput(output),
                toolCallId: call.id,
              ),
            );
          }
        }
        if (cancelled) {
          controller.add(const AiRunCancelledEvent());
        } else {
          throw const AiGatewayException(
            'agent_iteration_limit',
            '工具调用次数过多，已停止本次运行。',
          );
        }
      } on Object catch (error, stackTrace) {
        if (!cancelled) controller.addError(error, stackTrace);
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }

    unawaited(execute());
    return AiAgentRunHandle(
      events: controller.stream,
      cancel: () {
        if (cancelled) return;
        cancelled = true;
        providerHandle?.cancel();
      },
    );
  }

  List<AiProviderMessage> _buildConversation(
    String systemPrompt,
    List<ChatMessage> history,
  ) {
    final messages = <AiProviderMessage>[
      AiProviderMessage(role: 'system', content: systemPrompt),
    ];
    var approximateCharacters = systemPrompt.length;
    final selected = <ChatMessage>[];
    for (final message in history.reversed) {
      if (message.status == ChatMessageStatus.failed ||
          message.status == ChatMessageStatus.streaming) {
        continue;
      }
      final cost =
          message.content.length +
          message.parts.fold<int>(
            0,
            (sum, part) =>
                sum +
                switch (part) {
                  ChatQuotePart() => part.quote.length,
                  ChatToolCallPart() =>
                    (part.result?.length ?? 0) + part.argumentsJson.length,
                  ChatSkillCallPart() =>
                    (part.result?.length ?? 0) + part.argumentsJson.length,
                  _ => 0,
                },
          );
      if (selected.isNotEmpty && approximateCharacters + cost > 48000) break;
      selected.add(message);
      approximateCharacters += cost;
    }
    for (final message in selected.reversed) {
      messages.addAll(_providerMessagesFor(message));
    }
    return messages;
  }

  List<AiProviderMessage> _providerMessagesFor(ChatMessage message) {
    if (message.role == ChatRole.user) {
      final quotes = message.parts.whereType<ChatQuotePart>().toList();
      final buffer = StringBuffer(message.content);
      for (var index = 0; index < quotes.length; index++) {
        final quote = quotes[index];
        buffer
          ..writeln()
          ..writeln()
          ..writeln('[引用 ${index + 1}]')
          ..writeln('书籍：${quote.bookTitle}')
          ..writeln('章节：${quote.chapterTitle ?? '未知章节'}')
          ..write(quote.quote);
      }
      return [AiProviderMessage(role: 'user', content: buffer.toString())];
    }
    if (message.role != ChatRole.assistant) return const [];
    final callParts = message.parts
        .where((part) => part is ChatToolCallPart || part is ChatSkillCallPart)
        .toList();
    if (callParts.isEmpty) {
      return message.content.isEmpty
          ? const []
          : [AiProviderMessage(role: 'assistant', content: message.content)];
    }
    final calls = callParts.map((part) {
      return switch (part) {
        ChatToolCallPart() => AiRequestedToolCall(
          id: part.callId,
          name: part.toolName,
          argumentsJson: part.argumentsJson,
        ),
        ChatSkillCallPart() => AiRequestedToolCall(
          id: part.callId,
          name: 'skill_${part.skillId.replaceAll('-', '_')}',
          argumentsJson: part.argumentsJson,
        ),
        _ => throw StateError('Unsupported tool part'),
      };
    }).toList();
    final reasoning = message.parts
        .whereType<ChatReasoningPart>()
        .map((part) => part.text)
        .join();
    final result = <AiProviderMessage>[
      AiProviderMessage(
        role: 'assistant',
        content: message.content.isEmpty ? null : message.content,
        reasoningContent: reasoning.isEmpty ? null : reasoning,
        toolCalls: calls,
      ),
    ];
    for (final part in callParts) {
      final (callId, output) = switch (part) {
        ChatToolCallPart() => (part.callId, part.result ?? part.error),
        ChatSkillCallPart() => (part.callId, part.result ?? part.error),
        _ => (null, null),
      };
      if (callId != null && output != null) {
        result.add(
          AiProviderMessage(
            role: 'tool',
            content: _limitToolOutput(output),
            toolCallId: callId,
          ),
        );
      }
    }
    return result;
  }

  String _limitToolOutput(String value) =>
      value.length <= 32768 ? value : '${value.substring(0, 32768)}\n[结果已截断]';
}
