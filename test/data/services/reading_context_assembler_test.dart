import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/annotation_repository.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/services/reading_context_assembler.dart';
import 'package:tomoread/domain/models/content_chunk.dart';

void main() {
  test('assembles budgeted context without future chapter spoilers', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final raw = await database.database;
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'progress': 0.5,
      'chapter_index': 0,
      'chapter_count': 2,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
    final chunks = ContentChunkRepository(database);
    ContentChunk chunk(int chapter, String text) => ContentChunk(
      id: 'chunk-$chapter',
      bookId: 'book-a',
      chapterId: 'chapter-$chapter',
      chapterIndex: chapter,
      chapterTitle: 'Chapter $chapter',
      href: 'text:chapter-$chapter',
      locatorStart: 'text:v1|$chapter|0|0',
      locatorEnd: 'text:v1|$chapter|${text.length}|${text.length}',
      rawStart: 0,
      rawEnd: text.length,
      ordinal: chapter,
      text: text,
      textHash: 'hash-$chapter',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
    );
    await chunks.replaceForBook(
      bookId: 'book-a',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
      chunks: [chunk(0, 'current fact keyword'), chunk(1, 'future spoiler keyword')],
    );
    final assembler = ReadingContextAssembler(
      chunks: chunks,
      annotations: AnnotationRepository(database),
    );

    final bundle = await assembler.assemble(
      bookId: 'book-a',
      currentChapterIndex: 0,
      searchQuery: 'keyword',
      characterBudget: 1000,
    );

    expect(bundle.spoilerLimited, isTrue);
    expect(bundle.segments, isNotEmpty);
    expect(bundle.segments.every((segment) => segment.chapterIndex == 0), isTrue);
    expect(bundle.usedCharacters, lessThanOrEqualTo(1000));
    expect(bundle.contextHash, hasLength(64));
  });
}
