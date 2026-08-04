import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/font_repository.dart';
import 'package:tomoread/data/services/font_catalog_service.dart';
import 'package:tomoread/domain/models/reading_font.dart';
import 'package:tomoread/features/settings/font_catalog_controller.dart';

void main() {
  late Directory root;
  late AppDatabase database;
  late FontRepository repository;
  late ProviderContainer container;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread_fonts_');
    database = AppDatabase(
      pathProvider: () async => path.join(root.path, 'database', 'tomoread.db'),
    );
    repository = FontRepository(
      database,
      supportDirectory: () async => root,
    );
    container = ProviderContainer(
      overrides: [
        fontRepositoryProvider.overrideWithValue(repository),
        fontCatalogServiceProvider.overrideWithValue(_FakeFontCatalog()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
      await root.delete(recursive: true);
    });
  });

  test('build loads system and imported fonts', () async {
    final fontDir = Directory(path.join(root.path, 'fonts'));
    await fontDir.create(recursive: true);
    final file = File(path.join(fontDir.path, 'font.ttf'));
    await file.writeAsString('font');
    await repository.importFile(file.path, licenseLabel: 'MIT');

    final state = await container.read(fontCatalogControllerProvider.future);
    expect(state.systemFonts.map((f) => f.family), contains('Arial'));
    expect(state.importedFonts, hasLength(1));
    expect(state.importedFonts.single.fileName, 'font.ttf');
  });

  test('delete removes an imported font and invalidates the state', () async {
    final fontDir = Directory(path.join(root.path, 'fonts'));
    await fontDir.create(recursive: true);
    final file = File(path.join(fontDir.path, 'delete.ttf'));
    await file.writeAsString('font');
    final font = await repository.importFile(file.path);
    await container.read(fontCatalogControllerProvider.future);
    final notifier = container.read(fontCatalogControllerProvider.notifier);

    await notifier.delete(font.id);

    final state = await container.read(fontCatalogControllerProvider.future);
    expect(state.importedFonts, isEmpty);
    expect(await repository.listImported(), isEmpty);
  });
}

class _FakeFontCatalog implements FontCatalogService {
  @override
  Future<List<SystemFontFamily>> listSystemFonts() async => const [
    SystemFontFamily(family: 'Arial'),
    SystemFontFamily(family: 'Noto Sans'),
  ];
}
