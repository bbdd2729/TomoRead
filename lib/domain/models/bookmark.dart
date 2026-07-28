class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.locator,
    required this.chapterTitle,
    required this.createdAt,
    this.label,
  });

  final String id;
  final String bookId;
  final String locator;
  final String chapterTitle;
  final DateTime createdAt;
  final String? label;
}
