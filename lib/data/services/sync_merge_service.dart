import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models/sync_models.dart';

class SyncMergeService {
  const SyncMergeService();

  SyncEnvelope createUpsert({
    required SyncEntityType entityType,
    required String entityId,
    required int revision,
    required DateTime updatedAt,
    required String deviceId,
    required Map<String, Object?> payload,
  }) {
    _validateIdentity(entityId, revision, deviceId);
    _validatePayload(payload);
    return SyncEnvelope(
      entityType: entityType,
      entityId: entityId,
      revision: revision,
      updatedAt: updatedAt.toUtc(),
      deviceId: deviceId,
      operation: SyncOperation.upsert,
      payload: payload,
      payloadHash: payloadHash(payload),
    );
  }

  SyncEnvelope createDelete({
    required SyncEntityType entityType,
    required String entityId,
    required int revision,
    required DateTime deletedAt,
    required String deviceId,
  }) {
    _validateIdentity(entityId, revision, deviceId);
    return SyncEnvelope(
      entityType: entityType,
      entityId: entityId,
      revision: revision,
      updatedAt: deletedAt.toUtc(),
      deviceId: deviceId,
      operation: SyncOperation.delete,
      payload: const {},
      payloadHash: payloadHash(const {}),
    );
  }

  SyncMergeOutcome merge(SyncEnvelope? local, SyncEnvelope incoming) {
    _validateEnvelope(incoming);
    if (local == null) {
      return SyncMergeOutcome(
        disposition: SyncMergeDisposition.applied,
        envelope: incoming,
      );
    }
    _validateEnvelope(local);
    if (local.entityType != incoming.entityType ||
        local.entityId != incoming.entityId) {
      throw const FormatException('不能合并不同的同步实体。');
    }
    if (local.operation == incoming.operation &&
        local.payloadHash == incoming.payloadHash) {
      final winner = _compareVersion(local, incoming) >= 0 ? local : incoming;
      return SyncMergeOutcome(
        disposition: identical(winner, local)
            ? SyncMergeDisposition.ignored
            : SyncMergeDisposition.applied,
        envelope: winner,
      );
    }
    if (local.isDeleted) {
      if (incoming.revision <= local.revision) {
        return SyncMergeOutcome(
          disposition: SyncMergeDisposition.ignored,
          envelope: local,
        );
      }
      return SyncMergeOutcome(
        disposition: SyncMergeDisposition.applied,
        envelope: incoming,
      );
    }
    if (incoming.isDeleted) {
      if (incoming.revision < local.revision) {
        return SyncMergeOutcome(
          disposition: SyncMergeDisposition.ignored,
          envelope: local,
        );
      }
      return SyncMergeOutcome(
        disposition: SyncMergeDisposition.applied,
        envelope: incoming,
      );
    }
    if (incoming.revision != local.revision) {
      final winner = incoming.revision > local.revision ? incoming : local;
      return SyncMergeOutcome(
        disposition: identical(winner, local)
            ? SyncMergeDisposition.ignored
            : SyncMergeDisposition.applied,
        envelope: winner,
      );
    }

    final conflictFields = _longTextFields(incoming.entityType)
        .where((field) => local.payload[field] != incoming.payload[field])
        .where(
          (field) =>
              local.payload.containsKey(field) &&
              incoming.payload.containsKey(field),
        )
        .toList(growable: false);
    if (conflictFields.isNotEmpty) {
      final conflict = SyncConflict(
        id: _conflictId(local, incoming),
        entityType: local.entityType,
        entityId: local.entityId,
        fieldNames: conflictFields,
        localPayload: local.payload,
        incomingPayload: incoming.payload,
        localRevision: local.revision,
        incomingRevision: incoming.revision,
        createdAt: _later(local.updatedAt, incoming.updatedAt),
      );
      return SyncMergeOutcome(
        disposition: SyncMergeDisposition.conflict,
        envelope: local,
        conflict: conflict,
      );
    }

    final winner = _compareTieBreak(local, incoming) >= 0 ? local : incoming;
    final mergedPayload = Map<String, Object?>.from(winner.payload);
    for (final field in _listFields(incoming.entityType)) {
      final merged = _mergeStableList(local.payload[field], incoming.payload[field]);
      if (merged != null) mergedPayload[field] = merged;
    }
    if (_mapsEqual(mergedPayload, winner.payload)) {
      return SyncMergeOutcome(
        disposition: identical(winner, local)
            ? SyncMergeDisposition.ignored
            : SyncMergeDisposition.applied,
        envelope: winner,
      );
    }
    final merged = createUpsert(
      entityType: local.entityType,
      entityId: local.entityId,
      revision: local.revision + 1,
      updatedAt: _later(local.updatedAt, incoming.updatedAt),
      deviceId: local.deviceId.compareTo(incoming.deviceId) >= 0
          ? local.deviceId
          : incoming.deviceId,
      payload: mergedPayload,
    );
    return SyncMergeOutcome(
      disposition: SyncMergeDisposition.applied,
      envelope: merged,
    );
  }

