import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/services/content_chunk_service.dart';
import 'package:tomoread/data/services/epub_content_service.dart';
import 'package:tomoread/domain/models/text_chapter.dart';
import 'package:tomoread/features/assistant/content_index_controller.dart';

void main() {
  late AppDatabase database;
  late ContentChunkRepository repository;
  late ContentChunkService service;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = ContentChunkRepository(database);
    service = ContentChunkService(
      repository: repository,
      epubContent: const EpubContentService(),
    );
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
    addTearDown(database.close);
  });

  test('rebuildText delegates to the service and notifies onChanged', () async {
    var notified = 0;
    final controller = ContentIndexController(
      service: service,
      onChanged: () => notified++,
    );
    final text = '第一段内容。\n\n第二段内容。';

    await controller.rebuildText(
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

    expect(notified, 1);
    final chunks = await repository.listForBook('book-a');
    expect(chunks, isNotEmpty);
  });

  test('rebuildText ignores concurrent rebuilds for the same book', () async {
    final calls = <String>[];
    final gated = _GatedContentChunkService(
      delegate: service,
      onRebuildText: (bookId) => calls.add(bookId),
    );
    final controller = ContentIndexController(
      service: gated,
      onChanged: () {},
    );

    final first = controller.rebuildText(
      bookId: 'book-a',
      rawText: '正文',
      contentHash: 'hash-1',
      chapters: [
        TextChapter(
          id: 'c1',
          bookId: 'book-a',
          ordinal: 0,
          title: '章',
          rawStart: 0,
          rawEnd: 2,
          contentHash: 'h1',
        ),
      ],
    );
    final second = controller.rebuildText(
      bookId: 'book-a',
      rawText: '正文',
      contentHash: 'hash-2',
      chapters: [
        TextChapter(
          id: 'c1',
          bookId: 'book-a',
          ordinal: 0,
          title: '章',
          rawStart: 0,
          rawEnd: 2,
          contentHash: 'h2',
        ),
      ],
    );
    await first;
    await second;

    expect(calls, ['book-a']);
  });
}

class _GatedContentChunkService extends ContentChunkService {
  _GatedContentChunkService({
    required this.delegate,
    required this.onRebuildText,
  }) : super(
         repository: delegate.repository,
         epubContent: delegate.epubContent,
       );

  final ContentChunkService delegate;
  final void Function(String bookId) onRebuildText;

  @override
  Future<void> rebuildText({
    required String bookId,
    required String rawText,
    required String contentHash,
    required List<TextChapter> chapters,
  }) async {
    onRebuildText(bookId);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
