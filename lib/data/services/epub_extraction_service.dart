import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/library_book.dart';

class EpubExtractionException implements Exception {
  const EpubExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EpubExtractionService {
  const EpubExtractionService({this.libraryRootProvider});

  final Future<Directory> Function()? libraryRootProvider;

  Future<String> ensureExtracted(LibraryBook book) async {
    final root = libraryRootProvider == null
        ? await getApplicationSupportDirectory()
        : await libraryRootProvider!();
    final targetDirectory = Directory(
      path.join(root.path, 'library', 'extracted', book.fileHash),
    );
    final completionMarker = File(path.join(targetDirectory.path, '.complete'));
    if (await completionMarker.exists()) return targetDirectory.path;

    final source = File(book.filePath);
    if (!await source.exists()) {
      throw const EpubExtractionException('找不到已导入的 EPUB 文件');
    }

    try {
      final archive = ZipDecoder().decodeBytes(await source.readAsBytes());
      await targetDirectory.create(recursive: true);
      for (final entry in archive.files.where((entry) => entry.isFile)) {
        final relativePath = path.joinAll(entry.name.split('/'));
        final destination = File(path.join(targetDirectory.path, relativePath));
        if (!path.isWithin(targetDirectory.path, destination.path) ||
            path.equals(destination.path, completionMarker.path)) {
          throw const EpubExtractionException('EPUB 包含不安全的资源路径');
        }
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(entry.content as List<int>);
      }
      await completionMarker.writeAsString('complete');
      return targetDirectory.path;
    } on EpubExtractionException {
      rethrow;
    } catch (error) {
      throw EpubExtractionException('无法准备 EPUB 阅读资源：$error');
    }
  }
}
