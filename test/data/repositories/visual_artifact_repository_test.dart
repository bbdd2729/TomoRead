import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/visual_artifact_repository.dart';
import 'package:tomoread/domain/models/visual_artifact.dart';

void main() {
  late AppDatabase database;
  late VisualArtifactRepository repository;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = VisualArtifactRepository(database);
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
  });

  tearDown(() => database.close());

  test('persists, lists, and deletes visual artifacts', () async {
    final artifact = await repository.save(
      bookId: 'book-a',
      kind: VisualArtifactKind.wordCloud,
      scope: VisualArtifactScope.currentChapter,
      title: 'Book · 词云',
      contentHash: 'hash-a',
      payload: const {'terms': <Object>[]},
    );

    expect((await repository.findById(artifact.id))?.title, 'Book · 词云');
    expect(await repository.listForBook('book-a'), hasLength(1));

    await repository.delete(artifact.id);
    expect(await repository.findById(artifact.id), isNull);
  });

  test('round-trips the local word-frequency cache', () async {
    final payload = WordCloudPayload(
      terms: const [WordCloudTerm(term: '阅读', frequency: 3)],
      scope: VisualArtifactScope.readChapters,
      layoutSeed: 8,
      contentHash: 'hash-a',
      tokenizerVersion: 1,
      stopwordVersion: 1,
      generatedAt: DateTime.utc(2026, 8, 2),
    );
    await repository.saveWordCloudCache(
      cacheKey: 'cache-a',
      bookId: 'book-a',
      payload: payload,
    );

    final restored = await repository.loadWordCloudCache('cache-a');
    expect(restored?.terms.single.term, '阅读');
    expect(restored?.terms.single.frequency, 3);
    expect(restored?.colorPalette, defaultWordCloudPalette);
  });
}
