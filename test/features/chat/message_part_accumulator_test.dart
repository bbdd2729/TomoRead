import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/ai_agent_models.dart';
import 'package:tomoread/domain/models/chat_models.dart';
import 'package:tomoread/features/chat/message_part_accumulator.dart';

void main() {
  test('preserves reasoning, tool, text, and citation order', () {
    final accumulator = MessagePartAccumulator(messageId: 'assistant-a');

    accumulator
      ..apply(const AiReasoningDeltaEvent('先查找原文。'))
      ..apply(
        const AiToolCallStartedEvent(
          callId: 'call-a',
          name: 'search_book_text',
          displayName: '搜索书中原文',
          kind: AiToolKind.read,
        ),
      )
      ..apply(
        const AiToolArgumentsDeltaEvent(
          callId: 'call-a',
          delta: '{"query":"概念"}',
        ),
      )
      ..apply(const AiToolExecutionStartedEvent('call-a'))
      ..apply(
        const AiToolExecutionCompletedEvent(
          callId: 'call-a',
          output: '找到一处',
          durationMillis: 12,
        ),
      )
      ..apply(
        const AiCitationEvent(
          ordinal: 1,
          source: AiCitationSource(
            bookId: 'book-a',
            href: 'chapter.xhtml',
            locator: 'ratio:0.2',
            quote: '原文片段',
            chapterIndex: 2,
          ),
        ),
      )
      ..apply(const AiTextDeltaEvent('这是回答 [1]。'))
      ..apply(const AiRunCompletedEvent(stopReason: 'stop'));

    expect(accumulator.parts.map((part) => part.runtimeType), [
      ChatReasoningPart,
      ChatToolCallPart,
      ChatCitationPart,
      ChatTextPart,
    ]);
    final tool = accumulator.parts.whereType<ChatToolCallPart>().single;
    expect(tool.status, ChatPartStatus.completed);
    expect(tool.argumentsJson, '{"query":"概念"}');
    expect(tool.result, '找到一处');
    expect(accumulator.content, '这是回答 [1]。');
    expect(accumulator.citations.single.locator, 'ratio:0.2');
    expect(accumulator.stopReason, 'stop');
  });

  test('uses call id when two tools have the same name', () {
    final accumulator = MessagePartAccumulator(messageId: 'assistant-b');
    for (final callId in const ['one', 'two']) {
      accumulator.apply(
        AiToolCallStartedEvent(
          callId: callId,
          name: 'get_annotations',
          displayName: '读取标注',
          kind: AiToolKind.read,
        ),
      );
    }
    accumulator
      ..apply(
        const AiToolExecutionCompletedEvent(
          callId: 'two',
          output: 'second',
          durationMillis: 1,
        ),
      )
      ..apply(
        const AiToolExecutionCompletedEvent(
          callId: 'one',
          output: 'first',
          durationMillis: 1,
        ),
      );

    final tools = accumulator.parts.whereType<ChatToolCallPart>().toList();
    expect(tools[0].result, 'first');
    expect(tools[1].result, 'second');
  });
}
