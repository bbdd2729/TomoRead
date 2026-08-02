import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/visual_artifact_repository.dart';
import 'package:tomoread/data/services/word_frequency_service.dart';
import 'package:tomoread/data/services/word_cloud_layout_service.dart';
import 'package:tomoread/domain/models/content_chunk.dart';
import 'package:tomoread/domain/models/visual_artifact.dart';

void main() {
  test('tokenizes ASCII words and CJK bigrams while removing stopwords', () {
    final terms = countWordFrequencies([
      '我们阅读阅读世界 the reading reading',
    ]);
    final frequencies = {for (final term in terms) term.term: term.frequency};

    expect(frequencies['阅读'], 2);
    expect(frequencies['reading'], 2);
    expect(frequencies['世界'], 1);
    expect(frequencies.containsKey('我们'), isFalse);
    expect(frequencies.containsKey('the'), isFalse);
  });

  test('cache key includes scope, range, and tokenizer options', () {
    final base = buildWordCloudCacheKey(
      bookId: 'book-a',
      contentHash: 'hash-a',
      scope: VisualArtifactScope.currentChapter,
      currentChapterIndex: 2,
      minimumLength: 2,
      maximumTerms: 100,
    );
    final otherRange = buildWordCloudCacheKey(
      bookId: 'book-a',
      contentHash: 'hash-a',
      scope: VisualArtifactScope.readChapters,
      currentChapterIndex: 2,
      minimumLength: 2,
      maximumTerms: 100,
    );
    final otherLimit = buildWordCloudCacheKey(
      bookId: 'book-a',
      contentHash: 'hash-a',
      scope: VisualArtifactScope.currentChapter,
      currentChapterIndex: 2,
      minimumLength: 2,
      maximumTerms: 60,
    );

    expect(base, isNot(otherRange));
    expect(base, isNot(otherLimit));
  });

  test('builds deterministic bounded word-cloud layout rows', () {
    final request = <String, Object>{
      'terms': [
        {'term': '阅读', 'frequency': 4},
        {'term': '世界', 'frequency': 2},
      ],
      'seed': 42,
      'width': 800.0,
      'height': 500.0,
    };
    final first = computeWordCloudLayoutRows(request);
    final second = computeWordCloudLayoutRows(request);

    expect(first, isNotEmpty);
    expect(second, first);
    expect((first.first['x']! as num).toDouble(), inInclusiveRange(0, 800));
    expect((first.first['y']! as num).toDouble(), inInclusiveRange(0, 500));
  });

  test('runs word-cloud layout through a background isolate', () async {
    final entries = await const WordCloudLayoutService().layout(
      WordCloudPayload(
        terms: const [WordCloudTerm(term: '阅读', frequency: 4)],
        scope: VisualArtifactScope.currentChapter,
        layoutSeed: 7,
        contentHash: 'hash-a',
        tokenizerVersion: 1,
        stopwordVersion: 1,
        generatedAt: DateTime.utc(2026, 8, 2),
      ),
      width: 800,
      height: 500,
    );

    expect(entries.single.term, '阅读');
  });

  test('reuses cached terms when only the layout seed changes', () async {
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
    final chunks = ContentChunkRepository(database);
    await chunks.replaceForBook(
      bookId: 'book-a',
      contentHash: 'book-hash',
      parserVersion: 1,
      indexVersion: 1,
      chunks: const [
        ContentChunk(
          id: 'chunk-a',
          bookId: 'book-a',
          chapterId: 'chapter-a',
          chapterIndex: 0,
          chapterTitle: 'Chapter',
          href: 'text:chapter-a',
          locatorStart: 'text:v1|0|0|0',
          locatorEnd: 'text:v1|0|8|8',
          rawStart: 0,
          rawEnd: 8,
          ordinal: 0,
          text: '阅读阅读世界',
          textHash: 'chunk-hash',
          contentHash: 'book-hash',
          parserVersion: 1,
          indexVersion: 1,
        ),
      ],
    );
    final artifacts = VisualArtifactRepository(database);
    final service = WordFrequencyService(
      chunks: chunks,
      artifacts: artifacts,
    );

    final first = await service.generate(
      bookId: 'book-a',
      bookTitle: 'Book',
      scope: VisualArtifactScope.currentChapter,
      currentChapterIndex: 0,
      layoutSeed: 1,
    );
    final second = await service.generate(
      bookId: 'book-a',
      bookTitle: 'Book',
      scope: VisualArtifactScope.currentChapter,
      currentChapterIndex: 0,
      layoutSeed: 2,
    );

    expect(second.payload.terms.first.term, first.payload.terms.first.term);
    expect(second.payload.layoutSeed, 2);
    final cacheRows = await raw.rawQuery(
      'SELECT COUNT(*) AS count FROM word_cloud_cache',
    );
    expect(cacheRows.single['count'], 1);
  });
}
