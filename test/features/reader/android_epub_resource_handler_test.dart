import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/features/reader/android_epub_resource_handler.dart';

void main() {
  group('AndroidEpubResourceHandler', () {
    late Directory temporaryDirectory;
    late Directory bookDirectory;
    late AndroidEpubResourceHandler handler;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'tomoread-epub-resource-test-',
      );
      bookDirectory = Directory('${temporaryDirectory.path}/book');
      await Directory('${bookDirectory.path}/.tomoread-reader').create(
        recursive: true,
      );
      await Directory('${bookDirectory.path}/OEBPS/Text').create(
        recursive: true,
      );
      await File('${bookDirectory.path}/.tomoread-reader/index.html')
          .writeAsString('<main>runtime</main>');
      await File('${bookDirectory.path}/OEBPS/Text/chapter.xhtml').writeAsString(
        '<html><body>chapter</body></html>',
      );
      handler = AndroidEpubResourceHandler(
        bookId: 'book-a',
        bookDirectoryPath: bookDirectory.path,
      );
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test('serves the runtime from the virtual origin', () async {
      final response = await handler.load(handler.runtimeEntryPoint);

      expect(response.statusCode, 200);
      expect(response.contentType, 'application/xhtml+xml');
      expect(String.fromCharCodes(response.data), contains('runtime'));
    });

    test('serves the active book and keeps its MIME type', () async {
      final response = await handler.load(
        Uri.parse('epub://localhost/book/book-a/OEBPS/Text/chapter.xhtml'),
      );

      expect(response.statusCode, 200);
      expect(response.contentType, 'application/xhtml+xml');
      expect(String.fromCharCodes(response.data), contains('chapter'));
    });

    test('rejects a request for another book', () async {
      final response = await handler.load(
        Uri.parse('epub://localhost/book/other-book/OEBPS/Text/chapter.xhtml'),
      );

      expect(response.statusCode, 403);
    });

    test('rejects a non-GET request', () async {
      final response = await handler.load(
        Uri.parse('epub://localhost/book/book-a/OEBPS/Text/chapter.xhtml'),
        method: 'POST',
      );

      expect(response.statusCode, 403);
    });

    test('rejects a decoded path traversal segment', () async {
      final response = await handler.loadRequestUrl(
        'epub://localhost/book/book-a/OEBPS/%2E%2E/secret.txt',
      );

      expect(response.statusCode, 403);
    });

    test('returns a not-found response for a missing resource', () async {
      final response = await handler.load(
        Uri.parse('epub://localhost/book/book-a/OEBPS/Text/missing.xhtml'),
      );

      expect(response.statusCode, 404);
    });
  });

  test('maps EPUB resource extensions to WebView MIME types', () {
    expect(androidEpubMimeTypeFor('chapter.xhtml'), 'application/xhtml+xml');
    expect(androidEpubMimeTypeFor('styles/book.css'), 'text/css; charset=utf-8');
    expect(androidEpubMimeTypeFor('fonts/book.woff2'), 'font/woff2');
    expect(androidEpubMimeTypeFor('unknown.bin'), 'application/octet-stream');
  });
}
