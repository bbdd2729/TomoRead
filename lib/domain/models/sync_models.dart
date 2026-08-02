enum SyncEntityType {
  bookMetadata,
  readingProgress,
  bookmark,
  annotation,
  annotationTag,
  globalNote,
  readingSettings,
  textProjectionRule,
  chatThread,
  chatMessage,
  importedFont,
}

enum SyncOperation { upsert, delete }

class SyncEnvelope {
  SyncEnvelope({
    required this.entityType,
    required this.entityId,
    required this.revision,
    required this.updatedAt,
    required this.deviceId,
    required this.operation,
    required Map<String, Object?> payload,
    required this.payloadHash,
  }) : payload = Map.unmodifiable(payload);

  final SyncEntityType entityType;
  final String entityId;
  final int revision;
  final DateTime updatedAt;
  final String deviceId;
  final SyncOperation operation;
  final Map<String, Object?> payload;
  final String payloadHash;

  bool get isDeleted => operation == SyncOperation.delete;

  Map<String, Object?> toJson() => {
    'entityType': entityType.name,
    'entityId': entityId,
    'revision': revision,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'operation': operation.name,
    'payload': payload,
    'payloadHash': payloadHash,
  };

  factory SyncEnvelope.fromJson(Map<String, Object?> json) {
    final payload = json['payload'];
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('同步实体 payload 必须是对象。');
    }
    final revision = json['revision'];
    if (revision is! int || revision <= 0) {
      throw const FormatException('同步实体 revision 无效。');
    }
    return SyncEnvelope(
      entityType: SyncEntityType.values.byName(json['entityType']! as String),
      entityId: json['entityId']! as String,
      revision: revision,
      updatedAt: DateTime.parse(json['updatedAt']! as String).toUtc(),
      deviceId: json['deviceId']! as String,
      operation: SyncOperation.values.byName(json['operation']! as String),
      payload: payload,
      payloadHash: json['payloadHash']! as String,
    );
  }
}

class SyncChange {
  const SyncChange({required this.sequence, required this.envelope});

  final int sequence;
  final SyncEnvelope envelope;
}

class SyncConflict {
  SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required List<String> fieldNames,
    required Map<String, Object?> localPayload,
    required Map<String, Object?> incomingPayload,
    required this.localRevision,
    required this.incomingRevision,
    required this.createdAt,
  }) : fieldNames = List.unmodifiable(fieldNames),
       localPayload = Map.unmodifiable(localPayload),
       incomingPayload = Map.unmodifiable(incomingPayload);

  final String id;
  final SyncEntityType entityType;
  final String entityId;
  final List<String> fieldNames;
  final Map<String, Object?> localPayload;
  final Map<String, Object?> incomingPayload;
  final int localRevision;
  final int incomingRevision;
  final DateTime createdAt;
}

enum SyncMergeDisposition { applied, ignored, conflict }

class SyncMergeOutcome {
  const SyncMergeOutcome({
    required this.disposition,
    required this.envelope,
    this.conflict,
  });

  final SyncMergeDisposition disposition;
  final SyncEnvelope envelope;
  final SyncConflict? conflict;
}

class SyncStateSummary {
  const SyncStateSummary({
    required this.backendId,
    required this.remoteId,
    required this.updatedAt,
    this.cursor,
    this.lastSuccessAt,
    this.lastSummaryJson,
    this.errorCode,
    this.credentialRef,
  });

  final String backendId;
  final String remoteId;
  final String? cursor;
  final DateTime? lastSuccessAt;
  final String? lastSummaryJson;
  final String? errorCode;
  final String? credentialRef;
  final DateTime updatedAt;
}
