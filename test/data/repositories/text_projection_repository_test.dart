import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/text_projection_repository.dart';
import 'package:tomoread/domain/models/display_projection.dart';

void main() {
  late AppDatabase database;
  late TextProjectionRepository repository;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = TextProjectionRepository(database);
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

  test('resolves per-book settings over global defaults', () async {
    await repository.saveSettings(
      const TextProjectionSettings(
        chineseConversion: ChineseConversionMode.traditionalToSimplified,
      ),
    );
    expect(
      (await repository.loadSettings('book-a')).chineseConversion,
      ChineseConversionMode.traditionalToSimplified,
    );

    await repository.saveSettings(
      const TextProjectionSettings(widthMode: CharacterWidthMode.toHalfWidth),
      bookId: 'book-a',
    );
    expect(
      (await repository.loadSettings('book-a')).widthMode,
      CharacterWidthMode.toHalfWidth,
    );

    await repository.clearBookSettings('book-a');
    expect(
      (await repository.loadSettings('book-a')).chineseConversion,
      ChineseConversionMode.traditionalToSimplified,
    );
  });

  test('stores global and book literal rules in deterministic order', () async {
    await repository.saveRule(
      name: 'global',
      findText: 'alpha',
      replaceText: 'A',
      priority: 100,
    );
    await repository.saveRule(
      bookId: 'book-a',
      name: 'book',
      findText: 'alpha beta',
      replaceText: 'B',
      priority: 0,
    );

    final rules = await repository.listRules('book-a');
    expect(rules, hasLength(2));
    expect(rules.first.bookId, 'book-a');
    expect(rules.last.bookId, isNull);
  });
}
