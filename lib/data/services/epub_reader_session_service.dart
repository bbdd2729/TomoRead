import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import 'epub_extraction_service.dart';

class EpubReaderSession {
  const EpubReaderSession({
    required this.directoryPath,
    required this.runtimeDirectoryPath,
    required this.entryPointPath,
    required this.manifestPath,
  });

  final String directoryPath;
  final String runtimeDirectoryPath;
  final String entryPointPath;
  final String manifestPath;

  String virtualEntryPointUrl(String hostName) => Uri(
    scheme: 'https',
    host: hostName,
    pathSegments: const ['.tomoread-reader', 'index.html'],
  ).toString();
}

class EpubReaderSessionService {
  EpubReaderSessionService({
    EpubExtractionService? extractionService,
    Future<String> Function(String assetKey)? runtimeAssetLoader,
  }) : _extractionService = extractionService ?? const EpubExtractionService(),
       _runtimeAssetLoader = runtimeAssetLoader ?? rootBundle.loadString;

  static const _runtimeDirectoryName = '.tomoread-reader';
  static const runtimeVersion = '29';

  static const _runtimeAssets = {
    'index.html': 'assets/epub_reader_runtime/index.html',
    'tomoread-reader.js': 'assets/epub_reader_runtime/tomoread-reader.js',
    'foliate-paginator.js': 'assets/epub_reader_runtime/foliate-paginator.js',
    'epubcfi.js': 'assets/epub_reader_runtime/epubcfi.js',
    'licenses/foliate-js.MIT.txt':
        'assets/epub_reader_runtime/licenses/foliate-js.MIT.txt',
  };

  final EpubExtractionService _extractionService;
  final Future<String> Function(String assetKey) _runtimeAssetLoader;

  Future<EpubReaderSession> prepare({
    required LibraryBook book,
    required EpubManifest manifest,
  }) async {
    final directoryPath = await _extractionService.ensureExtracted(book);
    final runtimeDirectory = Directory(
      path.join(directoryPath, _runtimeDirectoryName),
    );
    await runtimeDirectory.create(recursive: true);

    await _ensureRuntime(runtimeDirectory);
    final manifestFile = File(
      path.join(runtimeDirectory.path, 'manifest.json'),
    );
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'runtimeVersion': runtimeVersion,
        'bookId': book.id,
        'resourceBase': '../',
        'manifest': manifest.toJson(),
      }),
    );

    return EpubReaderSession(
      directoryPath: directoryPath,
      runtimeDirectoryPath: runtimeDirectory.path,
      entryPointPath: path.join(runtimeDirectory.path, 'index.html'),
      manifestPath: manifestFile.path,
    );
  }

  Future<void> _ensureRuntime(Directory runtimeDirectory) async {
    final versionFile = File(
      path.join(runtimeDirectory.path, '.runtime-version'),
    );
    if (await versionFile.exists() &&
        await versionFile.readAsString() == runtimeVersion) {
      return;
    }

    for (final entry in _runtimeAssets.entries) {
      final destination = File(path.join(runtimeDirectory.path, entry.key));
      await destination.parent.create(recursive: true);
      await destination.writeAsString(await _runtimeAssetLoader(entry.value));
    }
    await versionFile.writeAsString(runtimeVersion);
  }
}
