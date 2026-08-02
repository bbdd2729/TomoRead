import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models/reading_context.dart';
import '../repositories/annotation_repository.dart';
import '../repositories/content_chunk_repository.dart';
import 'hybrid_search_service.dart';

class ReadingContextAssembler {
  const ReadingContextAssembler({
    required this.chunks,
    required this.annotations,
    this.hybridSearch,
  });

  final ContentChunkRepository chunks;
  final AnnotationRepository annotations;
  final HybridSearchService? hybridSearch;

  Future<ReadingContextBundle> assemble({
    required String bookId,
    required int currentChapterIndex,
    ReadingContextSelection? selection,
    bool includeCurrentChapter = true,
    List<String> annotationIds = const [],
    String? searchQuery,
    bool allowFutureChapters = false,
    int characterBudget = 12000,
  }) async {
    final budget = characterBudget.clamp(1000, 50000).toInt();
    final candidates = <ReadingContextSegment>[];
    if (selection != null && selection.text.trim().isNotEmpty) {
      candidates.add(
        _segment(
          kind: ReadingContextKind.selection,
          bookId: bookId,
          chapterIndex: selection.chapterIndex,
          chapterTitle: selection.chapterTitle,
          href: selection.href,
          locator: selection.locator,
          text: selection.text,
        ),
      );
    }
    if (includeCurrentChapter) {
      final chapterChunks = await chunks.listChapter(
        bookId,
        currentChapterIndex,
      );
      candidates.addAll(
        chapterChunks.map(
          (chunk) => ReadingContextSegment(
            kind: ReadingContextKind.currentChapter,
            bookId: bookId,
            chapterIndex: chunk.chapterIndex,
            chapterTitle: chunk.chapterTitle,
            href: chunk.href,
            locator: chunk.locatorStart,
            text: chunk.text,
            contentHash: chunk.textHash,
          ),
        ),
      );
    }
    if (annotationIds.isNotEmpty) {
      final requested = annotationIds.toSet();
      final values = await annotations.listForBook(bookId);
      candidates.addAll(
        values.where((annotation) => requested.contains(annotation.id)).map(
          (annotation) => _segment(
            kind: ReadingContextKind.annotation,
            bookId: bookId,
            chapterIndex: annotation.chapterIndex ?? currentChapterIndex,
            chapterTitle: annotation.chapterTitle ?? '未命名章节',
            href: annotation.href,
            locator: annotation.locator,
            text: [
              annotation.selectedText,
              if (annotation.note?.trim().isNotEmpty == true)
                '笔记：${annotation.note!.trim()}',
            ].join('\n'),
          ),
        ),
      );
    }
    final query = searchQuery?.trim() ?? '';
    if (query.isNotEmpty) {
      final hybrid = hybridSearch;
      if (hybrid == null) {
        final hits = await chunks.search(
          bookId: bookId,
          query: query,
          maxChapterIndex: allowFutureChapters ? null : currentChapterIndex,
          limit: 12,
        );
        candidates.addAll(
          hits.map(
            (hit) => ReadingContextSegment(
              kind: ReadingContextKind.indexHit,
              bookId: bookId,
              chapterIndex: hit.chunk.chapterIndex,
              chapterTitle: hit.chunk.chapterTitle,
              href: hit.chunk.href,
              locator: hit.chunk.locatorStart,
              text: hit.excerpt,
              contentHash: hit.chunk.textHash,
            ),
          ),
        );
      } else {
        final response = await hybrid.search(
          bookId: bookId,
          query: query,
          maxChapterIndex: allowFutureChapters ? null : currentChapterIndex,
          limit: 12,
        );
        candidates.addAll(
          response.results.map(
            (hit) => ReadingContextSegment(
              kind: ReadingContextKind.indexHit,
              bookId: bookId,
              chapterIndex: hit.chapterIndex,
              chapterTitle: hit.chapterTitle,
              href: hit.href,
              locator: hit.locator,
              text: hit.excerpt,
              contentHash: hit.textHash,
            ),
          ),
        );
      }
    }

    final segments = <ReadingContextSegment>[];
    final seen = <String>{};
    var used = 0;
    for (final candidate in candidates) {
      if (!allowFutureChapters && candidate.chapterIndex > currentChapterIndex) {
        continue;
      }
      final identity = '${candidate.locator}:${candidate.contentHash}';
      if (!seen.add(identity)) continue;
      final remaining = budget - used;
      if (remaining <= 0) break;
      final text = candidate.text.length <= remaining
          ? candidate.text
          : candidate.text.substring(0, remaining);
      if (text.trim().isEmpty) continue;
      segments.add(
        ReadingContextSegment(
          kind: candidate.kind,
          bookId: candidate.bookId,
          chapterIndex: candidate.chapterIndex,
          chapterTitle: candidate.chapterTitle,
          href: candidate.href,
          locator: candidate.locator,
          text: text,
          contentHash: candidate.contentHash,
        ),
      );
      used += text.length;
    }
    final contextHash = sha256
        .convert(
          utf8.encode(
            segments
                .map(
                  (segment) =>
                      '${segment.kind.name}|${segment.locator}|${segment.contentHash}|${segment.text}',
                )
                .join('\n'),
          ),
        )
        .toString();
    return ReadingContextBundle(
      bookId: bookId,
      currentChapterIndex: currentChapterIndex,
      segments: segments,
      characterBudget: budget,
      usedCharacters: used,
      contextHash: contextHash,
      spoilerLimited: !allowFutureChapters,
    );
  }

  ReadingContextSegment _segment({
    required ReadingContextKind kind,
    required String bookId,
    required int chapterIndex,
    required String chapterTitle,
    required String href,
    required String locator,
    required String text,
  }) => ReadingContextSegment(
    kind: kind,
    bookId: bookId,
    chapterIndex: chapterIndex,
    chapterTitle: chapterTitle,
    href: href,
    locator: locator,
    text: text,
    contentHash: sha256.convert(utf8.encode(text)).toString(),
  );
}
