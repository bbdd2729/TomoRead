import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/ai_provider_preset.dart';
import '../../domain/models/chat_models.dart';

class AiProviderProbeService {
  const AiProviderProbeService({this.clientFactory});

  final http.Client Function()? clientFactory;

  Future<AiProviderProbeResult> probe(
    AiProviderProfile profile, {
    required String apiKey,
  }) async {
    final stopwatch = Stopwatch()..start();
    final client = clientFactory?.call() ?? http.Client();
    try {
      final uri = _modelsEndpoint(profile.baseUrl);
      final response = await client
          .get(uri, headers: _headers(profile, apiKey))
          .timeout(const Duration(seconds: 15));
      final models = response.statusCode >= 200 && response.statusCode < 300
          ? _parseModels(response.body)
          : const <String>[];
      return AiProviderProbeResult(
        providerId: profile.id,
        statusCode: response.statusCode,
        latencyMillis: stopwatch.elapsedMilliseconds,
        models: models,
        errorCode: response.statusCode >= 200 && response.statusCode < 300
            ? null
            : _statusError(response.statusCode),
      );
    } on Object catch (error) {
      return AiProviderProbeResult(
        providerId: profile.id,
        statusCode: null,
        latencyMillis: stopwatch.elapsedMilliseconds,
        models: const [],
        errorCode: error is FormatException ? 'invalid_url' : 'network_error',
      );
    } finally {
      client.close();
    }
  }

  Uri _modelsEndpoint(String source) {
    final normalized = source.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$normalized/models');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Invalid provider URL');
    }
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      throw const FormatException('Remote providers must use HTTPS');
    }
    return uri;
  }

  Map<String, String> _headers(AiProviderProfile profile, String apiKey) {
    final headers = <String, String>{'Accept': 'application/json'};
    switch (profile.authType) {
      case AiProviderAuthType.bearer:
        headers['Authorization'] = 'Bearer $apiKey';
      case AiProviderAuthType.apiKey:
        headers['api-key'] = apiKey;
      case AiProviderAuthType.none:
        break;
    }
    return headers;
  }

  List<String> _parseModels(String source) {
    final decoded = jsonDecode(source) as Map<String, Object?>;
    final data = decoded['data'] as List<Object?>? ?? const [];
    return data
        .whereType<Map<String, Object?>>()
        .map((entry) => entry['id'])
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  String _statusError(int status) => switch (status) {
    401 || 403 => 'auth_failed',
    404 => 'models_unsupported',
    429 => 'rate_limited',
    >= 500 => 'provider_unavailable',
    _ => 'request_failed',
  };
}
