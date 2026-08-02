import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/embedding_models.dart';

class EmbeddingProviderException implements Exception {
  const EmbeddingProviderException(
    this.code,
    this.message, {
    this.recoverable = true,
  });

  final String code;
  final String message;
  final bool recoverable;

  @override
  String toString() => message;
}

class EmbeddingCancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const EmbeddingProviderException('cancelled', 'Operation cancelled.');
    }
  }

  void Function() addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

class OpenAiCompatibleEmbeddingService {
  const OpenAiCompatibleEmbeddingService({this.clientFactory});

  final http.Client Function()? clientFactory;

  Future<List<List<double>>> embed({
    required EmbeddingProviderProfile profile,
    required String apiKey,
    required List<String> inputs,
    EmbeddingCancellationToken? cancellationToken,
    bool capabilityProbe = false,
    bool validateConfiguredDimensions = true,
  }) async {
    if (inputs.isEmpty) return const [];
    if (!capabilityProbe && !profile.canSendContent) {
      throw const EmbeddingProviderException(
        'remote_consent_required',
        'Remote content sharing has not been enabled for this profile.',
        recoverable: false,
      );
    }
    for (final input in inputs) {
      if (input.isEmpty || input.length > profile.maxInputCharacters) {
        throw const EmbeddingProviderException(
          'input_too_long',
          'A content chunk exceeds the configured input limit.',
          recoverable: false,
        );
      }
    }
    cancellationToken?.throwIfCancelled();
    final client = clientFactory?.call() ?? http.Client();
    final removeCancelListener = cancellationToken?.addListener(client.close);
    try {
      final response = await client
          .post(
            _endpoint(profile.baseUrl, 'embeddings'),
            headers: _headers(profile, apiKey),
            body: jsonEncode({
              'model': profile.modelId,
              'input': inputs,
              'encoding_format': 'float',
            }),
          )
          .timeout(const Duration(seconds: 60));
      cancellationToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw EmbeddingProviderException(
          _statusError(response.statusCode),
          'Embedding provider rejected the request (HTTP ${response.statusCode}).',
          recoverable: response.statusCode == 429 || response.statusCode >= 500,
        );
      }
      return _parseVectors(
        response.body,
        inputs.length,
        validateConfiguredDimensions ? profile.dimensions : null,
      );
    } on EmbeddingProviderException {
      rethrow;
    } on FormatException catch (error) {
      throw EmbeddingProviderException(
        'invalid_response',
        error.message,
        recoverable: false,
      );
    } on Object {
      cancellationToken?.throwIfCancelled();
      throw const EmbeddingProviderException(
        'network_error',
        'Embedding provider could not be reached.',
      );
    } finally {
      removeCancelListener?.call();
      client.close();
    }
  }

  Future<List<String>> listModels({
    required EmbeddingProviderProfile profile,
    required String apiKey,
  }) async {
    final client = clientFactory?.call() ?? http.Client();
    try {
      final response = await client
          .get(
            _endpoint(profile.baseUrl, 'models'),
            headers: _headers(profile, apiKey, contentType: false),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body) as Map<String, Object?>;
      final data = decoded['data'] as List<Object?>? ?? const [];
      return data
          .whereType<Map<String, Object?>>()
          .map((entry) => entry['id'])
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    } on Object {
      return const [];
    } finally {
      client.close();
    }
  }

  Uri _endpoint(String source, String path) {
    final normalized = source.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$normalized/$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const EmbeddingProviderException(
        'invalid_url',
        'Embedding provider URL is invalid.',
        recoverable: false,
      );
    }
    final local = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      throw const EmbeddingProviderException(
        'insecure_url',
        'Remote embedding providers must use HTTPS.',
        recoverable: false,
      );
    }
    return uri;
  }

  Map<String, String> _headers(
    EmbeddingProviderProfile profile,
    String apiKey, {
    bool contentType = true,
  }) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (contentType) headers['Content-Type'] = 'application/json';
    switch (profile.authType) {
      case EmbeddingProviderAuthType.bearer:
        headers['Authorization'] = 'Bearer $apiKey';
      case EmbeddingProviderAuthType.apiKey:
        headers['api-key'] = apiKey;
      case EmbeddingProviderAuthType.none:
        break;
    }
    return headers;
  }

  List<List<double>> _parseVectors(
    String source,
    int expectedCount,
    int? expectedDimensions,
  ) {
    final decoded = jsonDecode(source) as Map<String, Object?>;
    final data = decoded['data'] as List<Object?>?;
    if (data == null || data.length != expectedCount) {
      throw const FormatException('Embedding response count does not match.');
    }
    final indexed = <(int, List<double>)>[];
    for (var position = 0; position < data.length; position++) {
      final item = data[position] as Map<String, Object?>?;
      final values = item?['embedding'] as List<Object?>?;
      if (item == null || values == null || values.isEmpty) {
        throw const FormatException('Embedding response contains no vector.');
      }
      final vector = values.map((value) {
        if (value is! num || !value.toDouble().isFinite) {
          throw const FormatException('Embedding vector is not numeric.');
        }
        return value.toDouble();
      }).toList(growable: false);
      if (expectedDimensions != null && vector.length != expectedDimensions) {
        throw const FormatException('Embedding dimensions do not match.');
      }
      indexed.add(((item['index'] as num?)?.toInt() ?? position, vector));
    }
    indexed.sort((left, right) => left.$1.compareTo(right.$1));
    if (indexed.map((item) => item.$2.length).toSet().length != 1) {
      throw const FormatException('Embedding vectors use mixed dimensions.');
    }
    return indexed.map((item) => item.$2).toList(growable: false);
  }

  String _statusError(int status) => switch (status) {
    400 => 'invalid_request',
    401 || 403 => 'auth_failed',
    404 => 'embeddings_unsupported',
    413 => 'input_too_long',
    429 => 'rate_limited',
    >= 500 => 'provider_unavailable',
    _ => 'request_failed',
  };
}
