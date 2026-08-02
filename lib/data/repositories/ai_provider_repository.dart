import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/chat_models.dart';
import '../database/app_database.dart';

class AiProviderRepository {
  AiProviderRepository(this._database);

  final AppDatabase _database;

  Future<AiProviderProfile?> loadActive() async {
    final database = await _database.database;
    final rows = await database.query(
      'ai_provider_profiles',
      where: 'is_active = 1 AND is_enabled = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<List<AiProviderProfile>> listProfiles() async {
    final database = await _database.database;
    final rows = await database.query(
      'ai_provider_profiles',
      orderBy: 'is_active DESC, updated_at DESC, name ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<AiProviderProfile?> findById(String id) async {
    final database = await _database.database;
    final rows = await database.query(
      'ai_provider_profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<AiProviderProfile> save({
    String? id,
    required String name,
    required String baseUrl,
    required String modelId,
    required String secretKeyId,
    String? presetId,
    AiProviderProtocol protocol = AiProviderProtocol.openAiCompatible,
    AiProviderAuthType authType = AiProviderAuthType.bearer,
    String capabilitiesJson = '{}',
    String? customHeadersSecretId,
    double temperature = 0.3,
    int maxOutputTokens = 2048,
    bool toolsEnabled = false,
    bool reasoningEnabled = true,
    bool isEnabled = true,
  }) async {
    final now = DateTime.now();
    final profile = AiProviderProfile(
      id: id ?? 'provider-${now.microsecondsSinceEpoch}',
      name: name.trim(),
      presetId: presetId,
      protocol: protocol,
      authType: authType,
      baseUrl: baseUrl.trim(),
      modelId: modelId.trim(),
      secretKeyId: secretKeyId,
      temperature: temperature.clamp(0, 2).toDouble(),
      maxOutputTokens: maxOutputTokens.clamp(128, 32768),
      isActive: true,
      isEnabled: isEnabled,
      toolsEnabled: toolsEnabled,
      reasoningEnabled: reasoningEnabled,
      capabilitiesJson: capabilitiesJson,
      customHeadersSecretId: customHeadersSecretId,
      createdAt: now,
      updatedAt: now,
    );
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.update('ai_provider_profiles', {'is_active': 0});
      await transaction.insert('ai_provider_profiles', {
        'id': profile.id,
        'name': profile.name,
        'protocol': switch (profile.protocol) {
          AiProviderProtocol.openAiCompatible => 'openai_compatible',
        },
        'preset_id': profile.presetId,
        'auth_type': profile.authType.name,
        'base_url': profile.baseUrl,
        'model_id': profile.modelId,
        'secret_key_id': profile.secretKeyId,
        'temperature': profile.temperature,
        'max_output_tokens': profile.maxOutputTokens,
        'is_active': 1,
        'is_enabled': profile.isEnabled ? 1 : 0,
        'enable_tools': profile.toolsEnabled ? 1 : 0,
        'enable_reasoning': profile.reasoningEnabled ? 1 : 0,
        'capabilities_json': profile.capabilitiesJson,
        'custom_headers_secret_id': profile.customHeadersSecretId,
        'created_at': profile.createdAt.millisecondsSinceEpoch,
        'updated_at': profile.updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return profile;
  }

  Future<void> activate(String id) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.update('ai_provider_profiles', {'is_active': 0});
      await transaction.update(
        'ai_provider_profiles',
        {'is_active': 1, 'is_enabled': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final database = await _database.database;
    await database.update(
      'ai_provider_profiles',
      {
        'is_enabled': enabled ? 1 : 0,
        if (!enabled) 'is_active': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  AiProviderProfile _fromRow(Map<String, Object?> row) => AiProviderProfile(
    id: row['id']! as String,
    name: row['name']! as String,
    presetId: row['preset_id'] as String?,
    authType: AiProviderAuthType.values.firstWhere(
      (value) => value.name == row['auth_type'],
      orElse: () => AiProviderAuthType.bearer,
    ),
    baseUrl: row['base_url']! as String,
    modelId: row['model_id']! as String,
    secretKeyId: row['secret_key_id']! as String,
    temperature: (row['temperature']! as num).toDouble(),
    maxOutputTokens: row['max_output_tokens']! as int,
    isActive: (row['is_active']! as int) == 1,
    isEnabled: (row['is_enabled'] as int? ?? 1) == 1,
    toolsEnabled: (row['enable_tools'] as int? ?? 0) == 1,
    reasoningEnabled: (row['enable_reasoning'] as int? ?? 1) == 1,
    capabilitiesJson: row['capabilities_json'] as String? ?? '{}',
    customHeadersSecretId: row['custom_headers_secret_id'] as String?,
    protocol: switch (row['protocol'] as String?) {
      'openai_compatible' || null => AiProviderProtocol.openAiCompatible,
      _ => AiProviderProtocol.openAiCompatible,
    },
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}
