import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomoread/data/services/embedding_provider_service.dart';
import 'package:tomoread/domain/models/embedding_models.dart';

void main() {
  EmbeddingProviderProfile profile({
    EmbeddingProviderMode mode = EmbeddingProviderMode.remote,
    bool consent = true,
  }) => EmbeddingProviderProfile(
    id: 'embedding-a',
    name: 'Provider',
    mode: mode,
    authType: EmbeddingProviderAuthType.bearer,
    baseUrl: mode == EmbeddingProviderMode.remote
        ? 'https://example.com/v1'
        : 'http://localhost:11434/v1',
    modelId: 'embedding-model',
    modelVersion: 'v1',
    secretKeyId: 'secret',
    distanceMetric: EmbeddingDistanceMetric.cosine,
    dimensions: 3,
    maxInputCharacters: 100,
    batchSize: 8,
    isActive: true,
    isEnabled: true,
    remoteContentConsent: consent,
    capabilityStatus: EmbeddingCapabilityStatus.ready,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('calls the OpenAI-compatible embeddings endpoint in index order', () async {
    late http.Request captured;
    final service = OpenAiCompatibleEmbeddingService(
      clientFactory: () => MockClient((request) async {
        captured = request;
        return http.Response(
          '{"data":['
          '{"index":1,"embedding":[0,1,0]},'
          '{"index":0,"embedding":[1,0,0]}]}',
          200,
        );
      }),
    );

    final result = await service.embed(
      profile: profile(),
      apiKey: 'token',
      inputs: const ['first', 'second'],
    );

    expect(captured.url.toString(), 'https://example.com/v1/embeddings');
    expect(captured.headers['Authorization'], 'Bearer token');
    expect(result, [
      [1, 0, 0],
      [0, 1, 0],
    ]);
  });

  test('does not send remote content without explicit consent', () async {
    final service = OpenAiCompatibleEmbeddingService(
      clientFactory: () => MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      () => service.embed(
        profile: profile(consent: false),
        apiKey: 'token',
        inputs: const ['private book text'],
      ),
      throwsA(
        isA<EmbeddingProviderException>().having(
          (error) => error.code,
          'code',
          'remote_consent_required',
        ),
      ),
    );
  });
}
