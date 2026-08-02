import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/backup_manifest.dart';
import '../database/app_database.dart';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupOptions {
  const BackupOptions({this.includeBooks = true, this.includeFonts = true});

  final bool includeBooks;
  final bool includeFonts;
}

enum BackupPhase {
  preparing,
  snapshotting,
  collectingFiles,
  writingArchive,
  verifying,
  completed,
}

class BackupProgress {
  const BackupProgress({
    required this.phase,
    this.completed = 0,
    this.total = 0,
  });

  final BackupPhase phase;
  final int completed;
  final int total;
}

typedef BackupProgressCallback = void Function(BackupProgress progress);

class BackupCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const BackupException('备份已取消。');
  }
}

class BackupService {
  const BackupService({
    required this.database,
    required this.appVersion,
    required this.deviceId,
    this.rootProvider,
  });

  final AppDatabase database;
  final String appVersion;
  final String deviceId;
  final Future<Directory> Function()? rootProvider;

  Future<BackupManifest> create({
    required String destinationPath,
    BackupOptions options = const BackupOptions(),
    BackupProgressCallback? onProgress,
    BackupCancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? BackupCancellationToken();
    final destination = File(path.normalize(destinationPath));
    final parent = destination.parent;
    await parent.create(recursive: true);
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory(
      path.join(parent.path, '.tomoread-backup-staging-$nonce'),
    );
    final partial = File('${destination.path}.partial-$nonce');
    await staging.create(recursive: true);
    try {
      onProgress?.call(
        const BackupProgress(phase: BackupPhase.preparing),
      );
      token.throwIfCancelled();
      final root = rootProvider == null
          ? await getApplicationSupportDirectory()
          : await rootProvider!();
      final stagedDatabase = File(
        path.join(staging.path, 'database', 'tomoread.db'),
      );
      onProgress?.call(
        const BackupProgress(phase: BackupPhase.snapshotting),
      );
      await database.createSnapshot(stagedDatabase.path);

      final logicalPaths = await _stageManagedFiles(
        root: root,
        staging: staging,
        options: options,
        token: token,
        onProgress: onProgress,
      );
      await database.prepareSnapshotForBackup(
        snapshotPath: stagedDatabase.path,
        bookPaths: logicalPaths.bookPaths,
        coverPaths: logicalPaths.coverPaths,
        fontPaths: logicalPaths.fontPaths,
      );
      final snapshot = await database.inspectSnapshot(stagedDatabase.path);
      if (snapshot.schemaVersion != AppDatabase.schemaVersion) {
        throw const BackupException('数据库快照版本与应用版本不一致。');
      }

      token.throwIfCancelled();
      final entries = await _manifestEntries(staging);
      final manifest = BackupManifest(
        createdAt: DateTime.now().toUtc(),
        appVersion: appVersion,
        databaseSchemaVersion: snapshot.schemaVersion,
        deviceId: deviceId,
        includesBooks: options.includeBooks,
        includesFonts: options.includeFonts,
        contentSha256: _contentDigest(entries),
        entries: entries,
      );
      await File(path.join(staging.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        flush: true,
      );
      await File(path.join(staging.path, 'checksums.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          for (final entry in entries) entry.path: entry.sha256,
        }),
        flush: true,
      );

      token.throwIfCancelled();
      onProgress?.call(
        const BackupProgress(phase: BackupPhase.writingArchive),
      );
      final archive = Archive();
      await for (final entity in staging.list(recursive: true)) {
        if (entity is! File) continue;
        final relative = _archivePath(entity.path, from: staging.path);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relative, bytes.length, bytes));
      }
      await partial.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      token.throwIfCancelled();
      onProgress?.call(
        const BackupProgress(phase: BackupPhase.verifying),
      );
      final verified = await validate(partial.path);
      if (verified.entries.length != entries.length) {
        throw const BackupException('备份写入后的条目校验不一致。');
      }
      await _replaceAtomically(partial, destination);
      onProgress?.call(
        BackupProgress(
          phase: BackupPhase.completed,
          completed: entries.length,
          total: entries.length,
        ),
      );
      return manifest;
    } on BackupException {
      rethrow;
    } on Object catch (error) {
      throw BackupException('无法创建备份：$error');
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<BackupManifest> validate(String archivePath) async {
    final source = File(archivePath);
    if (!await source.exists()) throw const BackupException('找不到备份文件。');
    try {
      final archive = ZipDecoder().decodeBytes(await source.readAsBytes());
      final archiveFiles = archive.files.where((entry) => entry.isFile).toList();
      if (archiveFiles.any((entry) => !_safeArchivePath(entry.name))) {
        throw const BackupException('备份包含不安全的文件路径。');
      }
      final files = <String, ArchiveFile>{
        for (final file in archiveFiles) file.name: file,
      };
      if (files.length != archiveFiles.length) {
        throw const BackupException('备份包含重复的文件路径。');
      }
      final manifestFile = files['manifest.json'];
      final checksumsFile = files['checksums.json'];
      if (manifestFile == null || checksumsFile == null) {
        throw const BackupException('备份缺少 manifest.json 或 checksums.json。');
      }
      final manifest = BackupManifest.fromJson(
        _jsonObject(utf8.decode(_archiveBytes(manifestFile))),
      );
      if (manifest.databaseSchemaVersion > AppDatabase.schemaVersion) {
        throw const BackupException('备份来自更高版本，当前应用无法安全恢复。');
      }
      final checksums = _jsonObject(
        utf8.decode(_archiveBytes(checksumsFile)),
      );
      final listedPaths = <String>{};
      for (final entry in manifest.entries) {
        if (!listedPaths.add(entry.path) ||
            !_safeArchivePath(entry.path) ||
            !_entryKindMatchesPath(entry)) {
          throw const BackupException('备份清单包含无效或重复的条目。');
        }
        final file = files[entry.path];
        if (file == null || file.size != entry.size) {
          throw BackupException('备份条目缺失或大小不一致：${entry.path}');
        }
        final digest = sha256.convert(_archiveBytes(file)).toString();
        if (digest != entry.sha256 || checksums[entry.path] != entry.sha256) {
          throw BackupException('备份条目校验失败：${entry.path}');
        }
      }
      if (checksums.length != listedPaths.length ||
          files.keys.any(
            (name) =>
                name != 'manifest.json' &&
                name != 'checksums.json' &&
                !listedPaths.contains(name),
          )) {
        throw const BackupException('备份文件与清单不一致。');
      }
      if (manifest.contentSha256 != _contentDigest(manifest.entries)) {
        throw const BackupException('备份清单的内容摘要无效。');
      }
      if (!manifest.entries.any(
        (entry) => entry.path == 'database/tomoread.db',
      )) {
        throw const BackupException('备份缺少数据库快照。');
      }
      return manifest;
    } on BackupException {
      rethrow;
    } on Object catch (error) {
      throw BackupException('备份文件损坏或格式无效：$error');
    }
  }

  Future<_BackupLogicalPaths> _stageManagedFiles({
    required Directory root,
    required Directory staging,
    required BackupOptions options,
    required BackupCancellationToken token,
    BackupProgressCallback? onProgress,
  }) async {
    final raw = await database.database;
    final bookRows = await raw.query(
      'books',
      columns: ['id', 'file_hash', 'file_path', 'cover_path'],
    );
    final fontRows = await raw.query(
      'imported_fonts',
      columns: ['id', 'file_hash', 'file_path', 'format'],
    );
    final total =
        (options.includeBooks ? bookRows.length * 2 : 0) +
        (options.includeFonts ? fontRows.length : 0);
    var completed = 0;
    final bookPaths = <String, String>{};
    final coverPaths = <String, String>{};
    final fontPaths = <String, String>{};
    final managedBooks = Directory(path.join(root.path, 'library', 'books'));
    final managedCovers = Directory(path.join(root.path, 'library', 'covers'));
    final managedFonts = Directory(path.join(root.path, 'fonts'));
    void report() => onProgress?.call(
      BackupProgress(
        phase: BackupPhase.collectingFiles,
        completed: completed,
        total: total,
      ),
    );

    report();
    if (options.includeBooks) {
      for (final row in bookRows) {
        token.throwIfCancelled();
        final id = _safeSegment(row['id']! as String);
        final sourcePath = row['file_path'] as String?;
        if (sourcePath != null) {
          final source = File(sourcePath);
          final extension = _safeExtension(source.path);
          final hash = _safeSegment(
            (row['file_hash'] as String?) ?? path.basenameWithoutExtension(source.path),
          );
          final logicalPath = 'books/$id/$hash$extension';
          await _stageManagedFile(
            source: source,
            managedRoot: managedBooks,
            destination: File(
              path.joinAll([staging.path, ...logicalPath.split('/')]),
            ),
          );
          bookPaths[id] = logicalPath;
        }
        completed++;
        report();

        final coverPath = row['cover_path'] as String?;
        if (coverPath != null && await File(coverPath).exists()) {
          final logicalPath = 'covers/$id${_safeExtension(coverPath)}';
          await _stageManagedFile(
            source: File(coverPath),
            managedRoot: managedCovers,
            destination: File(
              path.joinAll([staging.path, ...logicalPath.split('/')]),
            ),
          );
          coverPaths[id] = logicalPath;
        }
        completed++;
        report();
      }
    }
    if (options.includeFonts) {
      for (final row in fontRows) {
        token.throwIfCancelled();
        final id = _safeSegment(row['id']! as String);
        final source = File(row['file_path']! as String);
        final hash = _safeSegment(row['file_hash']! as String);
        final extension = _safeExtension(source.path);
        final logicalPath = 'fonts/$id/$hash$extension';
        await _stageManagedFile(
          source: source,
          managedRoot: managedFonts,
          destination: File(
            path.joinAll([staging.path, ...logicalPath.split('/')]),
          ),
        );
        fontPaths[id] = logicalPath;
        completed++;
        report();
      }
    }
    return _BackupLogicalPaths(
      bookPaths: bookPaths,
      coverPaths: coverPaths,
      fontPaths: fontPaths,
    );
  }

  Future<void> _stageManagedFile({
    required File source,
    required Directory managedRoot,
    required File destination,
  }) async {
    if (!await source.exists()) {
      throw BackupException('托管文件不存在：${path.basename(source.path)}');
    }
    final normalizedRoot = path.normalize(managedRoot.absolute.path);
    final normalizedSource = path.normalize(source.absolute.path);
    if (!path.isWithin(normalizedRoot, normalizedSource)) {
      throw const BackupException('备份拒绝读取托管目录之外的文件。');
    }
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
  }

  Future<List<BackupManifestEntry>> _manifestEntries(Directory root) async {
    final entries = <BackupManifestEntry>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = _archivePath(entity.path, from: root.path);
      final kind = relative.startsWith('database/')
          ? 'database'
          : relative.startsWith('books/')
          ? 'book'
          : relative.startsWith('covers/')
          ? 'cover'
          : 'font';
      final digest = await sha256.bind(entity.openRead()).first;
      entries.add(
        BackupManifestEntry(
          path: relative,
          kind: kind,
          size: await entity.length(),
          sha256: digest.toString(),
        ),
      );
    }
    entries.sort((left, right) => left.path.compareTo(right.path));
    return entries;
  }

