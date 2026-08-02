import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../domain/models/book_import.dart';
import 'import_cancellation_token.dart';

typedef ImportScanProgress = void Function(int scannedEntries);

class BookImportScanService {
  const BookImportScanService();

  static const supportedExtensions = {'.epub', '.pdf', '.txt', '.md', '.markdown'};
  static const _supportedMimeTypes = {
    'application/epub+zip',
    'application/pdf',
    'text/plain',
    'text/markdown',
    'text/x-markdown',
  };
  static const _systemDirectoryNames = {
    r'$recycle.bin',
    'system volume information',
    'windows',
    'program files',
    'program files (x86)',
    'programdata',
    'lost+found',
    'proc',
    'sys',
    'dev',
  };

  Future<ImportScanPreview> scan(
    Iterable<ImportSource> sources, {
    ImportScanLimits limits = const ImportScanLimits(),
    ImportCancellationToken? cancellationToken,
    ImportScanProgress? onProgress,
    Iterable<String> excludedRoots = const [],
  }) async {
    final items = <ImportScanItem>[];
    final seenPaths = <String>{};
    final normalizedExcludedRoots = excludedRoots
        .where((value) => value.trim().isNotEmpty)
        .map((value) => path.normalize(path.absolute(value)))
        .toList(growable: false);
    var totalBytes = 0;
    var supportedFiles = 0;
    var limitReached = false;

    bool shouldStop() {
      if (cancellationToken?.isCancelled == true) return true;
      if (items.length < limits.maxEntries) return false;
      limitReached = true;
      return true;
    }

    void add(ImportScanItem item) {
      if (items.length >= limits.maxEntries) {
        limitReached = true;
        return;
      }
      items.add(item);
      onProgress?.call(items.length);
    }

    Future<void> inspectFile(
      ImportSource source,
      String filePath, {
      required bool discoveredInDirectory,
    }) async {
      if (shouldStop()) return;
      final normalizedPath = path.normalize(path.absolute(filePath));
      final identity = Platform.isWindows
          ? normalizedPath.toLowerCase()
          : normalizedPath;
      if (!seenPaths.add(identity)) {
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.skipped,
            reason: '同一路径已在本次扫描中出现',
          ),
        );
        return;
      }
      final name = path.basename(normalizedPath);
      if (discoveredInDirectory && _isHiddenName(name)) {
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.skipped,
            reason: '已忽略隐藏文件',
          ),
        );
        return;
      }
      final extension = path.extension(name).toLowerCase();
      if (!supportedExtensions.contains(extension)) {
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.skipped,
            reason: '不支持的文件格式',
          ),
        );
        return;
      }
      final mimeType = source.mimeType?.split(';').first.trim().toLowerCase();
      if (mimeType != null &&
          mimeType.isNotEmpty &&
          !_supportedMimeTypes.contains(mimeType)) {
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.skipped,
            reason: '文件 MIME 类型不受支持',
          ),
        );
        return;
      }
      if (supportedFiles >= limits.maxSupportedFiles) {
        limitReached = true;
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.skipped,
            reason: '已达到单次导入文件数量上限',
          ),
        );
        return;
      }
      try {
        final stat = await File(normalizedPath).stat();
        if (stat.type != FileSystemEntityType.file) {
          add(
            ImportScanItem(
              source: source,
              disposition: ImportScanDisposition.skipped,
              reason: '路径不是普通文件',
            ),
          );
          return;
        }
        if (stat.size > limits.maxFileBytes) {
          add(
            ImportScanItem(
              source: source,
              disposition: ImportScanDisposition.skipped,
              reason: '文件超过单文件大小上限',
            ),
          );
          return;
        }
        if (totalBytes + stat.size > limits.maxTotalBytes) {
          limitReached = true;
          add(
            ImportScanItem(
              source: source,
              disposition: ImportScanDisposition.skipped,
              reason: '文件会使本次导入超过总大小上限',
            ),
          );
          return;
        }
        supportedFiles++;
        totalBytes += stat.size;
        final requestSource = ImportSource(
          kind: source.kind,
          location: normalizedPath,
          displayName: source.displayName ?? name,
          mimeType: source.mimeType,
          temporary: source.temporary,
        );
        add(
          ImportScanItem(
            source: requestSource,
            disposition: ImportScanDisposition.supported,
            request: BookImportRequest(
              source: requestSource,
              sourcePath: normalizedPath,
              sizeBytes: stat.size,
            ),
          ),
        );
      } on FileSystemException catch (error) {
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.failed,
            reason: error.message,
          ),
        );
      }
    }

    for (final source in sources) {
      if (shouldStop()) break;
      final location = source.location.trim();
      if (location.isEmpty) {
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.failed,
            reason: '导入路径为空',
          ),
        );
        continue;
      }
      final normalizedPath = path.normalize(path.absolute(location));
      try {
        final type = await FileSystemEntity.type(
          normalizedPath,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link) {
          add(
            ImportScanItem(
              source: source,
              disposition: ImportScanDisposition.skipped,
              reason: '已忽略符号链接',
            ),
          );
          continue;
        }
        if (type == FileSystemEntityType.file) {
          await inspectFile(source, normalizedPath, discoveredInDirectory: false);
          continue;
        }
        if (type != FileSystemEntityType.directory) {
          add(
            ImportScanItem(
              source: source,
              disposition: ImportScanDisposition.failed,
              reason: '路径不存在或无法读取',
            ),
          );
          continue;
        }
        if (_isExcluded(normalizedPath, normalizedExcludedRoots)) {
          add(
            ImportScanItem(
              source: source,
              disposition: ImportScanDisposition.skipped,
              reason: '不会扫描应用私有目录',
            ),
          );
          continue;
        }

        final directories = Queue<Directory>()..add(Directory(normalizedPath));
        while (directories.isNotEmpty && !shouldStop()) {
          final directory = directories.removeFirst();
          try {
            await for (final entity in directory.list(followLinks: false)) {
              if (shouldStop()) break;
              final entityType = await FileSystemEntity.type(
                entity.path,
                followLinks: false,
              );
              final childSource = ImportSource(
                kind: source.kind,
                location: entity.path,
                displayName: path.basename(entity.path),
                mimeType: source.mimeType,
                temporary: source.temporary,
              );
              if (entityType == FileSystemEntityType.link) {
                add(
                  ImportScanItem(
                    source: childSource,
                    disposition: ImportScanDisposition.skipped,
                    reason: '已忽略符号链接',
                  ),
                );
              } else if (entityType == FileSystemEntityType.directory) {
                final name = path.basename(entity.path);
                if (_isHiddenName(name) || _isSystemDirectory(name)) {
                  add(
                    ImportScanItem(
                      source: childSource,
                      disposition: ImportScanDisposition.skipped,
                      reason: '已忽略隐藏或系统目录',
                    ),
                  );
                } else if (_isExcluded(entity.path, normalizedExcludedRoots)) {
                  add(
                    ImportScanItem(
                      source: childSource,
                      disposition: ImportScanDisposition.skipped,
                      reason: '不会扫描应用私有目录',
                    ),
                  );
                } else {
                  directories.add(Directory(entity.path));
                }
              } else if (entityType == FileSystemEntityType.file) {
                await inspectFile(
                  childSource,
                  entity.path,
                  discoveredInDirectory: true,
                );
              }
            }
          } on FileSystemException catch (error) {
            add(
              ImportScanItem(
                source: ImportSource(
                  kind: source.kind,
                  location: directory.path,
                  displayName: path.basename(directory.path),
                ),
                disposition: ImportScanDisposition.failed,
                reason: error.message,
              ),
            );
          }
        }
      } on FileSystemException catch (error) {
        add(
          ImportScanItem(
            source: source,
            disposition: ImportScanDisposition.failed,
            reason: error.message,
          ),
        );
      }
    }

    return ImportScanPreview(
      items: List.unmodifiable(items),
      totalBytes: totalBytes,
      cancelled: cancellationToken?.isCancelled == true,
      limitReached: limitReached,
    );
  }

  bool _isHiddenName(String name) => name.startsWith('.');

  bool _isSystemDirectory(String name) =>
      _systemDirectoryNames.contains(name.toLowerCase());

  bool _isExcluded(String value, List<String> excludedRoots) {
    final normalized = path.normalize(path.absolute(value));
    return excludedRoots.any(
      (root) => normalized == root || path.isWithin(root, normalized),
    );
  }
}
