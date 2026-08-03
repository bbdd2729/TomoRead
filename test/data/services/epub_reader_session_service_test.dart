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
      expect(
        sessionManifest['runtimeVersion'],
        EpubReaderSessionService.runtimeVersion,
      );
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
        EpubReaderSessionService.runtimeVersion,
      );
    },
  );

  test('bundles the Foliate runtime license asset', () async {
    final license = await rootBundle.loadString(
      'assets/epub_reader_runtime/licenses/foliate-js.MIT.txt',
    );

    expect(license, contains('MIT License'));
  });

  test('bundles the safe annotation locator parser', () async {
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(runtime, contains('rangeForCfi(doc, locator.slice(4))'));
    expect(runtime, isNot(contains('annotation.loc.slice')));
  });

  test('keeps the cached runtime marker aligned with the JS protocol', () async {
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(
      runtime,
      contains(
        "const runtimeVersion = '${EpubReaderSessionService.runtimeVersion}'",
      ),
    );
  });

  test('reports a bridge boot event before EPUB commands run', () async {
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(runtime, contains("postMessage({ type: 'runtimeBoot', runtimeVersion })"));
  });

  test('supports EPUB spine documents without a head element', () async {
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(runtime, contains('const ensureRuntimeStyle = (doc, id) =>'));
    expect(runtime, contains("host = doc.createElement('head')"));
    expect(runtime, isNot(contains('doc.head.append(style)')));
  });

  test('keeps optional EPUB document enhancements from blocking chapter load',
      () async {
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(runtime, contains('const runDocumentEnhancement = (context, action) =>'));
    expect(runtime, contains("runDocumentEnhancement('annotations'"));
    expect(runtime, contains("type: 'runtimeWarning'"));
    expect(runtime, contains("type: 'commandFailed', id, command: type, message, stack"));
  });

  test('loads the Android file runtime without ES module imports', () async {
    final entryPoint = await rootBundle.loadString(
      'assets/epub_reader_runtime/index.html',
    );
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(entryPoint, contains('<script src="./foliate-paginator.js">'));
    expect(entryPoint, contains('<script src="./epubcfi.js">'));
    expect(entryPoint, contains('<script src="./tomoread-reader.js">'));
    expect(entryPoint, isNot(contains('type="module"')));
    expect(runtime, isNot(contains("import './foliate-paginator.js'")));
    expect(runtime, contains('globalThis.TomoReadEpubCfi'));
  });

  test('waits for an Android iframe document before running Foliate hooks',
      () async {
    final paginator = await rootBundle.loadString(
      'assets/epub_reader_runtime/foliate-paginator.js',
    );

    expect(paginator, contains('if (!loadedDocument) return'));
    expect(
      paginator,
      contains('otherwise the paginator passes null into afterLoad().'),
    );
  });

  test('EPUB automatic scrolling uses elapsed animation-frame time', () async {
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(runtime, contains("case 'startAutoScroll':"));
    expect(runtime, contains('timestamp - autoScrollStartedAt'));
    expect(runtime, contains("stopAutoScroll('selection')"));
    expect(runtime, isNot(contains('setInterval(startAutoScroll')));
  });

  test('keeps TTS sentence emphasis separate from search highlights', () async {
    final runtime = await rootBundle.loadString(
      'assets/epub_reader_runtime/tomoread-reader.js',
    );

    expect(runtime, contains('setTtsHighlight'));
    expect(runtime, contains("highlights.set('tomoread-tts', ranges)"));
    expect(runtime, contains("highlights.set('tomoread-search', ranges)"));
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