  Future<void> _replaceAtomically(File partial, File destination) async {
    final previous = File('${destination.path}.previous');
    if (await previous.exists()) await previous.delete();
    if (await destination.exists()) await destination.rename(previous.path);
    try {
      await partial.rename(destination.path);
      if (await previous.exists()) await previous.delete();
    } on Object {
      if (await previous.exists() && !await destination.exists()) {
        await previous.rename(destination.path);
      }
      rethrow;
    }
  }

  Map<String, Object?> _jsonObject(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON 根节点必须是对象。');
    }
    return decoded;
  }

  List<int> _archiveBytes(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) return content;
    throw const FormatException('备份条目不是普通文件。');
  }

  bool _entryKindMatchesPath(BackupManifestEntry entry) => switch (entry.kind) {
    'database' => entry.path == 'database/tomoread.db',
    'book' => entry.path.startsWith('books/'),
    'cover' => entry.path.startsWith('covers/'),
    'font' => entry.path.startsWith('fonts/'),
    _ => false,
  };

  bool _safeArchivePath(String value) {
    final normalized = path.posix.normalize(value);
    return value.isNotEmpty &&
        normalized == value &&
        !path.posix.isAbsolute(value) &&
        !value.contains('\\') &&
        !value.split('/').contains('..');
  }

  String _archivePath(String value, {required String from}) => path
      .relative(value, from: from)
      .split(path.separator)
      .join('/');

  String _safeSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed.contains('/') ||
        trimmed.contains('\\')) {
      throw const BackupException('托管条目标识无效。');
    }
    return trimmed;
  }

  String _safeExtension(String value) {
    final extension = path.extension(value).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) return '.bin';
    return extension;
  }

  String _contentDigest(List<BackupManifestEntry> entries) {
    final canonical = entries
        .map((entry) => '${entry.path}\u0000${entry.size}\u0000${entry.sha256}')
        .join('\n');
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

class _BackupLogicalPaths {
  const _BackupLogicalPaths({
    required this.bookPaths,
    required this.coverPaths,
    required this.fontPaths,
  });

  final Map<String, String> bookPaths;
  final Map<String, String> coverPaths;
  final Map<String, String> fontPaths;
}
