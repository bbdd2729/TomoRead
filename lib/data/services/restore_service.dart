import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/backup_manifest.dart';
import '../database/app_database.dart';
import 'backup_service.dart';

class RestoreException implements Exception {
  const RestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum RestorePhase {
  validating,
  extracting,
  validatingDatabase,
  creatingRollback,
  switchingData,
  reopeningDatabase,
  completed,
}

class RestoreProgress {
  const RestoreProgress({
    required this.phase,
    this.completed = 0,
    this.total = 0,
  });

  final RestorePhase phase;
  final int completed;
  final int total;
}

typedef RestoreProgressCallback = void Function(RestoreProgress progress);

class RestoreCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const RestoreException('恢复已取消。');
  }
}

class RestoreResult {
  const RestoreResult({
    required this.manifest,
    required this.rollbackBackupPath,
  });

  final BackupManifest manifest;
  final String rollbackBackupPath;
}

class RestoreService {
  const RestoreService({
    required this.database,
    required this.backupService,
    this.rootProvider,
  });

  final AppDatabase database;
  final BackupService backupService;
  final Future<Directory> Function()? rootProvider;

  Future<RestoreResult> restore({
    required String archivePath,
    RestoreProgressCallback? onProgress,
    RestoreCancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? RestoreCancellationToken();
    onProgress?.call(
      const RestoreProgress(phase: RestorePhase.validating),
    );
    final manifest = await backupService.validate(archivePath);
    token.throwIfCancelled();
    final root = rootProvider == null
        ? await getApplicationSupportDirectory()
        : await rootProvider!();
    await root.create(recursive: true);
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory(
      path.join(root.path, '.tomoread-restore-staging-$nonce'),
    );
    final previous = Directory(
      path.join(root.path, '.tomoread-restore-previous-$nonce'),
    );
    final rollbackBackup = File(
      path.join(
        root.path,
        'backups',
        'pre-restore-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.tomoread.zip',
      ),
    );
    var switched = false;
    try {
      await staging.create(recursive: true);
      onProgress?.call(
        RestoreProgress(
          phase: RestorePhase.extracting,
          total: manifest.entries.length,
        ),
      );
      final archive = ZipDecoder().decodeBytes(
        await File(archivePath).readAsBytes(),
      );
      final files = <String, ArchiveFile>{
        for (final file in archive.files.where((entry) => entry.isFile))
          file.name: file,
      };
      for (var index = 0; index < manifest.entries.length; index++) {
        token.throwIfCancelled();
        final entry = manifest.entries[index];
        final source = files[entry.path];
        if (source == null || !_safeArchivePath(entry.path)) {
          throw const RestoreException('备份条目在解压前验证后发生变化。');
        }
        final destination = File(
          path.joinAll([staging.path, ...entry.path.split('/')]),
        );
        final normalizedDestination = path.normalize(destination.path);
        if (!path.isWithin(path.normalize(staging.path), normalizedDestination)) {
          throw const RestoreException('备份解压路径越界。');
        }
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(_archiveBytes(source), flush: true);
        onProgress?.call(
          RestoreProgress(
            phase: RestorePhase.extracting,
            completed: index + 1,
            total: manifest.entries.length,
          ),
        );
      }

      token.throwIfCancelled();
      onProgress?.call(
        const RestoreProgress(phase: RestorePhase.validatingDatabase),
      );
      final stagedDatabase = File(
        path.join(staging.path, 'database', 'tomoread.db'),
      );
      final snapshot = await database.inspectSnapshot(stagedDatabase.path);
      if (snapshot.schemaVersion != manifest.databaseSchemaVersion ||
          snapshot.schemaVersion > AppDatabase.schemaVersion) {
        throw const RestoreException('数据库 schema 与备份清单不一致。');
      }
      final logicalPaths = _logicalPaths(manifest);
      if (!snapshot.bookIds.containsAll(logicalPaths.bookPaths.keys) ||
          !snapshot.bookIds.containsAll(logicalPaths.coverPaths.keys) ||
          !snapshot.fontIds.containsAll(logicalPaths.fontPaths.keys)) {
        throw const RestoreException('备份文件与数据库实体不一致。');
      }

      token.throwIfCancelled();
      onProgress?.call(
        const RestoreProgress(phase: RestorePhase.creatingRollback),
      );
      await backupService.create(destinationPath: rollbackBackup.path);

      token.throwIfCancelled();
      onProgress?.call(
        const RestoreProgress(phase: RestorePhase.switchingData),
      );
      await previous.create(recursive: true);
      await database.close();
      final databasePath = await database.databasePath;
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        final sidecar = File('$databasePath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      final swaps = <_RestoreSwap>[
        _RestoreSwap.file(
          source: stagedDatabase,
          target: File(databasePath),
          previous: File(path.join(previous.path, 'database', 'tomoread.db')),
        ),
        if (manifest.includesBooks) ...[
          _RestoreSwap.directory(
            source: await _ensureDirectory(
              Directory(path.join(staging.path, 'books')),
            ),
            target: Directory(path.join(root.path, 'library', 'books')),
            previous: Directory(
              path.join(previous.path, 'library', 'books'),
            ),
          ),
          _RestoreSwap.directory(
            source: await _ensureDirectory(
              Directory(path.join(staging.path, 'covers')),
            ),
            target: Directory(path.join(root.path, 'library', 'covers')),
            previous: Directory(
              path.join(previous.path, 'library', 'covers'),
            ),
          ),
        ],
        if (manifest.includesFonts)
          _RestoreSwap.directory(
            source: await _ensureDirectory(
              Directory(path.join(staging.path, 'fonts')),
            ),
            target: Directory(path.join(root.path, 'fonts')),
            previous: Directory(path.join(previous.path, 'fonts')),
          ),
      ];
      final installed = <_RestoreSwap>[];
      try {
        for (final swap in swaps) {
          await swap.install();
          installed.add(swap);
        }
        switched = true;
        onProgress?.call(
          const RestoreProgress(phase: RestorePhase.reopeningDatabase),
        );
        await database.database;
        await database.rewriteManagedPaths(
          supportRoot: root,
          bookPaths: logicalPaths.bookPaths,
          coverPaths: logicalPaths.coverPaths,
          fontPaths: logicalPaths.fontPaths,
        );
        await database.inspectSnapshot(databasePath);
      } on Object catch (error) {
        await database.close();
        for (final swap in installed.reversed) {
          await swap.rollback();
        }
        switched = false;
        await database.database;
        throw RestoreException('恢复失败，已自动保留原书库：$error');
      }

      if (await previous.exists()) await previous.delete(recursive: true);
      onProgress?.call(
        const RestoreProgress(phase: RestorePhase.completed),
      );
      return RestoreResult(
        manifest: manifest,
        rollbackBackupPath: rollbackBackup.path,
      );
    } on RestoreException {
      rethrow;
    } on BackupException catch (error) {
      throw RestoreException(error.message);
    } on Object catch (error) {
      await database.database;
      throw RestoreException('无法恢复备份：$error');
    } finally {
      if (!switched && await previous.exists()) {
        await previous.delete(recursive: true);
      }
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  _RestoreLogicalPaths _logicalPaths(BackupManifest manifest) {
    final bookPaths = <String, String>{};
    final coverPaths = <String, String>{};
    final fontPaths = <String, String>{};
    for (final entry in manifest.entries) {
      final segments = entry.path.split('/');
      switch (entry.kind) {
        case 'book':
          if (segments.length != 3) {
            throw const RestoreException('书籍备份路径格式无效。');
          }
          _putUnique(
            bookPaths,
            segments[1],
            path.posix.join('library', entry.path),
          );
          break;
        case 'cover':
          if (segments.length != 2) {
            throw const RestoreException('封面备份路径格式无效。');
          }
          _putUnique(
            coverPaths,
            path.posix.basenameWithoutExtension(segments[1]),
            path.posix.join('library', entry.path),
          );
          break;
        case 'font':
          if (segments.length != 3) {
            throw const RestoreException('字体备份路径格式无效。');
          }
          _putUnique(fontPaths, segments[1], entry.path);
          break;
        case 'database':
          break;
        default:
          throw const RestoreException('备份条目类型无效。');
      }
    }
    return _RestoreLogicalPaths(
      bookPaths: bookPaths,
      coverPaths: coverPaths,
      fontPaths: fontPaths,
    );
  }

  void _putUnique(Map<String, String> target, String key, String value) {
    if (key.isEmpty || target.containsKey(key)) {
      throw const RestoreException('备份包含重复或无效的实体文件。');
    }
    target[key] = value;
  }

  Future<Directory> _ensureDirectory(Directory directory) async {
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  List<int> _archiveBytes(ArchiveFile file) => file.content;

  bool _safeArchivePath(String value) {
    final normalized = path.posix.normalize(value);
    return value.isNotEmpty &&
        normalized == value &&
        !path.posix.isAbsolute(value) &&
        !value.contains('\\') &&
        !value.split('/').contains('..');
  }
}

class _RestoreLogicalPaths {
  const _RestoreLogicalPaths({
    required this.bookPaths,
    required this.coverPaths,
    required this.fontPaths,
  });

  final Map<String, String> bookPaths;
  final Map<String, String> coverPaths;
  final Map<String, String> fontPaths;
}

class _RestoreSwap {
  _RestoreSwap._({
    required this.source,
    required this.target,
    required this.previous,
    required this.isDirectory,
  });

  factory _RestoreSwap.file({
    required File source,
    required File target,
    required File previous,
  }) => _RestoreSwap._(
    source: source,
    target: target,
    previous: previous,
    isDirectory: false,
  );

  factory _RestoreSwap.directory({
    required Directory source,
    required Directory target,
    required Directory previous,
  }) => _RestoreSwap._(
    source: source,
    target: target,
    previous: previous,
    isDirectory: true,
  );

  final FileSystemEntity source;
  final FileSystemEntity target;
  final FileSystemEntity previous;
  final bool isDirectory;
  bool _hadPrevious = false;

  Future<void> install() async {
    await previous.parent.create(recursive: true);
    _hadPrevious = await target.exists();
    if (_hadPrevious) await target.rename(previous.path);
    await target.parent.create(recursive: true);
    try {
      await source.rename(target.path);
    } on Object {
      if (_hadPrevious && !await target.exists()) {
        await previous.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> rollback() async {
    if (await target.exists()) {
      if (isDirectory) {
        await Directory(target.path).delete(recursive: true);
      } else {
        await File(target.path).delete();
      }
    }
    if (_hadPrevious && await previous.exists()) {
      await previous.rename(target.path);
    }
  }
}
