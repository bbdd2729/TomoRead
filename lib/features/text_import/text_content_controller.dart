import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:crypto/crypto.dart';

import '../../app/providers.dart';
import '../../data/services/chapter_parser_service.dart';
import '../../data/services/text_decoder_service.dart';
import '../../domain/models/text_content_profile.dart';
import '../../domain/models/text_chapter.dart';

final textContentControllerProvider = Provider<TextContentController>(
  (ref) => TextContentController(ref),
);

class TextContentController {
  const TextContentController(this.ref);

  final Ref ref;

  Future<void> rebuildWithEncoding(String bookId, String encoding) async {
    final book = await ref.read(bookRepositoryProvider).findById(bookId);
    if (book == null || (book.format != 'txt' && book.format != 'markdown')) {
      throw const TextDecodeException('文本书籍不存在。');
    }
    final decoded = await ref
        .read(textDecoderServiceProvider)
        .decodeFile(book.filePath, encodingOverride: encoding);
    final parsed = await ref.read(chapterParserServiceProvider).parse(
      bookId: bookId,
      text: decoded.text,
      contentHash: decoded.contentHash,
      markdown: book.format == 'markdown',
    );
    await ref
        .read(textContentRepositoryProvider)
        .saveProfileAndChapters(
          TextContentProfile(
            bookId: bookId,
            encoding: decoded.encoding,
            encodingConfidence: 1,
            parserVersion: ChapterParserService.parserVersion,
            contentHash: decoded.contentHash,
            updatedAt: DateTime.now(),
          ),
          parsed.chapters,
        );
    ref.invalidate(textContentProfileProvider(bookId));
    ref.invalidate(textChaptersProvider(bookId));
    ref.invalidate(textBookDocumentProvider(bookId));
    ref.invalidate(readerBookProvider(bookId));
    ref.invalidate(libraryBooksProvider);
  }

  Future<void> renameChapter(
    String bookId,
    String chapterId,
    String title,
  ) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.length > 120) {
      throw const FormatException('章节标题应为 1 到 120 个字符。');
    }
    final chapters = await ref
        .read(textContentRepositoryProvider)
        .listChapters(bookId);
    final next = chapters
        .map(
          (chapter) => chapter.id == chapterId
              ? _copyChapter(chapter, title: normalized)
              : chapter,
        )
        .toList();
    await _saveChapters(bookId, next);
  }

  Future<void> mergeWithNext(String bookId, int ordinal) async {
    final document = await ref.read(textBookDocumentProvider(bookId).future);
    if (ordinal < 0 || ordinal + 1 >= document.chapters.length) {
      throw const FormatException('当前章节后没有可合并章节。');
    }
    final current = document.chapters[ordinal];
    final following = document.chapters[ordinal + 1];
    final merged = _copyChapter(
      current,
      rawEnd: following.rawEnd,
      contentHash: _rangeHash(
        document.rawText,
        current.rawStart,
        following.rawEnd,
      ),
      sourceRuleId: 'manual-merge',
    );
    final next = [...document.chapters]..replaceRange(
      ordinal,
      ordinal + 2,
      [merged],
    );
    await _saveChapters(bookId, next);
  }

  Future<void> splitChapter({
    required String bookId,
    required int ordinal,
    required int rawOffset,
    required String nextTitle,
  }) async {
    final document = await ref.read(textBookDocumentProvider(bookId).future);
    if (ordinal < 0 || ordinal >= document.chapters.length) {
      throw const FormatException('章节不存在。');
    }
    final chapter = document.chapters[ordinal];
    if (rawOffset <= chapter.rawStart || rawOffset >= chapter.rawEnd) {
      throw const FormatException('拆分位置必须位于当前章节正文中。');
    }
    final normalizedTitle = nextTitle.trim();
    if (normalizedTitle.isEmpty || normalizedTitle.length > 120) {
      throw const FormatException('新章节标题应为 1 到 120 个字符。');
    }
    final first = _copyChapter(
      chapter,
      rawEnd: rawOffset,
      contentHash: _rangeHash(
        document.rawText,
        chapter.rawStart,
        rawOffset,
      ),
      sourceRuleId: 'manual-split',
    );
    final secondHash = _rangeHash(
      document.rawText,
      rawOffset,
      chapter.rawEnd,
    );
    final second = TextChapter(
      id: '$bookId-${secondHash.substring(0, 16)}-${DateTime.now().microsecondsSinceEpoch}',
      bookId: bookId,
      ordinal: ordinal + 1,
      title: normalizedTitle,
      rawStart: rawOffset,
      rawEnd: chapter.rawEnd,
      sourceRuleId: 'manual-split',
      contentHash: secondHash,
    );
    final next = [...document.chapters]..replaceRange(
      ordinal,
      ordinal + 1,
      [first, second],
    );
    await _saveChapters(bookId, next);
  }

  Future<void> _saveChapters(
    String bookId,
    List<TextChapter> chapters,
  ) async {
    final normalized = <TextChapter>[
      for (var index = 0; index < chapters.length; index++)
        _copyChapter(chapters[index], ordinal: index),
    ];
    await ref
        .read(textContentRepositoryProvider)
        .replaceChapters(bookId, normalized);
    ref.invalidate(textChaptersProvider(bookId));
    ref.invalidate(textBookDocumentProvider(bookId));
    ref.invalidate(readerBookProvider(bookId));
    ref.invalidate(libraryBooksProvider);
  }

  TextChapter _copyChapter(
    TextChapter source, {
    int? ordinal,
    String? title,
    int? rawEnd,
    String? sourceRuleId,
    String? contentHash,
  }) => TextChapter(
    id: source.id,
    bookId: source.bookId,
    ordinal: ordinal ?? source.ordinal,
    title: title ?? source.title,
    rawStart: source.rawStart,
    rawEnd: rawEnd ?? source.rawEnd,
    sourceRuleId: sourceRuleId ?? source.sourceRuleId,
    contentHash: contentHash ?? source.contentHash,
  );

  String _rangeHash(String text, int start, int end) =>
      sha256.convert(utf8.encode(text.substring(start, end))).toString();
}
