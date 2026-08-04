import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
      await File('${bookDirectory.path}/OEBPS/Text/notes.md').writeAsString(
        '# notes',
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

    test('rejects a double-encoded path traversal', () async {
      final response = await handler.loadRequestUrl(
        'epub://localhost/book/book-a/OEBPS/%252E%252E/secret.txt',
      );

      expect(response.statusCode, 403);
    });

    test('rejects backslash path traversal', () async {
      final response = await handler.loadRequestUrl(
        'epub://localhost/book/book-a/OEBPS/..\\secret.txt',
      );

      expect(response.statusCode, 403);
    });

    test('rejects an invalid raw URL', () async {
      final response = await handler.loadRequestUrl('not a uri ://');

      expect(response.statusCode, 403);
    });

    test('rejects a NUL byte inside a path segment', () async {
      final response = await handler.loadRequestUrl(
        'epub://localhost/book/book-a/OEBPS/Text/\u0000chapter.xhtml',
      );

      expect(response.statusCode, 403);
    });

    test('rejects a request with user info or a port', () async {
      final response = await handler.load(
        Uri.parse('epub://user@localhost:8080/book/book-a/chapter.xhtml'),
      );

      expect(response.statusCode, 403);
    });

    test('rejects a path outside the runtime and book namespaces', () async {
      final response = await handler.load(
        Uri.parse('epub://localhost/other/chapter.xhtml'),
      );

      expect(response.statusCode, 403);
    });

    test('rejects an empty relative path after the namespace', () async {
      final response = await handler.load(
        Uri.parse('epub://localhost/book/book-a/'),
      );

      expect(response.statusCode, 403);
    });

    test('returns 404 for a directory rather than reading it as a file', () async {
      final response = await handler.load(
        Uri.parse('epub://localhost/book/book-a/OEBPS/'),
      );

      expect(response.statusCode, 404);
    });
  });

  group('AndroidEpubResourceHandler.book-scoped URLs', () {
    test('runtime entry point uses the virtual scheme and host', () {
      final handler = AndroidEpubResourceHandler(
        bookId: 'book-a',
        bookDirectoryPath: '/tmp/book-a',
      );
      expect(handler.runtimeEntryPoint.scheme, 'epub');
      expect(handler.runtimeEntryPoint.host, 'localhost');
      expect(handler.runtimeEntryPoint.path, '/runtime/index.html');
    });

    test('resourceBaseForBook encodes the book id', () {
      expect(
        AndroidEpubResourceHandler.resourceBaseForBook('book a'),
        '../book/book%20a/',
      );
    });
  });

  group('AndroidEpubResourceResponse', () {
    test('isSuccess reflects the status code', () {
      expect(
        AndroidEpubResourceResponse(
          statusCode: 200,
          contentType: 'text/plain',
          data: Uint8List.fromList(utf8.encode('ok')),
        ).isSuccess,
        isTrue,
      );
      expect(
        AndroidEpubResourceResponse.error(statusCode: 404, message: 'missing')
            .isSuccess,
        isFalse,
      );
    });

    test('error factory writes the message as UTF-8 text', () {
      final response = AndroidEpubResourceResponse.error(
        statusCode: 403,
        message: '拒绝',
      );
      expect(response.contentType, 'text/plain; charset=utf-8');
      expect(String.fromCharCodes(response.data), '拒绝');
    });
  });

  test('maps EPUB resource extensions to WebView MIME types', () {
    expect(androidEpubMimeTypeFor('chapter.xhtml'), 'application/xhtml+xml');
    expect(androidEpubMimeTypeFor('styles/book.css'), 'text/css; charset=utf-8');
    expect(androidEpubMimeTypeFor('fonts/book.woff2'), 'font/woff2');
    expect(androidEpubMimeTypeFor('unknown.bin'), 'application/octet-stream');
    expect(androidEpubMimeTypeFor('a.xht'), 'application/xhtml+xml');
    expect(androidEpubMimeTypeFor('a.htm'), 'application/xhtml+xml');
    expect(androidEpubMimeTypeFor('a.js'), 'text/javascript; charset=utf-8');
    expect(androidEpubMimeTypeFor('a.mjs'), 'text/javascript; charset=utf-8');
    expect(androidEpubMimeTypeFor('a.json'), 'application/json; charset=utf-8');
    expect(androidEpubMimeTypeFor('a.xml'), 'application/xml; charset=utf-8');
    expect(androidEpubMimeTypeFor('a.opf'), 'application/xml; charset=utf-8');
    expect(androidEpubMimeTypeFor('a.ncx'), 'application/xml; charset=utf-8');
    expect(androidEpubMimeTypeFor('a.svg'), 'image/svg+xml');
    expect(androidEpubMimeTypeFor('a.png'), 'image/png');
    expect(androidEpubMimeTypeFor('a.jpg'), 'image/jpeg');
    expect(androidEpubMimeTypeFor('a.jpeg'), 'image/jpeg');
    expect(androidEpubMimeTypeFor('a.gif'), 'image/gif');
    expect(androidEpubMimeTypeFor('a.webp'), 'image/webp');
    expect(androidEpubMimeTypeFor('a.avif'), 'image/avif');
    expect(androidEpubMimeTypeFor('a.woff'), 'font/woff');
    expect(androidEpubMimeTypeFor('a.ttf'), 'font/ttf');
    expect(androidEpubMimeTypeFor('a.otf'), 'font/otf');
    expect(androidEpubMimeTypeFor('a.mp3'), 'audio/mpeg');
    expect(androidEpubMimeTypeFor('a.ogg'), 'audio/ogg');
    expect(androidEpubMimeTypeFor('a.oga'), 'audio/ogg');
    expect(androidEpubMimeTypeFor('a.wav'), 'audio/wav');
    expect(androidEpubMimeTypeFor('a.mp4'), 'video/mp4');
    expect(androidEpubMimeTypeFor('a.m4v'), 'video/mp4');
    expect(androidEpubMimeTypeFor('a.webm'), 'video/webm');
    expect(androidEpubMimeTypeFor('a.smil'), 'application/smil+xml');
  });
}

