import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/providers.dart';

class PdfReaderWorkspace extends HookConsumerWidget {
  const PdfReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
  });

  final String bookId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookState = ref.watch(readerBookProvider(bookId));
    final currentPage = useState(1);

    return bookState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('无法加载 PDF：$error')),
      data: (book) {
        if (book == null) return const Center(child: Text('找不到 PDF 书籍。'));
        final pageCount = book.chapterCount;
        final initialPage = pageCount == 0
            ? 1
            : (book.chapterIndex + 1).clamp(1, pageCount).toInt();
        final displayedPage = currentPage.value == 1 && book.chapterIndex > 0
            ? initialPage
            : currentPage.value;

        Future<void> savePage(int? pageNumber) async {
          if (pageNumber == null || pageNumber < 1) return;
          currentPage.value = pageNumber;
          await ref
              .read(bookRepositoryProvider)
              .updateReadingPosition(
                bookId: bookId,
                chapterIndex: pageNumber - 1,
                progress: pageCount == 0 ? 0 : pageNumber / pageCount,
                locator: 'page:$pageNumber',
              );
          ref.invalidate(libraryBooksProvider);
        }

        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, overflow: TextOverflow.ellipsis),
                    ),
                    Text('$pageCount 页'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PdfViewer.file(
                book.filePath,
                initialPageNumber: initialPage,
                params: PdfViewerParams(onPageChanged: savePage),
              ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('第 $displayedPage / $pageCount 页'),
                    const SizedBox(width: 16),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: pageCount == 0 ? 0 : displayedPage / pageCount,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
