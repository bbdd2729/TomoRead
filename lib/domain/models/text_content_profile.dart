import 'library_book.dart';
import 'text_chapter.dart';

class TextContentProfile {
  const TextContentProfile({
    required this.bookId,
    required this.encoding,
    required this.parserVersion,
    required this.contentHash,
    required this.updatedAt,
    this.encodingConfidence,
  });

  final String bookId;
  final String encoding;
  final double? encodingConfidence;
  final int parserVersion;
  final String contentHash;
  final DateTime updatedAt;
}

class TextDecodeResult {
  const TextDecodeResult({
    required this.text,
    required this.encoding,
    required this.confidence,
    required this.hasReplacementCharacters,
    required this.preview,
    required this.contentHash,
    required this.requiresUserConfirmation,
    this.candidates = const [],
  });

  final String text;
  final String encoding;
  final double confidence;
  final bool hasReplacementCharacters;
  final String preview;
  final String contentHash;
  final bool requiresUserConfirmation;
  final List<String> candidates;
}

class TextBookDocument {
  const TextBookDocument({
    required this.book,
    required this.profile,
    required this.chapters,
    required this.rawText,
  });

  final LibraryBook book;
  final TextContentProfile profile;
  final List<TextChapter> chapters;
  final String rawText;
}