  String payloadHash(Map<String, Object?> payload) =>
      sha256.convert(utf8.encode(_canonicalJson(payload))).toString();

  void _validateEnvelope(SyncEnvelope envelope) {
    _validateIdentity(envelope.entityId, envelope.revision, envelope.deviceId);
    if (envelope.isDeleted && envelope.payload.isNotEmpty) {
      throw const FormatException('删除墓碑不能携带实体 payload。');
    }
    _validatePayload(envelope.payload);
    if (payloadHash(envelope.payload) != envelope.payloadHash) {
      throw const FormatException('同步实体 payload hash 校验失败。');
    }
  }

  void _validateIdentity(String entityId, int revision, String deviceId) {
    if (entityId.trim().isEmpty || deviceId.trim().isEmpty || revision <= 0) {
      throw const FormatException('同步实体身份或 revision 无效。');
    }
  }

  void _validatePayload(Map<String, Object?> payload) {
    const forbiddenFragments = {
      'apikey',
      'password',
      'token',
      'cookie',
      'secret',
      'authorization',
      'credential',
      'systemfontpath',
      'fulltext',
      'rawtext',
      'completetext',
      'sourcecontent',
      'fullcontent',
    };
    void visit(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key is! String) {
            throw const FormatException('同步 payload 的对象键必须是字符串。');
          }
          final key = (entry.key as String)
              .replaceAll(RegExp(r'[_-]'), '')
              .toLowerCase();
          if (forbiddenFragments.any(key.contains)) {
            throw FormatException('同步 payload 禁止包含敏感字段：${entry.key}');
          }
          visit(entry.value);
        }
      } else if (value is List) {
        for (final item in value) {
          visit(item);
        }
      } else if (value is! String &&
          value is! num &&
          value is! bool &&
          value != null) {
        throw const FormatException('同步 payload 只能包含 JSON 值。');
      }
    }
    visit(payload);
  }

  int _compareVersion(SyncEnvelope left, SyncEnvelope right) {
    final revision = left.revision.compareTo(right.revision);
    return revision == 0 ? _compareTieBreak(left, right) : revision;
  }

  int _compareTieBreak(SyncEnvelope left, SyncEnvelope right) {
    final timestamp = left.updatedAt.compareTo(right.updatedAt);
    return timestamp == 0 ? left.deviceId.compareTo(right.deviceId) : timestamp;
  }

  Set<String> _longTextFields(SyncEntityType type) => switch (type) {
    SyncEntityType.annotation => const {'note'},
    SyncEntityType.globalNote => const {'content'},
    SyncEntityType.chatMessage => const {'content'},
    _ => const {},
  };

  Set<String> _listFields(SyncEntityType type) => switch (type) {
    SyncEntityType.bookMetadata => const {'tags'},
    _ => const {},
  };

  List<Object?>? _mergeStableList(Object? left, Object? right) {
    if (left is! List || right is! List) return null;
    final values = <String, Object?>{};
    for (final value in [...left, ...right]) {
      final key = value is Map && value['id'] != null
          ? value['id'].toString()
          : _canonicalJson(value);
      values[key] = value;
    }
    final keys = values.keys.toList()..sort();
    return [for (final key in keys) values[key]];
  }

  String _conflictId(SyncEnvelope local, SyncEnvelope incoming) {
    final hashes = [local.payloadHash, incoming.payloadHash]..sort();
    return sha256
        .convert(
          utf8.encode(
            '${local.entityType.name}\u0000${local.entityId}\u0000${hashes.join('\u0000')}',
          ),
        )
        .toString();
  }

  String _canonicalJson(Object? value) {
    Object? canonical(Object? source) {
      if (source is Map) {
        final keys = source.keys.cast<String>().toList()..sort();
        return <String, Object?>{
          for (final key in keys) key: canonical(source[key]),
        };
      }
      if (source is List) return source.map(canonical).toList();
      return source;
    }
    return jsonEncode(canonical(value));
  }

  bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) =>
      _canonicalJson(left) == _canonicalJson(right);

  DateTime _later(DateTime left, DateTime right) =>
      left.isAfter(right) ? left : right;
}
