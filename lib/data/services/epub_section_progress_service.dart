import 'dart:io';

import 'package:path/path.dart' as path;

import '../../domain/models/epub_manifest.dart';
import '../../domain/models/epub_section_progress.dart';

class EpubSectionProgressService {
  const EpubSectionProgressService();

  /// Builds the same content-weighted book locator used by Foliate/ReadAny.
  /// Only spine resource metadata is read; chapters remain lazily rendered.
  Future<EpubSectionProgress> load({
    required String extractedDirectory,
    required EpubManifest manifest,
  }) async {
    final sizes = <int>[];
    for (final item in manifest.spine) {
      if (!item.linear) {
        sizes.add(0);
        continue;
      }
      final file = _spineFile(extractedDirectory, item.href);
      sizes.add(file == null || !await file.exists() ? 0 : await file.length());
    }
    return EpubSectionProgress.fromSizes(sizes);
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
