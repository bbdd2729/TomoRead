import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../../app/app_diagnostics.dart';

/// Serves one extracted EPUB through the Android reader's virtual origin.
///
/// The renderer must never receive a physical file path. Keeping runtime and
/// book resources under [virtualScheme] also gives its iframe documents a
/// stable same-origin base on Android WebView.
class AndroidEpubResourceHandler {
  AndroidEpubResourceHandler({
    required this.bookId,
    required this.bookDirectoryPath,
  });

  static const virtualScheme = 'epub';
  static const virtualHost = 'localhost';
  static const _runtimeDirectoryName = '.tomoread-reader';

  final String bookId;
  final String bookDirectoryPath;

  Uri get runtimeEntryPoint => Uri(
    scheme: virtualScheme,
    host: virtualHost,
    pathSegments: const ['runtime', 'index.html'],
  );

  static String resourceBaseForBook(String bookId) =>
      '../book/${Uri.encodeComponent(bookId)}/';

  Future<AndroidEpubResourceResponse> load(
    Uri requestUri, {
    String? method,
  }) async {
    if (method != null && method.toUpperCase() != 'GET') {
      _logRejected(requestUri, 'unsupportedMethod');
      return AndroidEpubResourceResponse.error(
        statusCode: 403,
        message: 'EPUB resource method is not allowed.',
      );
    }
    final resolution = await _resolve(requestUri);
    if (resolution is _RejectedResource) {
      _logRejected(requestUri, resolution.reason);
      return AndroidEpubResourceResponse.error(
        statusCode: resolution.statusCode,
        message: resolution.message,
      );
    }

    final resource = resolution as _ResolvedResource;
    try {
      if (!await resource.file.exists() ||
          await FileSystemEntity.type(resource.file.path) !=
              FileSystemEntityType.file) {
        _logMissing(requestUri, resource.relativePath);
        return AndroidEpubResourceResponse.error(
          statusCode: 404,
          message: 'EPUB resource not found.',
        );
      }
      final data = await resource.file.readAsBytes();
      return AndroidEpubResourceResponse(
        statusCode: 200,
        contentType: androidEpubMimeTypeFor(resource.relativePath),
        data: data,
      );
    } on FileSystemException catch (error, stackTrace) {
      AppDiagnostics.error(
        'epub.resource',
        'resource read failed',
        details: {
          'bookId': bookId,
          'url': requestUri.toString(),
          'statusCode': 500,
        },
        error: error,
        stackTrace: stackTrace,
      );
      return AndroidEpubResourceResponse.error(
        statusCode: 500,
        message: 'Unable to read EPUB resource.',
      );
    }
  }

  Future<Object> _resolve(Uri requestUri) async {
    if (requestUri.scheme != virtualScheme || requestUri.host != virtualHost) {
      return const _RejectedResource(
        statusCode: 403,
        reason: 'unexpectedOrigin',
        message: 'EPUB resource origin is not allowed.',
      );
    }
    if (requestUri.userInfo.isNotEmpty || requestUri.port != 0) {
      return const _RejectedResource(
        statusCode: 403,
        reason: 'unexpectedAuthority',
        message: 'EPUB resource authority is not allowed.',
      );
    }

    final segments = requestUri.pathSegments;
    if (segments.isEmpty || segments.any(_isUnsafeSegment)) {
      return const _RejectedResource(
        statusCode: 403,
        reason: 'unsafePath',
        message: 'EPUB resource path is not allowed.',
      );
    }

    late final Directory root;
    late final List<String> relativeSegments;
    if (segments.first == 'runtime') {
      root = Directory(path.join(bookDirectoryPath, _runtimeDirectoryName));
      relativeSegments = segments.skip(1).toList();
    } else if (segments.length >= 3 &&
        segments.first == 'book' &&
        segments[1] == bookId) {
      root = Directory(bookDirectoryPath);
      relativeSegments = segments.skip(2).toList();
    } else {
      return const _RejectedResource(
        statusCode: 403,
        reason: 'outsideSession',
        message: 'EPUB resource is outside the active book.',
      );
    }

    if (relativeSegments.isEmpty || relativeSegments.any(_isUnsafeSegment)) {
      return const _RejectedResource(
        statusCode: 403,
        reason: 'unsafePath',
        message: 'EPUB resource path is not allowed.',
      );
    }

    try {
      final rootCanonical = await root.resolveSymbolicLinks();
      final candidate = File(path.join(root.path, ...relativeSegments));
      final candidateCanonical = await candidate.resolveSymbolicLinks();
      if (!path.isWithin(rootCanonical, candidateCanonical)) {
        return const _RejectedResource(
          statusCode: 403,
          reason: 'pathEscape',
          message: 'EPUB resource path is not allowed.',
        );
      }
      return _ResolvedResource(
        file: candidate,
        relativePath: path.joinAll(relativeSegments),
      );
    } on FileSystemException {
      // Do not expose whether the inaccessible path exists. The normal load
      // path reports it as a missing EPUB resource.
      final candidate = File(path.join(root.path, ...relativeSegments));
      return _ResolvedResource(
        file: candidate,
        relativePath: path.joinAll(relativeSegments),
      );
    }
  }

