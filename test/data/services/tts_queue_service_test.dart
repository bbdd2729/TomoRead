import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/tts_queue_service.dart';
import 'package:tomoread/domain/models/content_chunk.dart';
import 'package:tomoread/domain/models/document_locator.dart';

void main() {
  ContentChunk chunk(String text) => ContentChunk(
    id: 'chunk-1',
    bookId: 'book-1',
    chapterId: 'chapter-1',
    chapterIndex: 0,
    chapterTitle: '第一章',
    href: 'text:chapter-1',
    locatorStart: 'text:v1|0|100|100',
    locatorEnd: 'text:v1|0|${100 + text.length}|${100 + text.length}',
    rawStart: 100,
    rawEnd: 100 + text.length,
    ordinal: 0,
    text: text,
    textHash: 'text-hash',
    contentHash: 'content-hash',
    parserVersion: 1,
    indexVersion: 1,
  );

  test('splits structured chunks into locator-backed sentences', () {
    final segments = buildTtsSegmentsFromChunks(
      [chunk('第一句。第二句！\n第三句？')],
      format: 'txt',
    );

    expect(segments.map((segment) => segment.text), [
      '第一句。',
      '第二句！',
      '第三句？',
    ]);
    expect(
      TextDocumentLocator.tryParse(segments.first.locatorStart)?.rawStart,
      100,
    );
    expect(
      TextDocumentLocator.tryParse(segments.last.locatorEnd)?.rawEnd,
      113,
    );
  });

  test('caps a sentence at a stable soft boundary', () {
    final ranges = splitTtsSentenceRanges(
      'alpha beta gamma delta epsilon',
      maxLength: 18,
    );

    expect(ranges.length, 2);
    expect('alpha beta gamma delta epsilon'.substring(ranges.first.$1, ranges.first.$2), 'alpha beta gamma ');
  });
}
