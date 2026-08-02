import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

enum StorageCategory {
  database,
  managedBooks,
  covers,
  epubCache,
  textProjectionCache,
  wordCloudCache,
  visualExportTemporary,
  importStaging,
  importedFonts,
  backups,
}

class StorageCategoryReport {
  const StorageCategoryReport({
    required this.category,
    required this.fileCount,
    required this.totalBytes,
    required this.orphanCount,
    required this.regenerable,
  });

  final StorageCategory category;
  final int fileCount;
  final int totalBytes;
  final int orphanCount;
  final bool regenerable;
}

class StorageCleanupPlan {
  const StorageCleanupPlan({
    required this.categories,
    required this.bytes,
    required this.itemCount,
    this.includeConfirmedOrphans = false,
  });

  final List<StorageCategory> categories;
  final int bytes;
  final int itemCount;
  final bool includeConfirmedOrphans;
}

class StorageCleanupRecord {
  const StorageCleanupRecord({
    required this.createdAt,
    required this.categories,
    required this.itemCount,
    required this.bytes,
    required this.succeeded,
  });

  final DateTime createdAt;
  final List<StorageCategory> categories;
  final int itemCount;
  final int bytes;
  final bool succeeded;

  Map<String, Object> toJson() => {
    'createdAt': createdAt.toUtc().toIso8601String(),
    'categories': categories.map((value) => value.name).toList(),
    'itemCount': itemCount,
    'bytes': bytes,
    'succeeded': succeeded,
  };

  factory StorageCleanupRecord.fromJson(Map<String, Object?> json) =>
      StorageCleanupRecord(
        createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
        categories: (json['categories']! as List<dynamic>)
            .map(
              (value) => StorageCategory.values.byName(value! as String),
            )
            .toList(growable: false),
        itemCount: json['itemCount']! as int,
        bytes: json['bytes']! as int,
        succeeded: json['succeeded']! as bool,
      );
}

class StorageDiagnosticsService {
  const StorageDiagnosticsService({this.database, this.rootProvider});

  final AppDatabase? database;
  final Future<Directory> Function()? rootProvider;

  Future<List<StorageCategoryReport>> inspect() async {
    final root = await _root();
    final locations = _locations(root);
    final references = await _managedReferences();
    final reports = <StorageCategoryReport>[];
    for (final category in _directoryCategories) {
      final summary = await _directorySummary(
        locations[category]!,
        references: switch (category) {
          StorageCategory.managedBooks => references.bookPaths,
          StorageCategory.covers => references.coverPaths,
          StorageCategory.importedFonts => references.fontPaths,
          _ => null,
        },
      );
      reports.add(
        StorageCategoryReport(
          category: category,
          fileCount: summary.fileCount,
          totalBytes: summary.totalBytes,
          orphanCount: summary.orphanFiles.length,
          regenerable: _regenerable.contains(category),
        ),
      );
    }
    final tableReports = await _databaseCacheReports();
    reports.addAll(tableReports);
    reports.sort((left, right) => left.category.index.compareTo(right.category.index));
    return reports;
  }

  Future<StorageCleanupPlan> planCleanup(
    Iterable<StorageCategory> requested, {
    bool includeConfirmedOrphans = false,
  }) async {
    final requestedSet = requested.toSet();
    final safeCategories = requestedSet
        .where(
          (category) =>
              _regenerable.contains(category) ||
              (includeConfirmedOrphans && _orphanEligible.contains(category)),
        )
        .toList(growable: false);
    final reports = await inspect();
    var bytes = 0;
    var itemCount = 0;
    for (final report in reports.where(
      (report) => safeCategories.contains(report.category),
    )) {
      if (_regenerable.contains(report.category)) {
        bytes += report.totalBytes;
        itemCount += report.fileCount;
      } else if (includeConfirmedOrphans) {
        final orphanSummary = await _orphanSummary(report.category);
        bytes += orphanSummary.totalBytes;
        itemCount += orphanSummary.fileCount;
      }
    }
    return StorageCleanupPlan(
      categories: safeCategories,
      bytes: bytes,
      itemCount: itemCount,
      includeConfirmedOrphans: includeConfirmedOrphans,
    );
  }

