import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomoread/data/services/ai_gateway.dart';
import 'package:tomoread/domain/models/ai_agent_models.dart';
import 'package:tomoread/domain/models/chat_models.dart';

void main() {
  test('normalizes reasoning, text, tools, usage, and completion events', () async {
    late Map<String, Object?> requestJson;
    final client = MockClient.streaming((request, bodyStream) async {
      requestJson =
          jsonDecode(await bodyStream.bytesToString()) as Map<String, Object?>;
      final chunks = [
        'data: {"choices":[{"delta":{"reasoning_content":"先检索。"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"回答"}}]}\n\n',
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"search_book_text","arguments":"{\\"query\\":"}}]}}]}\n\n',
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"概念\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":12,"completion_tokens":5,"completion_tokens_details":{"reasoning_tokens":2}}}\n\n',
        'data: [DONE]\n\n',
      ];
      return http.StreamedResponse(
        Stream.fromIterable(chunks.map(utf8.encode)),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final gateway = OpenAiCompatibleGateway(clientFactory: () => client);
    final now = DateTime(2026);
    final profile = AiProviderProfile(
      id: 'provider-a',
      name: 'Test',
      baseUrl: 'https://example.com/v1',
      modelId: 'model-a',
      secretKeyId: 'secret-a',
      temperature: .2,
      maxOutputTokens: 1000,
      isActive: true,
      toolsEnabled: true,
      createdAt: now,
      updatedAt: now,
    );
    const tool = AiToolDeclaration(
      name: 'search_book_text',
      displayName: '搜索书中原文',
      description: '搜索',
      kind: AiToolKind.read,
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
      },
    );

    final handle = await gateway.streamReply(
      profile: profile,
      apiKey: 'key',
      messages: const [AiProviderMessage(role: 'user', content: '问题')],
      tools: const [tool],
    );
    final events = await handle.events.toList();

    expect(requestJson['tools'], isA<List<Object?>>());
    expect(events.whereType<AiReasoningDeltaEvent>().single.delta, '先检索。');
    expect(events.whereType<AiTextDeltaEvent>().single.delta, '回答');
    final started = events.whereType<AiToolCallStartedEvent>().single;
    expect(started.callId, 'call-1');
    expect(started.displayName, '搜索书中原文');
    final ready = events.whereType<AiToolCallReadyEvent>().single.call;
    expect(ready.argumentsJson, '{"query":"概念"}');
    expect(events.whereType<AiUsageEvent>().single.usage.reasoningTokens, 2);
    expect(
      events.whereType<AiProviderCompletedEvent>().single.stopReason,
      'tool_calls',
    );
  });
}
