import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/ai_agent_models.dart';
import '../../domain/models/chat_models.dart';
import 'sse_decoder.dart';

class AiGatewayException implements Exception {
  const AiGatewayException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class AiStreamHandle {
  const AiStreamHandle({required this.events, required this.cancel});

  final Stream<AiStreamEvent> events;
  final void Function() cancel;
}

abstract interface class AiGateway {
  AiCapabilities capabilities(AiProviderProfile profile);

  Future<AiStreamHandle> streamReply({
    required AiProviderProfile profile,
    required String apiKey,
    required List<AiProviderMessage> messages,
    List<AiToolDeclaration> tools = const [],
  });
}

class OpenAiCompatibleGateway implements AiGateway {
  const OpenAiCompatibleGateway({
    this.idleTimeout = const Duration(seconds: 75),
    this.clientFactory,
  });

  final Duration idleTimeout;
  final http.Client Function()? clientFactory;

  @override
  AiCapabilities capabilities(AiProviderProfile profile) => AiCapabilities(
    streaming: true,
    tools: profile.toolsEnabled,
    reasoningSummary: profile.reasoningEnabled,
    usage: true,
  );

  @override
  Future<AiStreamHandle> streamReply({
    required AiProviderProfile profile,
    required String apiKey,
    required List<AiProviderMessage> messages,
    List<AiToolDeclaration> tools = const [],
  }) async {
    final client = clientFactory?.call() ?? http.Client();
    try {
      final body = <String, Object?>{
        'model': profile.modelId,
        'stream': true,
        'temperature': profile.temperature,
        'max_tokens': profile.maxOutputTokens,
        'messages': messages
            .map(
              (message) => _encodeMessage(
                message,
                includeReasoning: profile.reasoningEnabled,
              ),
            )
            .toList(),
      };
      if (tools.isNotEmpty && profile.toolsEnabled) {
        body['tools'] = tools
            .map(
              (tool) => {
                'type': 'function',
                'function': {
                  'name': tool.name,
                  'description': tool.description,
                  'parameters': tool.inputSchema,
                },
              },
            )
            .toList();
        body['tool_choice'] = 'auto';
      }
      final request = http.Request('POST', _endpoint(profile.baseUrl))
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream, application/json',
        })
        ..body = jsonEncode(body);
      final response = await client
          .send(request)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const AiGatewayException(
              'connection_timeout',
              '连接模型服务超时，请检查网络和服务地址。',
            ),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseBody = await response.stream.bytesToString();
        client.close();
        throw AiGatewayException(
          _statusCode(response.statusCode),
          _statusMessage(response.statusCode, responseBody),
        );
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (!contentType.contains('text/event-stream')) {
        final responseBody = await response.stream.bytesToString();
        client.close();
        return _jsonHandle(responseBody, tools);
      }

      final controller = StreamController<AiStreamEvent>();
      final declarations = {for (final tool in tools) tool.name: tool};
      final buffers = <int, _ToolCallBuffer>{};
      StreamSubscription<SseEvent>? subscription;
      var cancelled = false;
      var completed = false;
      String? stopReason;

      void emitToolState() {
        for (final buffer in buffers.values) {
          if (!buffer.started && buffer.name.isNotEmpty) {
            buffer.started = true;
            final declaration = declarations[buffer.name];
            controller.add(
              AiToolCallStartedEvent(
                callId: buffer.id,
                name: buffer.name,
                displayName: declaration?.displayName ?? buffer.name,
                kind: declaration?.kind ?? AiToolKind.read,
                skillId: declaration?.skillId,
              ),
            );
          }
          if (buffer.started &&
              buffer.arguments.length > buffer.emittedArgumentsLength) {
            final delta = buffer.arguments.substring(
              buffer.emittedArgumentsLength,
            );
            buffer.emittedArgumentsLength = buffer.arguments.length;
            controller.add(
              AiToolArgumentsDeltaEvent(callId: buffer.id, delta: delta),
            );
          }
        }
      }

      void completeStream() {
        if (completed) return;
        completed = true;
        emitToolState();
        for (final buffer in buffers.values) {
          if (!buffer.ready && buffer.name.isNotEmpty) {
            buffer.ready = true;
            controller.add(AiToolCallReadyEvent(buffer.toCall()));
          }
        }
        controller.add(AiProviderCompletedEvent(stopReason: stopReason));
        unawaited(controller.close());
        client.close();
      }

