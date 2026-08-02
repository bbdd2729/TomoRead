class BackupManifestEntry {
  const BackupManifestEntry({
    required this.path,
    required this.kind,
    required this.size,
    required this.sha256,
  });

  final String path;
  final String kind;
  final int size;
  final String sha256;

  Map<String, Object> toJson() => {
    'path': path,
    'kind': kind,
    'size': size,
    'sha256': sha256,
  };

  factory BackupManifestEntry.fromJson(Map<String, Object?> json) =>
      BackupManifestEntry(
        path: _requiredString(json, 'path'),
        kind: _requiredString(json, 'kind'),
        size: _requiredInt(json, 'size'),
        sha256: _requiredString(json, 'sha256'),
      );
}

class BackupManifest {
  const BackupManifest({
    required this.createdAt,
    required this.appVersion,
    required this.databaseSchemaVersion,
    required this.deviceId,
    required this.includesBooks,
    required this.includesFonts,
    required this.contentSha256,
    required this.entries,
  });

  static const format = 'tomoread-backup-v1';
  static const schemaVersion = 1;

  final DateTime createdAt;
  final String appVersion;
  final int databaseSchemaVersion;
  final String deviceId;
  final bool includesBooks;
  final bool includesFonts;
  final String contentSha256;
  final List<BackupManifestEntry> entries;

  Map<String, Object> toJson() => {
    'format': format,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'appVersion': appVersion,
    'databaseSchemaVersion': databaseSchemaVersion,
    'deviceId': deviceId,
    'includesBooks': includesBooks,
    'includesFonts': includesFonts,
    'contentSha256': contentSha256,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    if (json['format'] != format || json['schemaVersion'] != schemaVersion) {
      throw const FormatException('不支持的 TomoRead 备份格式或版本。');
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List<dynamic>) {
      throw const FormatException('备份清单缺少条目列表。');
    }
    return BackupManifest(
      createdAt: DateTime.parse(_requiredString(json, 'createdAt')).toUtc(),
      appVersion: _requiredString(json, 'appVersion'),
      databaseSchemaVersion: _requiredInt(json, 'databaseSchemaVersion'),
      deviceId: _requiredString(json, 'deviceId'),
      includesBooks: _requiredBool(json, 'includesBooks'),
      includesFonts: _requiredBool(json, 'includesFonts'),
      contentSha256: _requiredString(json, 'contentSha256'),
      entries: rawEntries.map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('备份清单条目格式无效。');
        }
        return BackupManifestEntry.fromJson(value);
      }).toList(growable: false),
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('备份清单字段 $key 无效。');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('备份清单字段 $key 无效。');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('备份清单字段 $key 无效。');
  }
  return value;
}
