import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/content_chunk_service.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/text_chapter.dart';

final contentIndexControllerProvider = Provider<ContentIndexController>(
  (ref) => ContentIndexController(
    service: ref.watch(contentChunkServiceProvider),
    onChanged: () => ref.read(contentIndexRevisionProvider.notifier).bump(),
  ),
);

class ContentIndexController {
  ContentIndexController({required this.service, required this.onChanged});

  final ContentChunkService service;
  final void Function() onChanged;
  final Set<String> _running = {};

  Future<void> rebuildText({
    required String bookId,
    required String rawText,
    required String contentHash,
    required List<TextChapter> chapters,
  }) async {
    if (!_running.add(bookId)) return;
    try {
      await service.rebuildText(
        bookId: bookId,
        rawText: rawText,
        contentHash: contentHash,
        chapters: chapters,
      );
    } finally {
      _running.remove(bookId);
      onChanged();
    }
  }

  Future<void> rebuildEpub({
    required LibraryBook book,
    required EpubManifest manifest,
  }) async {
    if (!_running.add(book.id)) return;
    try {
      await service.rebuildEpub(book: book, manifest: manifest);
    } finally {
      _running.remove(book.id);
      onChanged();
    }
  }
}
