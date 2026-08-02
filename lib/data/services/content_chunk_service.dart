import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../domain/models/content_chunk.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/text_chapter.dart';
import '../repositories/content_chunk_repository.dart';
import 'chapter_parser_service.dart';
import 'epub_content_service.dart';

class ContentChunkService {
  const ContentChunkService({
    required this.repository,
    required this.epubContent,
  });

  static const indexVersion = 1;
  static const maxChunkLength = 1400;

  final ContentChunkRepository repository;
  final EpubContentService epubContent;

  Future<void> rebuildText({
    required String bookId,
    required String rawText,
    required String contentHash,
    required List<TextChapter> chapters,
  }) async {
    await repository.beginRebuild(
      bookId: bookId,
      contentHash: contentHash,
      parserVersion: ChapterParserService.parserVersion,
      indexVersion: indexVersion,
    );
    try {
      final chunks = await Isolate.run(
        () => _buildTextChunks(
          bookId,
          rawText,
          contentHash,
          chapters,
        ),
      );
      await repository.replaceForBook(
        bookId: bookId,
        contentHash: contentHash,
        parserVersion: ChapterParserService.parserVersion,
        indexVersion: indexVersion,
        chunks: chunks,
      );
    } on Object catch (error) {
      await repository.markFailed(
        bookId: bookId,
        contentHash: contentHash,
        parserVersion: ChapterParserService.parserVersion,
        indexVersion: indexVersion,
        error: error,
      );
      rethrow;
    }
  }

  Future<void> rebuildEpub({
    required LibraryBook book,
    required EpubManifest manifest,
  }) async {
    await repository.beginRebuild(
      bookId: book.id,
      contentHash: book.fileHash,
      parserVersion: 1,
      indexVersion: indexVersion,
    );
    try {
      final chunks = <ContentChunk>[];
      var ordinal = 0;
      for (var chapterIndex = 0;
          chapterIndex < manifest.spine.length;
          chapterIndex++) {
        final chapter = await epubContent.loadChapter(
          book: book,
          manifest: manifest,
          chapterIndex: chapterIndex,
        );
        final text = chapter.plainText;
        for (final range in _splitRanges(text, 0, text.length)) {
          final content = text.substring(range.$1, range.$2);
          final textHash = sha256.convert(utf8.encode(content)).toString();
          final startRatio = text.isEmpty ? 0.0 : range.$1 / text.length;
          final endRatio = text.isEmpty ? 0.0 : range.$2 / text.length;
          chunks.add(
            ContentChunk(
              id: _chunkId(book.id, chapterIndex, range.$1, textHash),
              bookId: book.id,
              chapterId: 'epub-$chapterIndex',
              chapterIndex: chapterIndex,
              chapterTitle: chapter.title,
              href: chapter.href,
              locatorStart: 'ratio:${startRatio.toStringAsFixed(6)}',
              locatorEnd: 'ratio:${endRatio.toStringAsFixed(6)}',
              rawStart: range.$1,
              rawEnd: range.$2,
              ordinal: ordinal++,
              text: content,
              textHash: textHash,
              contentHash: book.fileHash,
              parserVersion: 1,
              indexVersion: indexVersion,
            ),
          );
        }
        await repository.reportProgress(
          book.id,
          manifest.spine.isEmpty
              ? 1
              : (chapterIndex + 1) / manifest.spine.length,
        );
      }
      await repository.replaceForBook(
        bookId: book.id,
        contentHash: book.fileHash,
        parserVersion: 1,
        indexVersion: indexVersion,
        chunks: chunks,
      );
    } on Object catch (error) {
      await repository.markFailed(
        bookId: book.id,
        contentHash: book.fileHash,
        parserVersion: 1,
        indexVersion: indexVersion,
        error: error,
      );
      rethrow;
    }
  }
}

List<ContentChunk> _buildTextChunks(
  String bookId,
  String rawText,
  String contentHash,
  List<TextChapter> chapters,
) {
  final chunks = <ContentChunk>[];
  var ordinal = 0;
  for (final chapter in chapters) {
    final chapterStart = chapter.rawStart.clamp(0, rawText.length).toInt();
    final chapterEnd = chapter.rawEnd.clamp(chapterStart, rawText.length).toInt();
    for (final range in _splitRanges(rawText, chapterStart, chapterEnd)) {
      final content = rawText.substring(range.$1, range.$2);
      final textHash = sha256.convert(utf8.encode(content)).toString();
      chunks.add(
        ContentChunk(
          id: _chunkId(bookId, chapter.ordinal, range.$1, textHash),
          bookId: bookId,
          chapterId: chapter.id,
          chapterIndex: chapter.ordinal,
          chapterTitle: chapter.title,
          href: 'text:${chapter.id}',
          locatorStart: chapter.locator(start: range.$1, end: range.$1),
          locatorEnd: chapter.locator(start: range.$2, end: range.$2),
          rawStart: range.$1,
          rawEnd: range.$2,
          ordinal: ordinal++,
          text: content,
          textHash: textHash,
          contentHash: contentHash,
          parserVersion: ChapterParserService.parserVersion,
          indexVersion: ContentChunkService.indexVersion,
        ),
      );
    }
  }
  return chunks;
}

List<(int, int)> _splitRanges(String text, int start, int end) {
  final result = <(int, int)>[];
  var cursor = start;
  while (cursor < end) {
    while (cursor < end && _isWhitespace(text.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= end) break;
    var target = (cursor + ContentChunkService.maxChunkLength)
        .clamp(cursor + 1, end)
        .toInt();
    if (target < end) {
      final minimum = cursor + (ContentChunkService.maxChunkLength * .55).round();
      final paragraph = text.lastIndexOf('\n\n', target);
      final line = text.lastIndexOf('\n', target);
      final space = text.lastIndexOf(' ', target);
      final preferred = [paragraph, line, space]
          .where((value) => value >= minimum)
          .firstOrNull;
      if (preferred != null) target = preferred;
    }
    while (target > cursor && _isWhitespace(text.codeUnitAt(target - 1))) {
      target--;
    }
    if (target <= cursor) target = (cursor + 1).clamp(0, end).toInt();
    result.add((cursor, target));
    cursor = target;
  }
  return result;
}

bool _isWhitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

String _chunkId(String bookId, int chapter, int start, String textHash) =>
    sha256
        .convert(utf8.encode('$bookId:$chapter:$start:$textHash'))
        .toString()
        .substring(0, 32);
