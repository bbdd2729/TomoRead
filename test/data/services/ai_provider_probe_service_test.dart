import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomoread/data/services/ai_provider_probe_service.dart';
import 'package:tomoread/domain/models/chat_models.dart';

void main() {
  test('loads model identifiers without adding auth for a local provider', () async {
    late http.Request captured;
    final service = AiProviderProbeService(
      clientFactory: () => MockClient((request) async {
        captured = request;
        return http.Response(
          '{"data":[{"id":"qwen3"},{"id":"gemma3"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final now = DateTime(2026);
    final profile = AiProviderProfile(
      id: 'ollama-a',
      name: 'Ollama',
      presetId: 'ollama',
      authType: AiProviderAuthType.none,
      baseUrl: 'http://localhost:11434/v1',
      modelId: 'qwen3',
      secretKeyId: 'unused',
      temperature: .3,
      maxOutputTokens: 2048,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    final result = await service.probe(profile, apiKey: '');

    expect(result.succeeded, isTrue);
    expect(result.models, ['gemma3', 'qwen3']);
    expect(captured.url.toString(), 'http://localhost:11434/v1/models');
    expect(captured.headers.containsKey('Authorization'), isFalse);
  });
}
