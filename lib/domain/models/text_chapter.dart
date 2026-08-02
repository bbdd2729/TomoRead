import 'document_locator.dart';

class TextChapter {
  const TextChapter({
    required this.id,
    required this.bookId,
    required this.ordinal,
    required this.title,
    required this.rawStart,
    required this.rawEnd,
    required this.contentHash,
    this.sourceRuleId,
  });

  final String id;
  final String bookId;
  final int ordinal;
  final String title;
  final int rawStart;
  final int rawEnd;
  final String? sourceRuleId;
  final String contentHash;

  String locator({int? start, int? end}) => TextDocumentLocator(
    chapterIndex: ordinal,
    rawStart: start ?? rawStart,
    rawEnd: end ?? rawEnd,
  ).serialize();
}

class ChapterRulePreview {
  const ChapterRulePreview({
    required this.ruleId,
    required this.matchCount,
    required this.examples,
  });

  final String ruleId;
  final int matchCount;
  final List<String> examples;
}

class TextChapterParseResult {
  const TextChapterParseResult({
    required this.chapters,
    required this.rulePreviews,
  });

  final List<TextChapter> chapters;
  final List<ChapterRulePreview> rulePreviews;
}
