import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/domain/models/content_chunk.dart';

void main() {
  late AppDatabase database;
  late ContentChunkRepository repository;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = ContentChunkRepository(database);
    final raw = await database.database;
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'progress': 0.0,
      'chapter_index': 0,
      'chapter_count': 2,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
  });

  tearDown(() => database.close());

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

  test('replaces chunks atomically and searches within spoiler boundary', () async {
    await repository.replaceForBook(
      bookId: 'book-a',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
      chunks: [chunk(0, 'visible keyword'), chunk(1, 'future keyword')],
    );

    expect((await repository.loadState('book-a'))?.status, ContentIndexStatus.ready);
    final visible = await repository.search(
      bookId: 'book-a',
      query: 'keyword',
      maxChapterIndex: 0,
    );
    expect(visible, hasLength(1));
    expect(visible.single.chunk.chapterIndex, 0);
    final beforeCurrentOffset = await repository.search(
      bookId: 'book-a',
      query: 'keyword',
      maxChapterIndex: 0,
      maxRawOffset: 5,
    );
    expect(beforeCurrentOffset, isEmpty);
    expect(await repository.characterCountForBook('book-a'), 29);
  });
}
