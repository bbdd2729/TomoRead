enum ContentIndexStatus { pending, indexing, ready, failed }

class ContentChunk {
  const ContentChunk({
    required this.id,
    required this.bookId,
    required this.chapterId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.href,
    required this.locatorStart,
    required this.locatorEnd,
    required this.rawStart,
    required this.rawEnd,
    required this.ordinal,
    required this.text,
    required this.textHash,
    required this.contentHash,
    required this.parserVersion,
    required this.indexVersion,
  });

  final String id;
  final String bookId;
  final String chapterId;
  final int chapterIndex;
  final String chapterTitle;
  final String href;
  final String locatorStart;
  final String locatorEnd;
  final int rawStart;
  final int rawEnd;
  final int ordinal;
  final String text;
  final String textHash;
  final String contentHash;
  final int parserVersion;
  final int indexVersion;
}

class ContentIndexState {
  const ContentIndexState({
    required this.bookId,
    required this.contentHash,
    required this.parserVersion,
    required this.indexVersion,
    required this.status,
    required this.progress,
    required this.updatedAt,
    this.error,
  });

  final String bookId;
  final String contentHash;
  final int parserVersion;
  final int indexVersion;
  final ContentIndexStatus status;
  final double progress;
  final String? error;
  final DateTime updatedAt;
}

class ContentSearchResult {
  const ContentSearchResult({required this.chunk, required this.excerpt});

  final ContentChunk chunk;
  final String excerpt;
}
