import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/services/content_chunk_service.dart';
import 'package:tomoread/data/services/epub_content_service.dart';
import 'package:tomoread/domain/models/text_chapter.dart';

void main() {
  test('builds text chunks with original UTF-16 locators', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final raw = await database.database;
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'progress': 0.0,
      'chapter_index': 0,
      'chapter_count': 1,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
    final repository = ContentChunkRepository(database);
    final service = ContentChunkService(
      repository: repository,
      epubContent: const EpubContentService(),
    );
    final text =
        '${List.filled(ContentChunkService.maxChunkLength + 200, '字').join()}'
        '\n\n第二段。';
    await service.rebuildText(
      bookId: 'book-a',
      rawText: text,
      contentHash: 'content-hash',
      chapters: [
        TextChapter(
          id: 'chapter-a',
          bookId: 'book-a',
          ordinal: 0,
          title: '第一章',
          rawStart: 0,
          rawEnd: text.length,
          contentHash: 'chapter-hash',
        ),
      ],
    );

    final chunks = await repository.listForBook('book-a');
    expect(chunks.length, greaterThan(1));
    expect(chunks.first.locatorStart, 'text:v1|0|0|0');
    expect(chunks.last.rawEnd, text.length);
  });
}
