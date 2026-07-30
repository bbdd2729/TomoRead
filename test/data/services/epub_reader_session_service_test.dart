import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/data/services/epub_extraction_service.dart';
import 'package:tomoread/data/services/epub_reader_session_service.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread_reader_session_');
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'prepares a versioned runtime beside extracted EPUB resources',
    () async {
      final source = File(path.join(root.path, 'book.epub'));
      await source.writeAsBytes(_buildEpub());
      final extractionService = EpubExtractionService(
        libraryRootProvider: () async => root,
      );
      final service = EpubReaderSessionService(
        extractionService: extractionService,
        runtimeAssetLoader: (assetKey) async => 'asset:$assetKey',
      );
      final book = _book(source.path);
      const manifest = EpubManifest(
        opfPath: 'OPS/package.opf',
        version: '3.0',
        direction: ReadingDirection.ltr,
        spine: [
          EpubSpineItem(
            id: 'chapter-1',
            href: 'OPS/chapter.xhtml',
            linear: true,
          ),
        ],
        toc: [
          EpubTocItem(
            title: 'Chapter 1',
            href: 'OPS/chapter.xhtml',
            spineIndex: 0,
          ),
        ],
      );

      final session = await service.prepare(book: book, manifest: manifest);

      expect(
        await File(session.entryPointPath).readAsString(),
        'asset:assets/epub_reader_runtime/index.html',
      );
      expect(
        await File(
          path.join(session.runtimeDirectoryPath, 'foliate-paginator.js'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          path.join(session.directoryPath, 'OPS', 'chapter.xhtml'),
        ).exists(),
        isTrue,
      );
      expect(
        session.virtualEntryPointUrl('reader.tomoread'),
        'https://reader.tomoread/.tomoread-reader/index.html',
      );

      final sessionManifest =
          jsonDecode(await File(session.manifestPath).readAsString())
              as Map<String, dynamic>;
      expect(sessionManifest['bookId'], book.id);
      expect(sessionManifest['resourceBase'], '../');
      expect(
        (sessionManifest['manifest'] as Map<String, dynamic>)['opfPath'],
        manifest.opfPath,
      );

      await service.prepare(book: book, manifest: manifest);
      expect(
        await File(
          path.join(session.runtimeDirectoryPath, '.runtime-version'),
        ).readAsString(),
        '7',
      );
    },
  );

  test('bundles the Foliate runtime license asset', () async {
    final license = await rootBundle.loadString(
      'assets/epub_reader_runtime/licenses/foliate-js.MIT.txt',
    );

    expect(license, contains('MIT License'));
  });
}

LibraryBook _book(String filePath) => LibraryBook(
  id: 'book-a',
  fileHash: 'book-a',
  title: 'Book',
  author: '',
  filePath: filePath,
  progress: 0,
  importedAt: DateTime(2026),
  format: 'epub',
  chapterCount: 1,
  direction: ReadingDirection.ltr,
);

List<int> _buildEpub() {
  final archive = Archive();
  const content = '<html><body>Text</body></html>';
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile('OPS/chapter.xhtml', bytes.length, bytes));
  return ZipEncoder().encode(archive);
}
