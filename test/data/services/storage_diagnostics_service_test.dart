import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/services/storage_diagnostics_service.dart';

void main() {
  late Directory root;
  late AppDatabase database;
  late StorageDiagnosticsService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread_storage_');
    database = AppDatabase(
      pathProvider: () async => path.join(root.path, 'database', 'tomoread.db'),
    );
    final raw = await database.database;
    for (final value in {
      'library/books/book.epub': 'book',
      'library/books/orphan.epub': 'orphan',
      'library/extracted/hash/chapter.xhtml': 'cache',
      'library/imports/pending.epub': 'staging',
      'fonts/font.ttf': 'font',
    }.entries) {
      final file = File(path.join(root.path, value.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(value.value);
    }
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'file_path': path.join(root.path, 'library', 'books', 'book.epub'),
      'progress': 0,
      'chapter_index': 0,
      'chapter_count': 0,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
    await raw.insert('imported_fonts', {
      'id': 'font-a',
      'family': 'Test Font',
      'file_name': 'font.ttf',
      'file_path': path.join(root.path, 'fonts', 'font.ttf'),
      'file_hash': 'font-hash',
      'format': 'ttf',
      'source': 'test',
      'created_at': 1,
    });
    await raw.insert('word_cloud_cache', {
      'cache_key': 'cache-a',
      'book_id': 'book-a',
      'payload_json': '{"terms":[]}',
      'created_at': 1,
    });
    service = StorageDiagnosticsService(
      database: database,
      rootProvider: () async => root,
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test('reports protected and regenerable storage separately', () async {
    final reports = await service.inspect();

    expect(
      reports
          .firstWhere((report) => report.category == StorageCategory.epubCache)
          .regenerable,
      isTrue,
    );
    expect(
      reports
          .firstWhere(
            (report) => report.category == StorageCategory.managedBooks,
          )
          .regenerable,
      isFalse,
    );
    expect(
      reports
          .firstWhere(
            (report) => report.category == StorageCategory.managedBooks,
          )
          .orphanCount,
      1,
    );
  });

  test('cleanup ignores protected books, database, and fonts', () async {
    final plan = await service.planCleanup(StorageCategory.values);
    await service.executeCleanup(plan);

    expect(
      await Directory(path.join(root.path, 'library', 'extracted')).exists(),
      isFalse,
    );
    expect(
      await File(path.join(root.path, 'library', 'books', 'book.epub')).exists(),
      isTrue,
    );
    expect(
      await File(
        path.join(root.path, 'library', 'books', 'orphan.epub'),
      ).exists(),
      isTrue,
    );
    expect(await File(path.join(root.path, 'fonts', 'font.ttf')).exists(), isTrue);
    final raw = await database.database;
    expect(
      (await raw.query('word_cloud_cache')).length,
      0,
    );
  });

  test('deletes orphan files only after an explicit orphan plan', () async {
    final plan = await service.planCleanup(
      const [StorageCategory.managedBooks],
      includeConfirmedOrphans: true,
    );
    expect(plan.itemCount, 1);

    await service.executeCleanup(plan);

    expect(
      await File(
        path.join(root.path, 'library', 'books', 'orphan.epub'),
      ).exists(),
      isFalse,
    );
    expect(
      await File(path.join(root.path, 'library', 'books', 'book.epub')).exists(),
      isTrue,
    );
  });

  test('records cleanup without sensitive paths', () async {
    final plan = await service.planCleanup(StorageCategory.values);
    await service.executeCleanup(plan);

    final records = await service.recentCleanupRecords();
    expect(records, hasLength(1));
    expect(records.single.succeeded, isTrue);
  });
}
