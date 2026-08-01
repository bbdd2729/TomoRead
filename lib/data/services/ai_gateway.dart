import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/chat_models.dart';

class AiGatewayException implements Exception {
  const AiGatewayException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class AiStreamHandle {
  const AiStreamHandle({required this.stream, required this.cancel});

  final Stream<String> stream;
  final void Function() cancel;
}

abstract interface class AiGateway {
  Future<AiStreamHandle> streamReply({
    required AiProviderProfile profile,
    required String apiKey,
    required List<ChatMessage> history,
    required String systemPrompt,
  });
}

class OpenAiCompatibleGateway implements AiGateway {
  const OpenAiCompatibleGateway();

  @override
  Future<AiStreamHandle> streamReply({
    required AiProviderProfile profile,
    required String apiKey,
    required List<ChatMessage> history,
    required String systemPrompt,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', _endpoint(profile.baseUrl))
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode({
          'model': profile.modelId,
          'stream': true,
          'temperature': profile.temperature,
          'max_tokens': profile.maxOutputTokens,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            ...history
                .where((message) => message.role != ChatRole.system)
                .map(
                  (message) => {
                    'role': message.role.name,
                    'content': message.content,
                  },
                ),
          ],
        });
      final response = await client
          .send(request)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const AiGatewayException(
              'timeout',
              '连接模型服务超时，请检查网络和服务地址。',
            ),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        client.close();
        throw AiGatewayException(
          _statusCode(response.statusCode),
          _statusMessage(response.statusCode, body),
        );
      }

      final controller = StreamController<String>();
      late StreamSubscription<String> subscription;
      var cancelled = false;
      subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (cancelled || !line.startsWith('data:')) return;
              final data = line.substring(5).trim();
              if (data.isEmpty) return;
              if (data == '[DONE]') {
                controller.close();
                client.close();
                return;
              }
              try {
                final json = jsonDecode(data) as Map<String, Object?>;
                final choices = json['choices'] as List<Object?>?;
                if (choices == null || choices.isEmpty) return;
                final choice = choices.first! as Map<String, Object?>;
                final delta = choice['delta'] as Map<String, Object?>?;
                final content = delta?['content'];
                if (content is String && content.isNotEmpty) {
                  controller.add(content);
                }
              } on FormatException {
                // Some compatible providers emit keep-alive data that is not JSON.
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!controller.isClosed) controller.addError(error, stackTrace);
              client.close();
            },
            onDone: () {
              if (!controller.isClosed) controller.close();
              client.close();
            },
            cancelOnError: true,
          );
      return AiStreamHandle(
        stream: controller.stream,
        cancel: () {
          if (cancelled) return;
          cancelled = true;
          subscription.cancel();
          client.close();
          if (!controller.isClosed) controller.close();
        },
      );
    } on Object {
      client.close();
      rethrow;
    }
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

  String _statusCode(int status) => switch (status) {
    401 || 403 => 'authentication',
    429 => 'rate_limit',
    >= 500 => 'provider_unavailable',
    _ => 'request_failed',
  };

  String _statusMessage(int status, String body) {
    final detail = body.length > 240 ? body.substring(0, 240) : body;
    return switch (status) {
      401 || 403 => 'API Key 无效或没有访问该模型的权限。',
      429 => '模型服务请求过于频繁，请稍后重试。',
      >= 500 => '模型服务暂时不可用。',
      _ => '模型请求失败（HTTP $status）${detail.isEmpty ? '' : '：$detail'}',
    };
  }
}