      subscription = const SseDecoder()
          .decode(response.stream)
          .timeout(idleTimeout)
          .listen(
            (event) {
              if (cancelled || completed) return;
              final data = event.data.trim();
              if (data.isEmpty) return;
              if (data == '[DONE]') {
                completeStream();
                return;
              }
              try {
                final json = jsonDecode(data) as Map<String, Object?>;
                if (event.event == 'error' || json['error'] != null) {
                  throw AiGatewayException(
                    'provider_stream_error',
                    _providerError(json['error']),
                  );
                }
                final choices = json['choices'] as List<Object?>?;
                if (choices != null && choices.isNotEmpty) {
                  final choice = choices.first! as Map<String, Object?>;
                  final delta = choice['delta'] as Map<String, Object?>?;
                  if (delta != null) {
                    final content = _textDelta(delta['content']);
                    if (content.isNotEmpty) {
                      controller.add(AiTextDeltaEvent(content));
                    }
                    final reasoning = _reasoningDelta(delta);
                    if (profile.reasoningEnabled && reasoning.isNotEmpty) {
                      controller.add(AiReasoningDeltaEvent(reasoning));
                    }
                    final toolCalls = delta['tool_calls'] as List<Object?>?;
                    if (toolCalls != null) {
                      for (final rawCall in toolCalls) {
                        if (rawCall is! Map<String, Object?>) continue;
                        final index = rawCall['index'] as int? ?? 0;
                        final buffer = buffers.putIfAbsent(
                          index,
                          () => _ToolCallBuffer(index),
                        );
                        final id = rawCall['id'];
                        if (!buffer.started && id is String && id.isNotEmpty) {
                          buffer.id = id;
                        }
                        final function =
                            rawCall['function'] as Map<String, Object?>?;
                        final name = function?['name'];
                        if (name is String) buffer.name += name;
                        final arguments = function?['arguments'];
                        if (arguments is String) {
                          buffer.arguments += arguments;
                        }
                      }
                      emitToolState();
                    }
                  }
                  final reason = choice['finish_reason'];
                  if (reason is String && reason.isNotEmpty) {
                    stopReason = reason;
                  }
                }
                final usage = _parseUsage(json['usage']);
                if (usage != null) controller.add(AiUsageEvent(usage));
              } on AiGatewayException catch (error, stackTrace) {
                if (!controller.isClosed) {
                  controller.addError(error, stackTrace);
                  unawaited(controller.close());
                }
                completed = true;
                subscription?.cancel();
                client.close();
              } on FormatException {
                // Compatible services sometimes send keep-alive data as text.
              } on TypeError catch (error, stackTrace) {
                if (!controller.isClosed) {
                  controller.addError(
                    AiGatewayException(
                      'invalid_stream',
                      '模型服务返回了无法识别的流式数据：$error',
                    ),
                    stackTrace,
                  );
                  unawaited(controller.close());
                }
                completed = true;
                subscription?.cancel();
                client.close();
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!controller.isClosed && !cancelled) {
                final mapped = error is TimeoutException
                    ? const AiGatewayException(
                        'stream_idle_timeout',
                        '模型服务长时间没有返回新内容。',
                      )
                    : error;
                controller.addError(mapped, stackTrace);
                unawaited(controller.close());
              }
              client.close();
            },
            onDone: () {
              if (!cancelled) completeStream();
              client.close();
            },
            cancelOnError: true,
          );
      return AiStreamHandle(
        events: controller.stream,
        cancel: () {
          if (cancelled) return;
          cancelled = true;
          subscription?.cancel();
          client.close();
          if (!controller.isClosed) unawaited(controller.close());
        },
      );
    } on Object {
      client.close();
      rethrow;
    }
  }

  AiStreamHandle _jsonHandle(String source, List<AiToolDeclaration> tools) {
    try {
      final json = jsonDecode(source) as Map<String, Object?>;
      if (json['error'] != null) {
        throw AiGatewayException(
          'provider_error',
          _providerError(json['error']),
        );
      }
      final events = <AiStreamEvent>[];
      final choices = json['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) {
        throw const AiGatewayException('invalid_response', '模型服务没有返回可用回答。');
      }
      final choice = choices.first! as Map<String, Object?>;
      final message = choice['message'] as Map<String, Object?>? ?? const {};
      final reasoning = _reasoningDelta(message);
      if (reasoning.isNotEmpty) events.add(AiReasoningDeltaEvent(reasoning));
      final content = _textDelta(message['content']);
      if (content.isNotEmpty) events.add(AiTextDeltaEvent(content));
      final declarations = {for (final tool in tools) tool.name: tool};
      final toolCalls = message['tool_calls'] as List<Object?>? ?? const [];
      for (var index = 0; index < toolCalls.length; index++) {
        final raw = toolCalls[index] as Map<String, Object?>;
        final function = raw['function'] as Map<String, Object?>? ?? const {};
        final name = function['name'] as String? ?? 'unknown_tool';
        final id = raw['id'] as String? ?? 'tool-$index';
        final arguments = function['arguments'] as String? ?? '{}';
        final declaration = declarations[name];
        events
          ..add(
            AiToolCallStartedEvent(
              callId: id,
              name: name,
              displayName: declaration?.displayName ?? name,
              kind: declaration?.kind ?? AiToolKind.read,
              skillId: declaration?.skillId,
            ),
          )
          ..add(AiToolArgumentsDeltaEvent(callId: id, delta: arguments))
          ..add(
            AiToolCallReadyEvent(
              AiRequestedToolCall(id: id, name: name, argumentsJson: arguments),
            ),
          );
      }
      final usage = _parseUsage(json['usage']);
      if (usage != null) events.add(AiUsageEvent(usage));
      events.add(
        AiProviderCompletedEvent(
          stopReason: choice['finish_reason'] as String?,
        ),
      );
      return AiStreamHandle(events: Stream.fromIterable(events), cancel: () {});
    } on AiGatewayException {
      rethrow;
    } on Object catch (error) {
      throw AiGatewayException('invalid_response', '模型服务返回了无法识别的数据：$error');
    }
  }

  Map<String, Object?> _encodeMessage(
    AiProviderMessage message, {
    required bool includeReasoning,
  }) {
    final encoded = <String, Object?>{'role': message.role};
    if (message.content != null) encoded['content'] = message.content;
    if (includeReasoning && message.reasoningContent != null) {
      encoded['reasoning_content'] = message.reasoningContent;
    }
    if (message.toolCallId != null) {
      encoded['tool_call_id'] = message.toolCallId;
    }
    if (message.toolCalls.isNotEmpty) {
      encoded['tool_calls'] = message.toolCalls
          .map(
            (call) => {
              'id': call.id,
              'type': 'function',
              'function': {'name': call.name, 'arguments': call.argumentsJson},
            },
          )
          .toList();
    }
    return encoded;
  }

  Uri _endpoint(String source) {
    final normalized = source.trim().replaceFirst(RegExp(r'/+$'), '');
    final value = normalized.endsWith('/chat/completions')
        ? normalized
        : '$normalized/chat/completions';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AiGatewayException('invalid_url', '模型服务地址无效。');
    }
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
      throw const AiGatewayException(
        'insecure_url',
        '远程模型服务必须使用 HTTPS；本地服务可以使用 localhost。',
      );
    }
    return uri;
  }

  String _textDelta(Object? source) {
    if (source is String) return source;
    if (source is! List<Object?>) return '';
    return source
        .whereType<Map<String, Object?>>()
        .map((part) => part['text'])
        .whereType<String>()
        .join();
  }

  String _reasoningDelta(Map<String, Object?> source) {
    for (final key in const ['reasoning_content', 'reasoning', 'thinking']) {
      final value = source[key];
      if (value is String) return value;
      if (value is Map<String, Object?> && value['content'] is String) {
        return value['content']! as String;
      }
    }
    return '';
  }

  AiUsage? _parseUsage(Object? source) {
    if (source is! Map<String, Object?>) return null;
    final completionDetails =
        source['completion_tokens_details'] as Map<String, Object?>?;
    final promptDetails =
        source['prompt_tokens_details'] as Map<String, Object?>?;
    return AiUsage(
      inputTokens: source['prompt_tokens'] as int? ?? 0,
      outputTokens: source['completion_tokens'] as int? ?? 0,
      reasoningTokens: completionDetails?['reasoning_tokens'] as int? ?? 0,
      cachedTokens: promptDetails?['cached_tokens'] as int? ?? 0,
    );
  }

  String _providerError(Object? source) {
    if (source is Map<String, Object?>) {
      final message = source['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return '模型服务在生成过程中返回错误。';
  }

  String _statusCode(int status) => switch (status) {
    401 || 403 => 'auth_failed',
    429 => 'rate_limited',
    >= 500 => 'provider_unavailable',
    _ => 'request_failed',
  };

  String _statusMessage(int status, String body) {
    String detail = '';
    try {
      final decoded = jsonDecode(body) as Map<String, Object?>;
      detail = _providerError(decoded['error']);
    } on Object {
      detail = body.length > 160 ? body.substring(0, 160) : body;
    }
    return switch (status) {
      401 || 403 => 'API Key 无效或没有访问该模型的权限。',
      429 => '模型服务请求过于频繁，请稍后重试。',
      >= 500 => '模型服务暂时不可用。',
      _ => '模型请求失败（HTTP $status）${detail.isEmpty ? '' : '：$detail'}',
    };
  }
}

class _ToolCallBuffer {
  _ToolCallBuffer(this.index) : id = 'tool-$index';

  final int index;
  String id;
  String name = '';
  String arguments = '';
  int emittedArgumentsLength = 0;
  bool started = false;
  bool ready = false;

  AiRequestedToolCall toCall() => AiRequestedToolCall(
    id: id,
    name: name,
    argumentsJson: arguments.isEmpty ? '{}' : arguments,
  );
}
