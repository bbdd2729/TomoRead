import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/services/book_import_service.dart';
import 'package:tomoread/domain/models/book_import.dart';

void main() {
  late AppDatabase database;
  late BookRepository repository;
  late Directory root;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = BookRepository(database);
    root = await Directory.systemTemp.createTemp('tomoread-import-test-');
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('copies, hashes, parses, and deduplicates an EPUB import', () async {
    final source = File('${root.path}${Platform.pathSeparator}source.epub');
    await source.writeAsBytes(_minimalEpub());
    final service = BookImportService(
      repository: repository,
      libraryRootProvider: () async => root,
    );

    final imported = await service.importEpubFile(source.path);
    expect(imported.status, BookImportStatus.imported);
    expect(imported.book?.title, 'Imported title');
    expect(await File(imported.book!.filePath).exists(), isTrue);
    expect(await File(imported.book!.coverPath!).exists(), isTrue);
    expect(await repository.listBooks(), hasLength(1));

    final duplicate = await service.importEpubFile(source.path);
    expect(duplicate.status, BookImportStatus.duplicate);
    expect(await repository.listBooks(), hasLength(1));
  });

  test('imports UTF-8 text and persists the detected chapter catalog', () async {
    final source = File('${root.path}${Platform.pathSeparator}novel.txt');
    await source.writeAsString('''序章
开场
第一章 起点
正文
第二章 继续
结尾''');
    final service = BookImportService(
      repository: repository,
      libraryRootProvider: () async => root,
    );

    final imported = await service.importTextFile(source.path);

    expect(imported.status, BookImportStatus.imported);
    expect(imported.book?.format, 'txt');
    expect(imported.book!.chapterCount, 3);
    expect(await File(imported.book!.filePath).exists(), isTrue);
    final sql = await database.database;
    final profile = await sql.query('text_content_profiles');
    final chapters = await sql.query(
      'text_chapters',
      orderBy: 'ordinal ASC',
    );
    expect(profile.single['encoding'], 'utf-8');
    expect(chapters.map((row) => row['title']), ['序章', '第一章 起点', '第二章 继续']);
  });

  test('preview identifies library and in-batch duplicates before import', () async {
    final first = File('${root.path}${Platform.pathSeparator}first.txt');
    final second = File('${root.path}${Platform.pathSeparator}second.txt');
    final existing = File('${root.path}${Platform.pathSeparator}existing.txt');
    await first.writeAsString('same batch content');
    await second.writeAsString('same batch content');
    await existing.writeAsString('already imported content');
    final service = BookImportService(
      repository: repository,
      libraryRootProvider: () async => root,
    );
    expect(
      (await service.importTextFile(existing.path)).status,
      BookImportStatus.imported,
    );

    final preview = await service.previewSources([
      ImportSource(kind: ImportSourceKind.desktopDrop, location: first.path),
      ImportSource(kind: ImportSourceKind.desktopDrop, location: second.path),
      ImportSource(kind: ImportSourceKind.desktopDrop, location: existing.path),
    ]);

    expect(preview.supportedCount, 1);
    expect(preview.duplicateCount, 2);
    expect(
      preview.items.where(
        (item) => item.reason == '书库中已存在相同内容',
      ),
      hasLength(1),
    );
  });
}

List<int> _minimalEpub() {
  final archive = Archive();
  void add(String name, String source) {
    final bytes = utf8.encode(source);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  );
  add(
    'OPS/book.opf',
    '''<package version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
<metadata><dc:title>Imported title</dc:title><dc:creator>Imported author</dc:creator></metadata>
<manifest>
  <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
  <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
</manifest>
<spine><itemref idref="chapter"/></spine>
</package>''',
  );
  add('OPS/chapter.xhtml', '<html><body>Chapter</body></html>');
  archive.addFile(ArchiveFile('OPS/cover.png', 3, [9, 8, 7]));
  return ZipEncoder().encode(archive);
}
