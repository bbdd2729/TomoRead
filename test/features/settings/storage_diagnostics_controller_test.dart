import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/services/storage_diagnostics_service.dart';
import 'package:tomoread/features/settings/storage_diagnostics_controller.dart';

void main() {
  late Directory root;
  late AppDatabase database;
  late StorageDiagnosticsService service;
  late ProviderContainer container;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread_diag_');
    database = AppDatabase(
      pathProvider: () async => path.join(root.path, 'database', 'tomoread.db'),
    );
    final raw = await database.database;
    final bookPath = path.join(root.path, 'library', 'books', 'book.epub');
    final bookFile = File(bookPath);
    await bookFile.parent.create(recursive: true);
    await bookFile.writeAsString('book');
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'file_path': bookPath,
      'progress': 0,
      'chapter_index': 0,
      'chapter_count': 0,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
    service = StorageDiagnosticsService(
      database: database,
      rootProvider: () async => root,
    );
    container = ProviderContainer(
      overrides: [
        storageDiagnosticsServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
      await root.delete(recursive: true);
    });
  });

  test('build inspects storage and reports protected books', () async {
    final state = await container.read(storageDiagnosticsControllerProvider.future);
    expect(state.reports, isNotEmpty);
    final books = state.reports.firstWhere(
      (report) => report.category == StorageCategory.managedBooks,
    );
    expect(books.regenerable, isFalse);
    expect(books.fileCount, 1);
  });

  test('refresh reloads reports without clearing the state', () async {
    await container.read(storageDiagnosticsControllerProvider.future);
    final notifier = container.read(storageDiagnosticsControllerProvider.notifier);

    await notifier.refresh();

    final state = container.read(storageDiagnosticsControllerProvider).requireValue;
    expect(state.reports, isNotEmpty);
  });

  test('planRegenerableCleanup returns a non-empty plan', () async {
    final notifier = container.read(storageDiagnosticsControllerProvider.notifier);
    await container.read(storageDiagnosticsControllerProvider.future);

    final plan = await notifier.planRegenerableCleanup();
    expect(plan.itemCount, greaterThanOrEqualTo(0));
  });

  test('execute applies a cleanup plan and updates lastCleanup', () async {
    final notifier = container.read(storageDiagnosticsControllerProvider.notifier);
    await container.read(storageDiagnosticsControllerProvider.future);

    final plan = await notifier.planRegenerableCleanup();
    await notifier.execute(plan);

    final state = container.read(storageDiagnosticsControllerProvider).requireValue;
    expect(state.cleaning, isFalse);
    expect(state.error, isNull);
  });

  test('execute surfaces a service failure as an error state', () async {
    final failing = FailingStorageDiagnosticsService(
      database: database,
      rootProvider: () async => root,
    );
    final failingContainer = ProviderContainer(
      overrides: [
        storageDiagnosticsServiceProvider.overrideWithValue(failing),
      ],
    );
    addTearDown(failingContainer.dispose);
    final notifier = failingContainer.read(storageDiagnosticsControllerProvider.notifier);
    await failingContainer.read(storageDiagnosticsControllerProvider.future);

    await notifier.execute(const StorageCleanupPlan(
      categories: [StorageCategory.epubCache],
      bytes: 0,
      itemCount: 0,
    ));

    final state = failingContainer.read(storageDiagnosticsControllerProvider).requireValue;
    expect(state.cleaning, isFalse);
    expect(state.error, isNotNull);
  });
}

class FailingStorageDiagnosticsService extends StorageDiagnosticsService {
  FailingStorageDiagnosticsService({
    required super.database,
    super.rootProvider,
  });

  @override
  Future<StorageCleanupRecord> executeCleanup(StorageCleanupPlan plan) async {
    throw StateError('cleanup failed');
  }
}
