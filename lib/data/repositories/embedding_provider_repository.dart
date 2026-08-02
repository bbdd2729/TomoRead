import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/embedding_models.dart';
import '../database/app_database.dart';

class EmbeddingProviderRepository {
  EmbeddingProviderRepository(this._database);

  final AppDatabase _database;

  Future<EmbeddingProviderProfile?> loadActive() async {
    final database = await _database.database;
    final rows = await database.query(
      'embedding_provider_profiles',
      where: 'is_active = 1 AND is_enabled = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<List<EmbeddingProviderProfile>> listProfiles() async {
    final database = await _database.database;
    final rows = await database.query(
      'embedding_provider_profiles',
      orderBy: 'is_active DESC, updated_at DESC, name ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<EmbeddingProviderProfile?> findById(String id) async {
    final database = await _database.database;
    final rows = await database.query(
      'embedding_provider_profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<EmbeddingProviderProfile> save({
    String? id,
    required String name,
    required String baseUrl,
    required String modelId,
    required String modelVersion,
    required String secretKeyId,
    required EmbeddingProviderMode mode,
    required EmbeddingProviderAuthType authType,
    required EmbeddingDistanceMetric distanceMetric,
    required bool remoteContentConsent,
    String? presetId,
    int? dimensions,
    int maxInputCharacters = 8000,
    int batchSize = 16,
    bool isEnabled = true,
  }) async {
    final normalizedName = name.trim();
    final normalizedUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final normalizedModel = modelId.trim();
    final normalizedVersion = modelVersion.trim();
    if (normalizedName.isEmpty ||
        normalizedUrl.isEmpty ||
        normalizedModel.isEmpty ||
        normalizedVersion.isEmpty) {
      throw const FormatException(
        'Name, Base URL, model ID and model version are required.',
      );
    }
    if (dimensions != null && dimensions <= 0) {
      throw const FormatException('Embedding dimensions must be positive.');
    }
    _validateEndpoint(normalizedUrl, mode);
    final now = DateTime.now();
    final existing = id == null ? null : await findById(id);
    final modelChanged = existing != null &&
        (existing.baseUrl != normalizedUrl ||
            existing.modelId != normalizedModel ||
            existing.modelVersion != normalizedVersion ||
            existing.distanceMetric != distanceMetric ||
            existing.dimensions != dimensions);
    final profile = EmbeddingProviderProfile(
      id: id ?? 'embedding-${now.microsecondsSinceEpoch}',
      name: normalizedName,
      presetId: presetId,
      mode: mode,
      authType: authType,
      baseUrl: normalizedUrl,
      modelId: normalizedModel,
      modelVersion: normalizedVersion,
      secretKeyId: secretKeyId,
      distanceMetric: distanceMetric,
      dimensions: dimensions,
      maxInputCharacters: maxInputCharacters.clamp(256, 100000),
      batchSize: batchSize.clamp(1, 128),
      isActive: true,
      isEnabled: isEnabled,
      remoteContentConsent:
          mode == EmbeddingProviderMode.remote && remoteContentConsent,
      capabilityStatus: modelChanged || existing == null
          ? EmbeddingCapabilityStatus.untested
          : existing.capabilityStatus,
      capabilityErrorCode: modelChanged ? null : existing?.capabilityErrorCode,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.update('embedding_provider_profiles', {
        'is_active': 0,
      });
      final row = _toRow(profile);
      if (existing == null) {
        await transaction.insert(
          'embedding_provider_profiles',
          row,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        await transaction.update(
          'embedding_provider_profiles',
          row,
          where: 'id = ?',
          whereArgs: [profile.id],
        );
      }
      if (modelChanged) {
        await transaction.update(
          'content_embeddings',
          {
            'status': ContentEmbeddingStatus.stale.name,
            'error_code': 'model_changed',
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'profile_id = ?',
          whereArgs: [profile.id],
        );
        await transaction.update(
          'semantic_index_states',
          {
            'status': SemanticIndexStatus.stale.name,
            'indexed_chunks': 0,
            'failed_chunks': 0,
            'error_code': 'model_changed',
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'profile_id = ?',
          whereArgs: [profile.id],
        );
      }
    });
    return profile;
  }

  Future<void> activate(String id) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.update('embedding_provider_profiles', {
        'is_active': 0,
      });
      final count = await transaction.update(
        'embedding_provider_profiles',
        {
          'is_active': 1,
          'is_enabled': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) {
        throw StateError('Embedding profile does not exist.');
      }
    });
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final database = await _database.database;
    await database.update(
      'embedding_provider_profiles',
      {
        'is_enabled': enabled ? 1 : 0,
        if (!enabled) 'is_active': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<EmbeddingProviderProfile> recordProbe(
    String id,
    EmbeddingProbeResult result,
  ) async {
    final existing = await findById(id);
    if (existing == null) {
      throw StateError('Embedding profile does not exist.');
    }
    final dimensions = result.succeeded ? result.dimensions : existing.dimensions;
    final database = await _database.database;
    await database.update(
      'embedding_provider_profiles',
      {
        'dimensions': dimensions,
        'capability_status': result.capabilityStatus.name,
        'capability_error_code': result.errorCode,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (await findById(id))!;
  }

  Future<String?> delete(String id) async {
    final existing = await findById(id);
    if (existing == null) return null;
    final database = await _database.database;
    await database.delete(
      'embedding_provider_profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
    return existing.secretKeyId;
  }

  Map<String, Object?> _toRow(EmbeddingProviderProfile profile) => {
    'id': profile.id,
    'name': profile.name,
    'protocol': 'openai_compatible',
    'preset_id': profile.presetId,
    'mode': profile.mode.name,
    'auth_type': profile.authType.name,
    'base_url': profile.baseUrl,
    'model_id': profile.modelId,
    'model_version': profile.modelVersion,
    'secret_key_id': profile.secretKeyId,
    'distance_metric': profile.distanceMetric.name,
    'dimensions': profile.dimensions,
    'max_input_characters': profile.maxInputCharacters,
    'batch_size': profile.batchSize,
    'is_active': profile.isActive ? 1 : 0,
    'is_enabled': profile.isEnabled ? 1 : 0,
    'remote_content_consent': profile.remoteContentConsent ? 1 : 0,
    'capability_status': profile.capabilityStatus.name,
    'capability_error_code': profile.capabilityErrorCode,
    'created_at': profile.createdAt.millisecondsSinceEpoch,
    'updated_at': profile.updatedAt.millisecondsSinceEpoch,
  };

  EmbeddingProviderProfile _fromRow(Map<String, Object?> row) =>
      EmbeddingProviderProfile(
        id: row['id']! as String,
        name: row['name']! as String,
        presetId: row['preset_id'] as String?,
        mode: EmbeddingProviderMode.values.firstWhere(
          (value) => value.name == row['mode'],
          orElse: () => EmbeddingProviderMode.remote,
        ),
        authType: EmbeddingProviderAuthType.values.firstWhere(
          (value) => value.name == row['auth_type'],
          orElse: () => EmbeddingProviderAuthType.bearer,
        ),
        baseUrl: row['base_url']! as String,
        modelId: row['model_id']! as String,
        modelVersion: row['model_version']! as String,
        secretKeyId: row['secret_key_id']! as String,
        distanceMetric: EmbeddingDistanceMetric.values.firstWhere(
          (value) => value.name == row['distance_metric'],
          orElse: () => EmbeddingDistanceMetric.cosine,
        ),
        dimensions: row['dimensions'] as int?,
        maxInputCharacters: row['max_input_characters']! as int,
        batchSize: row['batch_size']! as int,
        isActive: (row['is_active']! as int) == 1,
        isEnabled: (row['is_enabled']! as int) == 1,
        remoteContentConsent:
            (row['remote_content_consent']! as int) == 1,
        capabilityStatus: EmbeddingCapabilityStatus.values.firstWhere(
          (value) => value.name == row['capability_status'],
          orElse: () => EmbeddingCapabilityStatus.untested,
        ),
        capabilityErrorCode: row['capability_error_code'] as String?,
        protocol: EmbeddingProviderProtocol.openAiCompatible,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at']! as int,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at']! as int,
        ),
      );

  void _validateEndpoint(String source, EmbeddingProviderMode mode) {
    final uri = Uri.tryParse(source);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Embedding provider URL is invalid.');
    }
    final loopback = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
    if (mode == EmbeddingProviderMode.localService &&
        !(uri.scheme == 'http' && loopback)) {
      throw const FormatException(
        'Local service profiles must use a loopback HTTP endpoint.',
      );
    }
    if (mode == EmbeddingProviderMode.remote && uri.scheme != 'https') {
      throw const FormatException('Remote profiles must use HTTPS.');
    }
  }
}