  Future<StorageCleanupRecord> executeCleanup(StorageCleanupPlan plan) async {
    final root = await _root();
    var succeeded = false;
    try {
      final locations = _locations(root);
      for (final category in plan.categories) {
        if (_directoryRegenerable.contains(category)) {
          final target = locations[category];
          if (target == null || !_inside(root, target.path)) continue;
          if (await target.exists()) await target.delete(recursive: true);
        }
      }
      final raw = database == null ? null : await database!.database;
      if (raw != null) {
        await raw.transaction((transaction) async {
          if (plan.categories.contains(StorageCategory.textProjectionCache)) {
            await transaction.delete('content_chunks');
            await transaction.delete('content_index_states');
          }
          if (plan.categories.contains(StorageCategory.wordCloudCache)) {
            await transaction.delete('word_cloud_cache');
          }
        });
      }
      if (plan.includeConfirmedOrphans) {
        for (final category in plan.categories.where(_orphanEligible.contains)) {
          final summary = await _orphanSummary(category);
          for (final file in summary.orphanFiles) {
            if (_inside(root, file.path) && await file.exists()) {
              await file.delete();
            }
          }
        }
      }
      succeeded = true;
      return StorageCleanupRecord(
        createdAt: DateTime.now().toUtc(),
        categories: plan.categories,
        itemCount: plan.itemCount,
        bytes: plan.bytes,
        succeeded: true,
      );
    } finally {
      await _appendRecord(
        root,
        StorageCleanupRecord(
          createdAt: DateTime.now().toUtc(),
          categories: plan.categories,
          itemCount: plan.itemCount,
          bytes: plan.bytes,
          succeeded: succeeded,
        ),
      );
    }
  }

  Future<List<StorageCleanupRecord>> recentCleanupRecords({
    int limit = 20,
  }) async {
    final file = _recordFile(await _root());
    if (!await file.exists()) return const [];
    final records = <StorageCleanupRecord>[];
    for (final line in await file.readAsLines()) {
      try {
        final value = jsonDecode(line);
        if (value is Map<String, dynamic>) {
          records.add(StorageCleanupRecord.fromJson(value));
        }
      } on Object {
        // A damaged diagnostic line must not block storage inspection.
      }
    }
    return records.reversed.take(limit).toList(growable: false);
  }

  Future<List<StorageCategoryReport>> _databaseCacheReports() async {
    final raw = database == null ? null : await database!.database;
    if (raw == null) {
      return const [
        StorageCategoryReport(
          category: StorageCategory.textProjectionCache,
          fileCount: 0,
          totalBytes: 0,
          orphanCount: 0,
          regenerable: true,
        ),
        StorageCategoryReport(
          category: StorageCategory.wordCloudCache,
          fileCount: 0,
          totalBytes: 0,
          orphanCount: 0,
          regenerable: true,
        ),
      ];
    }
    final chunkRows = await raw.rawQuery('''
      SELECT COUNT(*) AS item_count,
        COALESCE(SUM(length(text_content) + length(locator_start) +
          length(locator_end)), 0) AS bytes
      FROM content_chunks
    ''');
    final wordCloudRows = await raw.rawQuery('''
      SELECT COUNT(*) AS item_count,
        COALESCE(SUM(length(payload_json)), 0) AS bytes
      FROM word_cloud_cache
    ''');
    return [
      _tableReport(StorageCategory.textProjectionCache, chunkRows.single),
      _tableReport(StorageCategory.wordCloudCache, wordCloudRows.single),
    ];
  }

  StorageCategoryReport _tableReport(
    StorageCategory category,
    Map<String, Object?> row,
  ) => StorageCategoryReport(
    category: category,
    fileCount: (row['item_count']! as num).toInt(),
    totalBytes: (row['bytes']! as num).toInt(),
    orphanCount: 0,
    regenerable: true,
  );

  Future<_ManagedReferences> _managedReferences() async {
    final raw = database == null ? null : await database!.database;
    if (raw == null) return const _ManagedReferences();
    final books = await raw.query(
      'books',
      columns: ['file_path', 'cover_path'],
    );
    final fonts = await raw.query('imported_fonts', columns: ['file_path']);
    return _ManagedReferences(
      bookPaths: books
          .map((row) => row['file_path'] as String?)
          .whereType<String>()
          .map(path.normalize)
          .toSet(),
      coverPaths: books
          .map((row) => row['cover_path'] as String?)
          .whereType<String>()
          .map(path.normalize)
          .toSet(),
      fontPaths: fonts
          .map((row) => row['file_path'] as String?)
          .whereType<String>()
          .map(path.normalize)
          .toSet(),
    );
  }

