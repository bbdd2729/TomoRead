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
      where: 'is_active = 1',
      orderBy: 'updated_at DESC',
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
    double temperature = 0.3,
    int maxOutputTokens = 2048,
  }) async {
    final now = DateTime.now();
    final profile = AiProviderProfile(
      id: id ?? 'provider-${now.microsecondsSinceEpoch}',
      name: name.trim(),
      baseUrl: baseUrl.trim(),
      modelId: modelId.trim(),
      secretKeyId: secretKeyId,
      temperature: temperature.clamp(0, 2).toDouble(),
      maxOutputTokens: maxOutputTokens.clamp(128, 32768),
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.update('ai_provider_profiles', {'is_active': 0});
      await transaction.insert('ai_provider_profiles', {
        'id': profile.id,
        'name': profile.name,
        'protocol': 'openai_compatible',
        'base_url': profile.baseUrl,
        'model_id': profile.modelId,
        'secret_key_id': profile.secretKeyId,
        'temperature': profile.temperature,
        'max_output_tokens': profile.maxOutputTokens,
        'is_active': 1,
        'created_at': profile.createdAt.millisecondsSinceEpoch,
        'updated_at': profile.updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return profile;
  }

  AiProviderProfile _fromRow(Map<String, Object?> row) => AiProviderProfile(
    id: row['id']! as String,
    name: row['name']! as String,
    baseUrl: row['base_url']! as String,
    modelId: row['model_id']! as String,
    secretKeyId: row['secret_key_id']! as String,
    temperature: (row['temperature']! as num).toDouble(),
    maxOutputTokens: row['max_output_tokens']! as int,
    isActive: (row['is_active']! as int) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}
