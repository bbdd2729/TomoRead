import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/data/services/epub_extraction_service.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread_epub_extract_');
  });

  tearDown(() => root.delete(recursive: true));

  test('extracts EPUB resources into a stable per-book directory', () async {
    final source = File(path.join(root.path, 'book.epub'));
    await source.writeAsBytes(_buildEpub());
    final service = EpubExtractionService(
      libraryRootProvider: () async => root,
    );
    final book = LibraryBook(
      id: 'book-a',
      fileHash: 'book-a',
      title: 'Book',
      author: '',
      filePath: source.path,
      progress: 0,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 1,
      direction: ReadingDirection.ltr,
    );

    final directory = await service.ensureExtracted(book);

    expect(
      await File(path.join(directory, 'OPS', 'chapter.xhtml')).readAsString(),
      contains('正文'),
    );
    expect(
      await File(
        path.join(directory, 'OPS', 'styles', 'book.css'),
      ).readAsString(),
      contains('font-size'),
    );
    expect(await File(path.join(directory, '.complete')).exists(), isTrue);
    expect(await service.ensureExtracted(book), directory);
  });
}

List<int> _buildEpub() {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText('OPS/chapter.xhtml', '<html><body>正文</body></html>');
  addText('OPS/styles/book.css', 'body { font-size: 18px; }');
  return ZipEncoder().encode(archive);
}