  Future<_DirectorySummary> _orphanSummary(StorageCategory category) async {
    final root = await _root();
    final references = await _managedReferences();
    return _directorySummary(
      _locations(root)[category]!,
      references: switch (category) {
        StorageCategory.managedBooks => references.bookPaths,
        StorageCategory.covers => references.coverPaths,
        StorageCategory.importedFonts => references.fontPaths,
        _ => const <String>{},
      },
      orphansOnly: true,
    );
  }

  Future<_DirectorySummary> _directorySummary(
    Directory directory, {
    Set<String>? references,
    bool orphansOnly = false,
  }) async {
    var count = 0;
    var bytes = 0;
    final orphans = <File>[];
    if (await directory.exists()) {
      await for (final child in directory.list(recursive: true)) {
        if (child is! File) continue;
        final normalized = path.normalize(child.absolute.path);
        final orphan = references != null && !references.contains(normalized);
        if (orphan) orphans.add(child);
        if (!orphansOnly || orphan) {
          count++;
          bytes += await child.length();
        }
      }
    }
    return _DirectorySummary(
      fileCount: count,
      totalBytes: bytes,
      orphanFiles: orphans,
    );
  }

  Future<void> _appendRecord(
    Directory root,
    StorageCleanupRecord record,
  ) async {
    final file = _recordFile(root);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  File _recordFile(Directory root) => File(
    path.join(root.path, 'operations', 'storage-cleanup.jsonl'),
  );

  Future<Directory> _root() => rootProvider == null
      ? getApplicationSupportDirectory()
      : rootProvider!();

  bool _inside(Directory root, String target) => path.isWithin(
    path.normalize(root.absolute.path),
    path.normalize(File(target).absolute.path),
  );

  Map<StorageCategory, Directory> _locations(Directory root) => {
    StorageCategory.database: Directory(path.join(root.path, 'database')),
    StorageCategory.managedBooks: Directory(
      path.join(root.path, 'library', 'books'),
    ),
    StorageCategory.covers: Directory(path.join(root.path, 'library', 'covers')),
    StorageCategory.epubCache: Directory(
      path.join(root.path, 'library', 'extracted'),
    ),
    StorageCategory.visualExportTemporary: Directory(
      path.join(root.path, 'cache', 'visual-exports'),
    ),
    StorageCategory.importStaging: Directory(
      path.join(root.path, 'library', 'imports'),
    ),
    StorageCategory.importedFonts: Directory(path.join(root.path, 'fonts')),
    StorageCategory.backups: Directory(path.join(root.path, 'backups')),
  };

  static const _directoryCategories = [
    StorageCategory.database,
    StorageCategory.managedBooks,
    StorageCategory.covers,
    StorageCategory.epubCache,
    StorageCategory.visualExportTemporary,
    StorageCategory.importStaging,
    StorageCategory.importedFonts,
    StorageCategory.backups,
  ];

  static const _directoryRegenerable = {
    StorageCategory.epubCache,
    StorageCategory.visualExportTemporary,
    StorageCategory.importStaging,
  };

  static const _regenerable = {
    ..._directoryRegenerable,
    StorageCategory.textProjectionCache,
    StorageCategory.wordCloudCache,
  };

  static const _orphanEligible = {
    StorageCategory.managedBooks,
    StorageCategory.covers,
    StorageCategory.importedFonts,
  };
}

class _ManagedReferences {
  const _ManagedReferences({
    this.bookPaths = const {},
    this.coverPaths = const {},
    this.fontPaths = const {},
  });

  final Set<String> bookPaths;
  final Set<String> coverPaths;
  final Set<String> fontPaths;
}

class _DirectorySummary {
  const _DirectorySummary({
    required this.fileCount,
    required this.totalBytes,
    required this.orphanFiles,
  });

  final int fileCount;
  final int totalBytes;
  final List<File> orphanFiles;
}
