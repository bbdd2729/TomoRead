import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../domain/models/epub_manifest.dart';
import '../../domain/models/epub_section_progress.dart';
import 'epub_content_service.dart';

class EpubSectionProgressService {
  const EpubSectionProgressService({this.content = const EpubContentService()});

  final EpubContentService content;

  /// Builds a whole-book locator from the same normalized text representation
  /// used by search and content indexing. Using source byte sizes here would
  /// make a chapter's HTML/CSS markup distort the displayed character position.
  Future<EpubSectionProgress> load({
    required String extractedDirectory,
    required EpubManifest manifest,
  }) async {
    final characterCounts = <int>[];
    for (final item in manifest.spine) {
      if (!item.linear) {
        characterCounts.add(0);
        continue;
      }
      final file = _spineFile(extractedDirectory, item.href);
      if (file == null || !await file.exists()) {
        characterCounts.add(0);
        continue;
      }
      final bytes = await file.readAsBytes();
      characterCounts.add(
        content.characterCountFromXhtml(
          utf8.decode(bytes, allowMalformed: true),
        ),
      );
    }
    return EpubSectionProgress.fromCharacterCounts(characterCounts);
  }

  File? _spineFile(String extractedDirectory, String href) {
    final decodedHref = Uri.decodeFull(href.split('#').first);
    final candidate = path.normalize(
      path.join(extractedDirectory, path.joinAll(decodedHref.split('/'))),
    );
    if (!path.isWithin(extractedDirectory, candidate)) return null;
    return File(candidate);
  }
}
