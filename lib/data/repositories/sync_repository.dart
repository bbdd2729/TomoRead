import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/sync_models.dart';
import '../database/app_database.dart';
import '../services/sync_merge_service.dart';

class SyncRepository {
  SyncRepository(
    this._database, {
    this.mergeService = const SyncMergeService(),
    this.tombstoneRetention = const Duration(days: 90),
  });

  final AppDatabase _database;
  final SyncMergeService mergeService;
  final Duration tombstoneRetention;

  Future<void> registerDevice({
    required String deviceId,
    required String displayName,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final normalizedName = displayName.trim().isEmpty
        ? 'TomoRead device'
        : displayName.trim();
    final database = await _database.database;
    await database.insert('sync_devices', {
      'id': deviceId,
      'display_name': normalizedName,
      'created_at': timestamp,
      'last_seen_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await database.update(
      'sync_devices',
      {'display_name': normalizedName, 'last_seen_at': timestamp},
      where: 'id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<SyncEnvelope> putLocal({
    required SyncEntityType entityType,
    required String entityId,
    required Map<String, Object?> payload,
    required String deviceId,
    DateTime? updatedAt,
  }) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final current = await _readRecord(transaction, entityType, entityId);
      final revision = (current?.revision ?? 0) + 1;
      final envelope = mergeService.createUpsert(
        entityType: entityType,
        entityId: entityId,
        revision: revision,
        updatedAt: updatedAt ?? DateTime.now(),
        deviceId: deviceId,
        payload: payload,
      );
      await _writeEnvelope(transaction, envelope);
      return envelope;
    });
  }

  Future<SyncEnvelope> deleteLocal({
    required SyncEntityType entityType,
    required String entityId,
    required String deviceId,
    DateTime? deletedAt,
  }) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final current = await _readRecord(transaction, entityType, entityId);
      final envelope = mergeService.createDelete(
        entityType: entityType,
        entityId: entityId,
        revision: (current?.revision ?? 0) + 1,
        deletedAt: deletedAt ?? DateTime.now(),
        deviceId: deviceId,
      );
      await _writeEnvelope(transaction, envelope);
      return envelope;
    });
  }

  Future<SyncEnvelope?> find(
    SyncEntityType entityType,
    String entityId,
  ) async => _readRecord(await _database.database, entityType, entityId);

  Future<SyncMergeOutcome> mergeIncoming(SyncEnvelope incoming) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final local = await _readRecord(
        transaction,
        incoming.entityType,
        incoming.entityId,
      );
      final outcome = mergeService.merge(local, incoming);
      if (outcome.disposition == SyncMergeDisposition.conflict) {
        await _insertConflict(transaction, outcome.conflict!);
      } else if (outcome.disposition == SyncMergeDisposition.applied) {
        await _writeEnvelope(transaction, outcome.envelope);
      }
      return outcome;
    });
  }

  Future<List<SyncMergeOutcome>> mergeBatch(
    Iterable<SyncEnvelope> incoming,
  ) async {
    final sorted = incoming.toList(growable: false)
      ..sort((left, right) {
        final type = left.entityType.name.compareTo(right.entityType.name);
        if (type != 0) return type;
        final id = left.entityId.compareTo(right.entityId);
        if (id != 0) return id;
        final revision = left.revision.compareTo(right.revision);
        if (revision != 0) return revision;
        final time = left.updatedAt.compareTo(right.updatedAt);
        return time != 0 ? time : left.deviceId.compareTo(right.deviceId);
      });
    final outcomes = <SyncMergeOutcome>[];
    for (final envelope in sorted) {
      outcomes.add(await mergeIncoming(envelope));
    }
    return outcomes;
  }

  Future<List<SyncChange>> changesAfter(int sequence, {int limit = 500}) async {
    final database = await _database.database;
    final rows = await database.query(
      'sync_changes',
      where: 'sequence > ?',
      whereArgs: [sequence],
      orderBy: 'sequence ASC',
      limit: limit.clamp(1, 2000).toInt(),
    );
    return rows
        .map(
          (row) => SyncChange(
            sequence: row['sequence']! as int,
            envelope: _rowEnvelope(row, timestampColumn: 'modified_at'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<SyncConflict>> pendingConflicts() async {
    final database = await _database.database;
    final rows = await database.query(
      'sync_conflicts',
      where: 'resolved_at IS NULL',
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(_rowConflict).toList(growable: false);
  }

  Future<SyncEnvelope> resolveConflict({
    required String conflictId,
    required Map<String, Object?> resolutionPayload,
    required String deviceId,
    DateTime? resolvedAt,
  }) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'sync_conflicts',
        where: 'id = ? AND resolved_at IS NULL',
        whereArgs: [conflictId],
        limit: 1,
      );
      if (rows.isEmpty) throw const FormatException('同步冲突不存在或已解决。');
      final conflict = _rowConflict(rows.single);
      final current = await _readRecord(
        transaction,
        conflict.entityType,
        conflict.entityId,
      );
      final timestamp = (resolvedAt ?? DateTime.now()).toUtc();
      final envelope = mergeService.createUpsert(
        entityType: conflict.entityType,
        entityId: conflict.entityId,
        revision: (current?.revision ?? 0) + 1,
        updatedAt: timestamp,
        deviceId: deviceId,
        payload: resolutionPayload,
      );
      await _writeEnvelope(transaction, envelope);
      await transaction.update(
        'sync_conflicts',
        {
          'resolved_at': timestamp.millisecondsSinceEpoch,
          'resolution_payload_json': jsonEncode(resolutionPayload),
        },
        where: 'id = ?',
        whereArgs: [conflictId],
      );
      return envelope;
    });
  }

  Future<void> acknowledgeTombstone({
    required SyncEntityType entityType,
    required String entityId,
    required String deviceId,
  }) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'sync_tombstones',
        columns: ['acknowledged_devices_json'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType.name, entityId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final acknowledged = (jsonDecode(
        rows.single['acknowledged_devices_json']! as String,
      ) as List<dynamic>).whereType<String>().toSet()
        ..add(deviceId);
      final sorted = acknowledged.toList()..sort();
      await transaction.update(
        'sync_tombstones',
        {'acknowledged_devices_json': jsonEncode(sorted)},
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType.name, entityId],
      );
    });
  }

  Future<int> purgeEligibleTombstones({DateTime? now}) async {
    final database = await _database.database;
    return database.transaction((transaction) async {
      final devices = (await transaction.query('sync_devices', columns: ['id']))
          .map((row) => row['id']! as String)
          .toSet();
      final timestamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
      final rows = await transaction.query('sync_tombstones');
      var purged = 0;
      for (final row in rows) {
        final acknowledged = (jsonDecode(
          row['acknowledged_devices_json']! as String,
        ) as List<dynamic>).whereType<String>().toSet();
        final expired = (row['purge_after']! as int) <= timestamp;
        if (!expired && !acknowledged.containsAll(devices)) continue;
        final args = [row['entity_type'], row['entity_id']];
        await transaction.delete(
          'sync_tombstones',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: args,
        );
        await transaction.delete(
          'sync_records',
          where: "entity_type = ? AND entity_id = ? AND operation = 'delete'",
          whereArgs: args,
        );
        purged++;
      }
      return purged;
    });
  }

  Future<void> saveState(SyncStateSummary state) async {
    final database = await _database.database;
    await database.insert('sync_state', {
      'backend_id': state.backendId,
      'remote_id': state.remoteId,
      'cursor': state.cursor,
      'last_success_at': state.lastSuccessAt?.toUtc().millisecondsSinceEpoch,
      'last_summary_json': state.lastSummaryJson,
      'error_code': state.errorCode,
      'credential_ref': state.credentialRef,
      'updated_at': state.updatedAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SyncStateSummary?> loadState({
    required String backendId,
    required String remoteId,
  }) async {
    final database = await _database.database;
    final rows = await database.query(
      'sync_state',
      where: 'backend_id = ? AND remote_id = ?',
      whereArgs: [backendId, remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final lastSuccessAt = row['last_success_at'] as int?;
    return SyncStateSummary(
      backendId: row['backend_id']! as String,
      remoteId: row['remote_id']! as String,
      cursor: row['cursor'] as String?,
      lastSuccessAt: lastSuccessAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastSuccessAt, isUtc: true),
      lastSummaryJson: row['last_summary_json'] as String?,
      errorCode: row['error_code'] as String?,
      credentialRef: row['credential_ref'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at']! as int,
        isUtc: true,
      ),
    );
  }

  Future<SyncEnvelope?> _readRecord(
    DatabaseExecutor database,
    SyncEntityType entityType,
    String entityId,
  ) async {
    final rows = await database.query(
      'sync_records',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType.name, entityId],
      limit: 1,
    );
    return rows.isEmpty ? null : _rowEnvelope(rows.single);
  }

  Future<void> _writeEnvelope(
    DatabaseExecutor database,
    SyncEnvelope envelope,
  ) async {
    final row = {
      'entity_type': envelope.entityType.name,
      'entity_id': envelope.entityId,
      'revision': envelope.revision,
      'updated_at': envelope.updatedAt.toUtc().millisecondsSinceEpoch,
      'device_id': envelope.deviceId,
      'operation': envelope.operation.name,
      'payload_json': jsonEncode(envelope.payload),
      'payload_hash': envelope.payloadHash,
    };
    await database.insert(
      'sync_records',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await database.insert('sync_changes', {
      'entity_type': envelope.entityType.name,
      'entity_id': envelope.entityId,
      'revision': envelope.revision,
      'modified_at': envelope.updatedAt.toUtc().millisecondsSinceEpoch,
      'device_id': envelope.deviceId,
      'operation': envelope.operation.name,
      'payload_json': jsonEncode(envelope.payload),
      'payload_hash': envelope.payloadHash,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (envelope.isDeleted) {
      final existingTombstones = await database.query(
        'sync_tombstones',
        columns: ['acknowledged_devices_json'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [envelope.entityType.name, envelope.entityId],
        limit: 1,
      );
      final acknowledgedDevices = existingTombstones.isEmpty
          ? <String>{}
          : (jsonDecode(
                  existingTombstones.single['acknowledged_devices_json']!
                      as String,
                )
                as List<dynamic>)
              .whereType<String>()
              .toSet();
      acknowledgedDevices.add(envelope.deviceId);
      final sortedAcknowledgements = acknowledgedDevices.toList()..sort();
      await database.insert('sync_tombstones', {
        'entity_type': envelope.entityType.name,
        'entity_id': envelope.entityId,
        'revision': envelope.revision,
        'deleted_at': envelope.updatedAt.toUtc().millisecondsSinceEpoch,
        'device_id': envelope.deviceId,
        'payload_hash': envelope.payloadHash,
        'purge_after': envelope.updatedAt
            .toUtc()
            .add(tombstoneRetention)
            .millisecondsSinceEpoch,
        'acknowledged_devices_json': jsonEncode(sortedAcknowledgements),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await database.delete(
        'sync_tombstones',
        where: 'entity_type = ? AND entity_id = ? AND revision < ?',
        whereArgs: [
          envelope.entityType.name,
          envelope.entityId,
          envelope.revision,
        ],
      );
    }
  }

  Future<void> _insertConflict(
    DatabaseExecutor database,
    SyncConflict conflict,
  ) async {
    await database.insert('sync_conflicts', {
      'id': conflict.id,
      'entity_type': conflict.entityType.name,
      'entity_id': conflict.entityId,
      'field_names_json': jsonEncode(conflict.fieldNames),
      'local_payload_json': jsonEncode(conflict.localPayload),
      'incoming_payload_json': jsonEncode(conflict.incomingPayload),
      'local_revision': conflict.localRevision,
      'incoming_revision': conflict.incomingRevision,
      'created_at': conflict.createdAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  SyncEnvelope _rowEnvelope(
    Map<String, Object?> row, {
    String timestampColumn = 'updated_at',
  }) => SyncEnvelope(
    entityType: SyncEntityType.values.byName(row['entity_type']! as String),
    entityId: row['entity_id']! as String,
    revision: row['revision']! as int,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row[timestampColumn]! as int,
      isUtc: true,
    ),
    deviceId: row['device_id']! as String,
    operation: SyncOperation.values.byName(row['operation']! as String),
    payload: jsonDecode(row['payload_json']! as String) as Map<String, Object?>,
    payloadHash: row['payload_hash']! as String,
  );

  SyncConflict _rowConflict(Map<String, Object?> row) => SyncConflict(
    id: row['id']! as String,
    entityType: SyncEntityType.values.byName(row['entity_type']! as String),
    entityId: row['entity_id']! as String,
    fieldNames: (jsonDecode(row['field_names_json']! as String) as List<dynamic>)
        .whereType<String>()
        .toList(growable: false),
    localPayload: jsonDecode(row['local_payload_json']! as String)
        as Map<String, Object?>,
    incomingPayload: jsonDecode(row['incoming_payload_json']! as String)
        as Map<String, Object?>,
    localRevision: row['local_revision']! as int,
    incomingRevision: row['incoming_revision']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at']! as int,
      isUtc: true,
    ),
  );
}
