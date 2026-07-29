import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/providers.dart';
import '../../domain/models/bookmark.dart';
import 'pdf_bookmarks_dialog.dart';
import 'pdf_navigation_dialog.dart';
import 'pdf_search_dialog.dart';

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
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    final currentPage = useState(1);
    final viewerController = useMemoized(PdfViewerController.new);
    final textSearcher = useState<PdfTextSearcher?>(null);
    final pdfDocument = useState<PdfDocument?>(null);
    final outline = useState(const <PdfOutlineNode>[]);
    final outlineLoading = useState(false);
    final outlineError = useState<Object?>(null);

    useEffect(() {
      return () => textSearcher.value?.dispose();
    }, [viewerController]);

    Future<void> loadOutline(PdfDocument document) async {
      outlineLoading.value = true;
      outlineError.value = null;
      try {
        final loadedOutline = await document.loadOutline();
        if (!context.mounted) return;
        outline.value = loadedOutline;
      } catch (error) {
        if (!context.mounted) return;
        outlineError.value = error;
      } finally {
        if (context.mounted) outlineLoading.value = false;
      }
    }

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
        final bookmarkItems = bookmarks.value ?? const <Bookmark>[];
        final currentLocator = 'page:$displayedPage';
        final isBookmarked = bookmarkItems.any(
          (bookmark) => bookmark.locator == currentLocator,
        );

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

        Future<void> toggleBookmark() async {
          final repository = ref.read(bookmarkRepositoryProvider);
          final existing = bookmarkItems
              .where((bookmark) => bookmark.locator == currentLocator)
              .firstOrNull;
          if (existing != null) {
            await repository.remove(existing.id);
          } else {
            await repository.add(
              bookId: bookId,
              locator: currentLocator,
              chapterTitle: '第 $displayedPage 页',
            );
          }
          ref.invalidate(bookmarksForBookProvider(bookId));
        }

        Future<void> openBookmarks() async {
          final bookmark = await showDialog<Bookmark>(
            context: context,
            builder: (context) => PdfBookmarksDialog(bookmarks: bookmarkItems),
          );
          final page = bookmark == null
              ? null
              : int.tryParse(bookmark.locator.replaceFirst('page:', ''));
          if (page != null && viewerController.isReady) {
            await viewerController.goToPage(pageNumber: page);
          }
        }

        Future<void> openSearch() async {
          final searcher = textSearcher.value;
          if (searcher == null) return;
          await showDialog<void>(
            context: context,
            builder: (context) => PdfSearchDialog(searcher: searcher),
          );
        }

        Future<void> openNavigation() async {
          final document = pdfDocument.value;
          if (document == null) return;
          final destination = await showDialog<PdfDest>(
            context: context,
            builder: (context) => PdfNavigationDialog(
              document: document,
              outline: outline.value,
              isOutlineLoading: outlineLoading.value,
              outlineError: outlineError.value,
              currentPage: displayedPage,
            ),
          );
          if (destination != null && viewerController.isReady) {
            await viewerController.goToDest(destination);
          }
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
                    IconButton(
                      tooltip: isBookmarked ? '移除书签' : '添加书签',
                      onPressed: toggleBookmark,
                      icon: Icon(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      ),
                    ),
                    IconButton(
                      tooltip: '查看书签',
                      onPressed: bookmarks.isLoading ? null : openBookmarks,
                      icon: const Icon(Icons.format_list_bulleted),
                    ),
                    IconButton(
                      tooltip: '目录和页面导航',
                      onPressed: pdfDocument.value == null
                          ? null
                          : openNavigation,
                      icon: const Icon(Icons.menu_book_outlined),
                    ),
                    IconButton(
                      tooltip: '搜索 PDF',
                      onPressed: textSearcher.value == null ? null : openSearch,
                      icon: const Icon(Icons.search),
                    ),
                    Text('$pageCount 页'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PdfViewer.file(
                book.filePath,
                controller: viewerController,
                initialPageNumber: initialPage,
                params: PdfViewerParams(
                  onPageChanged: savePage,
                  onViewerReady: (_, controller) {
                    if (textSearcher.value == null) {
                      textSearcher.value = PdfTextSearcher(controller);
                    }
                    if (pdfDocument.value == null) {
                      pdfDocument.value = controller.document;
                      loadOutline(controller.document);
                    }
                  },
                  pagePaintCallbacks: textSearcher.value == null
                      ? null
                      : [textSearcher.value!.pageTextMatchPaintCallback],
                ),
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