  bool _isUnsafeSegment(String segment) =>
      segment.isEmpty ||
      segment == '.' ||
      segment == '..' ||
      segment.contains('/') ||
      segment.contains('\\') ||
      segment.contains('\u0000');

  void _logRejected(Uri uri, String reason) {
    AppDiagnostics.error(
      'epub.resource',
      'resource request rejected',
      details: {
        'bookId': bookId,
        'url': uri.toString(),
        'reason': reason,
        'statusCode': 403,
      },
    );
  }

  void _logMissing(Uri uri, String relativePath) {
    AppDiagnostics.error(
      'epub.resource',
      'resource not found',
      details: {
        'bookId': bookId,
        'url': uri.toString(),
        'path': relativePath,
        'statusCode': 404,
      },
    );
  }
}

class AndroidEpubResourceResponse {
  const AndroidEpubResourceResponse({
    required this.statusCode,
    required this.contentType,
    required this.data,
  });

  factory AndroidEpubResourceResponse.error({
    required int statusCode,
    required String message,
  }) => AndroidEpubResourceResponse(
    statusCode: statusCode,
    contentType: 'text/plain; charset=utf-8',
    data: Uint8List.fromList(utf8.encode(message)),
  );

  final int statusCode;
  final String contentType;
  final Uint8List data;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

String androidEpubMimeTypeFor(String resourcePath) {
  final extension = path.extension(resourcePath).toLowerCase();
  return switch (extension) {
    '.xhtml' || '.xht' || '.html' || '.htm' => 'application/xhtml+xml',
    '.css' => 'text/css; charset=utf-8',
    '.js' || '.mjs' => 'text/javascript; charset=utf-8',
    '.json' => 'application/json; charset=utf-8',
    '.xml' || '.opf' || '.ncx' => 'application/xml; charset=utf-8',
    '.svg' => 'image/svg+xml',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.avif' => 'image/avif',
    '.woff' => 'font/woff',
    '.woff2' => 'font/woff2',
    '.ttf' => 'font/ttf',
    '.otf' => 'font/otf',
    '.mp3' => 'audio/mpeg',
    '.ogg' || '.oga' => 'audio/ogg',
    '.wav' => 'audio/wav',
    '.mp4' || '.m4v' => 'video/mp4',
    '.webm' => 'video/webm',
    '.smil' => 'application/smil+xml',
    _ => 'application/octet-stream',
  };
}

class _ResolvedResource {
  const _ResolvedResource({required this.file, required this.relativePath});

  final File file;
  final String relativePath;
}

class _RejectedResource {
  const _RejectedResource({
    required this.statusCode,
    required this.reason,
    required this.message,
  });

  final int statusCode;
  final String reason;
  final String message;
}
