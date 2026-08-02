import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/services/backup_service.dart';
import 'package:tomoread/data/services/restore_service.dart';

void main() {
  late Directory root;
  late AppDatabase database;
  late BackupService backup;
  late RestoreService restore;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread_restore_');
    database = AppDatabase(
      pathProvider: () async => path.join(root.path, 'database', 'tomoread.db'),
    );
    final bookFile = File(
      path.join(root.path, 'library', 'books', 'book-hash.epub'),
    );
    await bookFile.parent.create(recursive: true);
    await bookFile.writeAsString('original book');
    final raw = await database.database;
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Original title',
      'author': '',
      'file_hash': 'book-hash',
      'file_path': bookFile.path,
      'format': 'epub',
      'progress': .25,
      'chapter_index': 0,
      'chapter_count': 1,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
    backup = BackupService(
      database: database,
      appVersion: '1.0.0+1',
      deviceId: 'device-test',
      rootProvider: () async => root,
    );
    restore = RestoreService(
      database: database,
      backupService: backup,
      rootProvider: () async => root,
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test('restores database and rebases managed book paths', () async {
    final archivePath = path.join(root.path, 'exports', 'library.tomoread.zip');
    await backup.create(destinationPath: archivePath);
    final raw = await database.database;
    await raw.update(
      'books',
      {'title': 'Changed title', 'progress': .9},
      where: 'id = ?',
      whereArgs: ['book-a'],
    );
    await File(
      path.join(root.path, 'library', 'books', 'book-hash.epub'),
    ).writeAsString('changed book');

    final result = await restore.restore(archivePath: archivePath);

    final restored = (await (await database.database).query(
      'books',
      where: 'id = ?',
      whereArgs: ['book-a'],
    )).single;
    expect(restored['title'], 'Original title');
    expect((restored['progress']! as num).toDouble(), .25);
    final restoredPath = restored['file_path']! as String;
    expect(await File(restoredPath).readAsString(), 'original book');
    expect(path.isWithin(root.path, restoredPath), isTrue);
    expect(await File(result.rollbackBackupPath).exists(), isTrue);
  });

  test('rejects a corrupted archive without changing the live library', () async {
    final archivePath = path.join(root.path, 'library.tomoread.zip');
    await File(archivePath).writeAsString('not a zip');

    await expectLater(
      restore.restore(archivePath: archivePath),
      throwsA(isA<RestoreException>()),
    );
    final rows = await (await database.database).query('books');
    expect(rows.single['title'], 'Original title');
  });
}
