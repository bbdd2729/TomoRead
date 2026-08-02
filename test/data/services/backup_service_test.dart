import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/services/backup_service.dart';
import 'package:tomoread/domain/models/backup_manifest.dart';

void main() {
  late Directory root;
  late AppDatabase database;
  late BackupService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread_backup_');
    final databasePath = path.join(root.path, 'live', 'tomoread.db');
    database = AppDatabase(pathProvider: () async => databasePath);
    final raw = await database.database;
    final book = File(path.join(root.path, 'library', 'books', 'book-a.epub'));
    await book.parent.create(recursive: true);
    await book.writeAsString('book bytes');
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'file_hash': 'book-hash',
      'file_path': book.path,
      'format': 'epub',
      'progress': .4,
      'chapter_index': 0,
      'chapter_count': 1,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
    final font = File(path.join(root.path, 'fonts', 'font-a.ttf'));
    await font.parent.create(recursive: true);
    await font.writeAsString('font bytes');
    await raw.insert('imported_fonts', {
      'id': 'font-a',
      'family': 'Test Font',
      'file_name': 'font-a.ttf',
      'file_path': font.path,
      'file_hash': 'font-hash',
      'format': 'ttf',
      'source': font.path,
      'created_at': 1,
    });
    service = BackupService(
      database: database,
      appVersion: '0.1.0',
      deviceId: 'device-test',
      rootProvider: () async => root,
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test('creates and validates a versioned backup with managed files', () async {
    final destination = path.join(root.path, 'exports', 'library.tomoread.zip');

    final manifest = await service.create(destinationPath: destination);
    final verified = await service.validate(destination);

    expect(manifest.appVersion, '0.1.0');
    expect(verified.deviceId, 'device-test');
    expect(
      verified.entries.map((entry) => entry.path),
      containsAll([
        'database/tomoread.db',
        'books/book-a/book-hash.epub',
        'fonts/font-a/font-hash.ttf',
      ]),
    );
    expect(verified.contentSha256, manifest.contentSha256);
  });

  test('rejects a backup whose checksummed payload was modified', () async {
    final destination = path.join(root.path, 'library.tomoread.zip');
    await service.create(destinationPath: destination);
    final archive = ZipDecoder().decodeBytes(
      await File(destination).readAsBytes(),
    );
    final rebuilt = Archive();
    for (final file in archive.files.where((entry) => entry.isFile)) {
      final bytes = file.name == 'books/book-a/book-hash.epub'
          ? utf8.encode('tampered')
          : file.content as List<int>;
      rebuilt.addFile(ArchiveFile(file.name, bytes.length, bytes));
    }
    await File(destination).writeAsBytes(ZipEncoder().encode(rebuilt));

    expect(
      () => service.validate(destination),
      throwsA(isA<BackupException>()),
    );
  });

  test('rejects a future manifest schema', () {
    expect(
      () => BackupManifest.fromJson({
        'format': BackupManifest.format,
        'schemaVersion': 99,
      }),
      throwsFormatException,
    );
  });
}
