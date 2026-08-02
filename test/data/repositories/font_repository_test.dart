import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/font_repository.dart';
import 'package:tomoread/data/repositories/settings_repository.dart';
import 'package:tomoread/domain/models/reading_font.dart';
import 'package:tomoread/domain/models/reading_settings.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late FontRepository fonts;

  setUp(() async {
    database = AppDatabase.inMemory();
    directory = await Directory.systemTemp.createTemp('tomoread-fonts-');
    fonts = FontRepository(database, supportDirectory: () async => directory);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('imports fonts by hash and replaces references before deletion', () async {
    final source = File(
      '${directory.path}${Platform.pathSeparator}Sample Font.woff2',
    );
    await source.writeAsBytes([0x77, 0x4f, 0x46, 0x32, 1, 2, 3, 4]);

    final imported = await fonts.importFile(
      source.path,
      licenseLabel: 'User supplied',
    );
    final duplicate = await fonts.importFile(source.path);

    expect(duplicate.id, imported.id);
    expect(imported.family, 'Sample Font');
    expect(imported.format, 'woff2');
    expect(await File(imported.filePath).exists(), isTrue);

    final settings = SettingsRepository(database);
    await settings.saveReadingSettings(ReadingSettings(font: imported.ref));
    final usage = await fonts.references(imported.id);
    expect(usage.global, isTrue);

    await expectLater(
      fonts.delete(imported.id),
      throwsA(isA<ImportedFontReferenceException>()),
    );
    await fonts.delete(imported.id, replacement: ReadingFontRef.serif);

    expect(await fonts.findById(imported.id), isNull);
    expect((await settings.load()).readingSettings.font, ReadingFontRef.serif);
    expect(await File(imported.filePath).exists(), isFalse);
  });
}
