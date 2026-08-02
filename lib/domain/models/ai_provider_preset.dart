import 'chat_models.dart';

class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.authType,
    required this.documentationUrl,
    this.protocol = AiProviderProtocol.openAiCompatible,
    this.allowLocalHttp = false,
    this.supportsModelList = true,
    this.toolsByDefault = false,
    this.reasoningByDefault = true,
    this.deprecated = false,
  });

  final String id;
  final String displayName;
  final AiProviderProtocol protocol;
  final String baseUrl;
  final AiProviderAuthType authType;
  final bool allowLocalHttp;
  final bool supportsModelList;
  final bool toolsByDefault;
  final bool reasoningByDefault;
  final String documentationUrl;
  final bool deprecated;
}

class AiProviderProbeResult {
  const AiProviderProbeResult({
    required this.providerId,
    required this.statusCode,
    required this.latencyMillis,
    required this.models,
    this.errorCode,
  });

  final String providerId;
  final int? statusCode;
  final int latencyMillis;
  final List<String> models;
  final String? errorCode;

  bool get succeeded => errorCode == null;
}
