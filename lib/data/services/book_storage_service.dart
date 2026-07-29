import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/library_book.dart';
import '../repositories/book_repository.dart';

class BookRemovalResult {
  const BookRemovalResult({this.cleanupErrors = const []});

  final List<String> cleanupErrors;

  bool get hasCleanupErrors => cleanupErrors.isNotEmpty;
}

class BookStorageService {
  const BookStorageService({
    required this.repository,
    this.libraryRootProvider,
  });

  final BookRepository repository;
  final Future<Directory> Function()? libraryRootProvider;

  Future<BookRemovalResult> removeBook(LibraryBook book) async {
    await repository.deleteBook(book.id);

    final root = libraryRootProvider == null
        ? await getApplicationSupportDirectory()
        : await libraryRootProvider!();
    final libraryPath = path.join(root.path, 'library');
    final cleanupErrors = <String>[];

    await _deleteManagedFile(
      book.filePath,
      managedDirectory: path.join(libraryPath, 'books'),
      cleanupErrors: cleanupErrors,
    );
    await _deleteManagedFile(
      book.coverPath,
      managedDirectory: path.join(libraryPath, 'covers'),
      cleanupErrors: cleanupErrors,
    );
    await _deleteManagedDirectory(
      path.join(libraryPath, 'extracted', book.fileHash),
      managedDirectory: path.join(libraryPath, 'extracted'),
      cleanupErrors: cleanupErrors,
    );
    return BookRemovalResult(cleanupErrors: cleanupErrors);
  }

  Future<void> _deleteManagedFile(
    String? targetPath, {
    required String managedDirectory,
    required List<String> cleanupErrors,
  }) async {
    if (targetPath == null ||
        !path.isWithin(managedDirectory, path.normalize(targetPath))) {
      return;
    }
    try {
      final file = File(targetPath);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      cleanupErrors.add(error.message);
    }
  }

  Future<void> _deleteManagedDirectory(
    String targetPath, {
    required String managedDirectory,
    required List<String> cleanupErrors,
  }) async {
    if (!path.isWithin(managedDirectory, path.normalize(targetPath))) return;
    try {
      final directory = Directory(targetPath);
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException catch (error) {
      cleanupErrors.add(error.message);
    }
  }
}
