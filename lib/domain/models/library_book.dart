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
    this.updatedAt,
    this.chapterIndex = 0,
    this.locator,
    this.coverPath,
    this.description,
    this.category,
    this.tags = const [],
    this.isFavorite = false,
  });

  final String id;
  final String fileHash;
  final String title;
  final String author;
  final String filePath;
  final String? coverPath;
  final String? description;
  final String? category;
  final List<String> tags;
  final bool isFavorite;
  final double progress;
  final DateTime importedAt;
  final DateTime? updatedAt;
  final String format;
  final int chapterCount;
  final int chapterIndex;
  final String? locator;
  final ReadingDirection direction;

  LibraryBook copyWith({
    String? title,
    String? author,
    String? coverPath,
    String? description,
    String? category,
    String? locator,
    List<String>? tags,
    bool? isFavorite,
    double? progress,
    int? chapterIndex,
    DateTime? updatedAt,
    bool clearDescription = false,
    bool clearCategory = false,
    bool clearLocator = false,
  }) => LibraryBook(
    id: id,
    fileHash: fileHash,
    title: title ?? this.title,
    author: author ?? this.author,
    filePath: filePath,
    progress: progress ?? this.progress,
    importedAt: importedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    format: format,
    chapterCount: chapterCount,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    locator: clearLocator ? null : locator ?? this.locator,
    coverPath: coverPath ?? this.coverPath,
    description: clearDescription ? null : description ?? this.description,
    category: clearCategory ? null : category ?? this.category,
    tags: tags ?? this.tags,
    isFavorite: isFavorite ?? this.isFavorite,
    direction: direction,
  );
}

class ImportedBook {
  const ImportedBook({required this.book, required this.manifest});

  final LibraryBook book;
  final EpubManifest manifest;
}
