import 'epub_manifest.dart';

class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.fileHash,
    required this.title,
    required this.author,
    required this.filePath,
    required this.progress,
    required this.importedAt,
    required this.format,
    required this.chapterCount,
    required this.direction,
    this.coverPath,
    this.description,
  });

  final String id;
  final String fileHash;
  final String title;
  final String author;
  final String filePath;
  final String? coverPath;
  final String? description;
  final double progress;
  final DateTime importedAt;
  final String format;
  final int chapterCount;
  final ReadingDirection direction;
}

class ImportedBook {
  const ImportedBook({required this.book, required this.manifest});

  final LibraryBook book;
  final EpubManifest manifest;
}
