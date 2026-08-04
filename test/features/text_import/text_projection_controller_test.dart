import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/text_projection_repository.dart';
import 'package:tomoread/domain/models/display_projection.dart';
import 'package:tomoread/features/text_import/text_projection_controller.dart';

void main() {
  late AppDatabase database;
  late TextProjectionRepository repository;
  late TextProjectionController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = TextProjectionRepository(database);
    final container = ProviderContainer(
      overrides: [
        textProjectionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    controller = TextProjectionController(
      repository: repository,
      onChanged: () {},
    );
  });

  test('saveSettings persists a book-level projection override', () async {
    await controller.saveSettings(
      const TextProjectionSettings(
        chineseConversion: ChineseConversionMode.traditionalToSimplified,
        convertLetters: false,
      ),
      bookId: 'book-a',
    );

    final settings = await repository.loadSettings('book-a');
    expect(
      settings.chineseConversion,
      ChineseConversionMode.traditionalToSimplified,
    );
    expect(settings.convertLetters, isFalse);
  });

  test('clearBookSettings removes the book override', () async {
    await controller.saveSettings(
      const TextProjectionSettings(
        chineseConversion: ChineseConversionMode.simplifiedToTraditional,
      ),
      bookId: 'book-a',
    );
    await controller.clearBookSettings('book-a');

    final settings = await repository.loadSettings('book-a');
    expect(settings.enabled, isFalse);
  });

  test('saveRule creates and deleteRule removes a display rule', () async {
    await controller.saveRule(
      bookId: 'book-a',
      name: '替换术语',
      findText: 'old term',
      replaceText: 'new term',
    );

    final rules = await repository.listRules('book-a');
    expect(rules, hasLength(1));
    expect(rules.single.findText, 'old term');

    await controller.deleteRule(rules.single.id);
    expect(await repository.listRules('book-a'), isEmpty);
  });

  test('saveRule rejects invalid rule names', () async {
    await expectLater(
      controller.saveRule(
        name: '',
        findText: 'x',
        replaceText: 'y',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
