import '../../domain/models/content_chunk.dart';
import '../../domain/models/document_locator.dart';
import '../../domain/models/tts.dart';
import '../repositories/content_chunk_repository.dart';

class TtsQueueResult {
  const TtsQueueResult({required this.segments, required this.startIndex});

  final List<TtsSegment> segments;
  final int startIndex;
}

abstract interface class TtsQueueLoader {
  Future<TtsQueueResult> load({
    required String bookId,
    required String format,
    required int chapterIndex,
    required String? currentLocator,
    required TtsCursor? savedCursor,
  });
}

class TtsQueueService implements TtsQueueLoader {
  const TtsQueueService(this.repository);

  final ContentChunkRepository repository;

  @override
  Future<TtsQueueResult> load({
    required String bookId,
    required String format,
    required int chapterIndex,
    required String? currentLocator,
    required TtsCursor? savedCursor,
  }) async {
    final chunks = await repository.listChapter(bookId, chapterIndex);
    final segments = buildTtsSegmentsFromChunks(chunks, format: format);
    return TtsQueueResult(
      segments: segments,
      startIndex: _resolveStartIndex(
        segments,
        format: format,
        chapterIndex: chapterIndex,
        currentLocator: currentLocator,
        savedCursor: savedCursor,
      ),
    );
  }
}

List<TtsSegment> buildTtsSegmentsFromChunks(
  Iterable<ContentChunk> chunks, {
  required String format,
}) {
  final segments = <TtsSegment>[];
  for (final chunk in chunks) {
    for (final range in splitTtsSentenceRanges(chunk.text)) {
      final source = chunk.text.substring(range.$1, range.$2);
      final text = source.trim();
      if (text.isEmpty) continue;
      final leadingWhitespace = source.length - source.trimLeft().length;
      final localStart = range.$1 + leadingWhitespace;
      final localEnd = localStart + text.length;
      final rawStart = chunk.rawStart + localStart;
      final rawEnd = chunk.rawStart + localEnd;
      final locators = _segmentLocators(
        chunk,
        format: format,
        localStart: localStart,
        localEnd: localEnd,
      );
      segments.add(
        TtsSegment(
          id: '${chunk.id}:$localStart:$localEnd',
          text: text,
          href: chunk.href,
          locatorStart: locators.$1,
          locatorEnd: locators.$2,
          chapterIndex: chunk.chapterIndex,
          chapterTitle: chunk.chapterTitle,
          rawStart: rawStart,
          rawEnd: rawEnd,
        ),
      );
    }
  }
  return segments;
}

List<(int, int)> splitTtsSentenceRanges(String text, {int maxLength = 320}) {
  final result = <(int, int)>[];
  var start = 0;
  var index = 0;
  while (index < text.length) {
    final unit = text.codeUnitAt(index);
    final sentenceEnd = _isSentenceTerminator(unit) || unit == 0x0a;
    final atLimit = index - start + 1 >= maxLength;
    if (sentenceEnd || atLimit) {
      var end = index + 1;
      if (atLimit && !sentenceEnd) {
        final preferred = _lastSoftBoundary(text, start, end);
        if (preferred > start) end = preferred;
      }
      result.add((start, end));
      start = end;
      index = end;
      continue;
    }
    index++;
  }
  if (start < text.length) result.add((start, text.length));
  return result;
}

bool _isSentenceTerminator(int unit) =>
    unit == 0x3002 ||
    unit == 0xff01 ||
    unit == 0xff1f ||
    unit == 0x21 ||
    unit == 0x3f ||
    unit == 0x3b ||
    unit == 0xff1b;

int _lastSoftBoundary(String text, int start, int end) {
  final minimum = start + ((end - start) * .55).round();
  for (var index = end - 1; index >= minimum; index--) {
    final unit = text.codeUnitAt(index);
    if (unit == 0x2c ||
        unit == 0xff0c ||
        unit == 0x20 ||
        unit == 0x09) {
      return index + 1;
    }
  }
  return end;
}

(String, String) _segmentLocators(
  ContentChunk chunk, {
  required String format,
  required int localStart,
  required int localEnd,
}) {
  if (format == 'txt' || format == 'markdown') {
    return (
      TextDocumentLocator(
        chapterIndex: chunk.chapterIndex,
        rawStart: chunk.rawStart + localStart,
        rawEnd: chunk.rawStart + localStart,
      ).serialize(),
      TextDocumentLocator(
        chapterIndex: chunk.chapterIndex,
        rawStart: chunk.rawStart + localEnd,
        rawEnd: chunk.rawStart + localEnd,
      ).serialize(),
    );
  }
  final startRatio = _ratioLocator(chunk.locatorStart) ?? 0;
  final endRatio = _ratioLocator(chunk.locatorEnd) ?? startRatio;
  final length = chunk.text.isEmpty ? 1 : chunk.text.length;
  final segmentStart = startRatio +
      (endRatio - startRatio) * (localStart / length).clamp(0, 1);
  final segmentEnd = startRatio +
      (endRatio - startRatio) * (localEnd / length).clamp(0, 1);
  return (
    'ratio:${segmentStart.clamp(0, 1).toStringAsFixed(6)}',
    'ratio:${segmentEnd.clamp(0, 1).toStringAsFixed(6)}',
  );
}

int _resolveStartIndex(
  List<TtsSegment> segments, {
  required String format,
  required int chapterIndex,
  required String? currentLocator,
  required TtsCursor? savedCursor,
}) {
  if (segments.isEmpty) return 0;
  if (savedCursor?.chapterIndex == chapterIndex) {
    final savedIndex = segments.indexWhere(
      (segment) => segment.id == savedCursor!.segmentId,
    );
    if (savedIndex >= 0) return savedIndex;
    currentLocator = savedCursor?.locator ?? currentLocator;
  }
  if (format == 'txt' || format == 'markdown') {
    final rawOffset = TextDocumentLocator.tryParse(currentLocator)?.rawStart;
    if (rawOffset != null) {
      final index = segments.indexWhere((segment) => segment.rawEnd > rawOffset);
      if (index >= 0) return index;
    }
    return 0;
  }
  final epub = EpubDocumentLocator.tryParse(
    currentLocator,
    fallbackChapterIndex: chapterIndex,
  );
  final ratio = epub?.location.scrollRatio;
  if (ratio != null) {
    final index = segments.indexWhere(
      (segment) => (_ratioLocator(segment.locatorEnd) ?? 0) >= ratio,
    );
    if (index >= 0) return index;
  }
  return 0;
}

double? _ratioLocator(String? locator) => locator?.startsWith('ratio:') == true
    ? double.tryParse(locator!.substring('ratio:'.length))
    : null;
