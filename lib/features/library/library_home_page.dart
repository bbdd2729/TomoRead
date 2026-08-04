import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/book_import_service.dart';
import '../../domain/models/book_import.dart';
import '../../domain/models/library_book.dart';
import '../../shared/widgets/page_header.dart';
import 'book_import_preview_dialog.dart';
import 'import_result_handler.dart';
import 'import_workflow_controller.dart';
import 'library_cards.dart';
import 'library_controls.dart';
import 'library_empty_states.dart';
import 'library_import_source_dialog.dart';
import 'library_selection.dart';

class LibraryHomePage extends HookConsumerWidget {
  const LibraryHomePage({
    super.key,
    required this.onOpenBookDetails,
    required this.onOpenReader,
  });

  final ValueChanged<LibraryBook> onOpenBookDetails;
  final ValueChanged<LibraryBook> onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryBooksProvider);
    final isImporting = useState(false);
    final importService = ref.read(bookImportServiceProvider);
    final importController = useMemoized(
      () => ImportWorkflowController.forService(importService),
      [importService],
    );
    useEffect(() => importController.dispose, [importController]);
    final searchQuery = useState('');
    final formatFilter = useState(LibraryFormatFilter.all);
    final sort = useState(LibrarySort.recent);
    final viewMode = useState(LibraryViewMode.grid);
    final categoryFilter = useState(allCategoriesFilter);
    final tagFilter = useState<String?>(null);
    final favoritesOnly = useState(false);
    final selectionMode = useState(false);
    final selectedBookIds = useState(<String>{});
    final removingBookId = useState<String?>(null);
    final isBatchOperating = useState(false);

    Future<void> finishImport(List<BookImportResult> initialResults) async {
      final results = await resolveImportResults(context, ref, initialResults);
      if (!context.mounted || results.isEmpty) return;
      if (results.any((result) => result.status == BookImportStatus.imported)) {
        ref.invalidate(libraryBooksProvider);
      }
      showImportSummary(context, results);
    }

    Future<void> importSources(List<ImportSource> sources) async {
      if (isImporting.value || sources.isEmpty) return;
      isImporting.value = true;
      try {
        importController.reset();
        final dialog = showDialog<List<BookImportResult>>(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              BookImportPreviewDialog(controller: importController),
        );
        unawaited(importController.prepare(sources));
        final results = await dialog;
        if (context.mounted && results != null) {
          await finishImport(results);
        }
      } finally {
        if (context.mounted) isImporting.value = false;
      }
    }

    Future<void> importBooks() async {
      if (isImporting.value) return;
      final choice = await showDialog<ImportSourceChoice>(
        context: context,
        builder: (context) => const ImportSourceDialog(),
      );
      if (choice == null || !context.mounted) return;
      switch (choice) {
        case ImportSourceChoice.files:
          await importSources(await importService.pickImportSources());
          return;
        case ImportSourceChoice.directory:
          final source = await importService.pickImportDirectorySource();
          if (source != null) await importSources([source]);
          return;
      }
    }

    Future<void> removeBook(LibraryBook book) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除书籍'),
          content: Text('“${book.title}”将从 TomoRead 书库和本地托管文件中移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      removingBookId.value = book.id;
      try {
        final result = await ref
            .read(bookStorageServiceProvider)
            .removeBook(book);
        ref.invalidate(libraryBooksProvider);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.hasCleanupErrors
                  ? '书籍已移除，但部分本地缓存未能清理。'
                  : '已删除《${book.title}》。',
            ),
          ),
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      } finally {
        if (context.mounted) removingBookId.value = null;
      }
    }

    Future<void> toggleFavorite(LibraryBook book) async {
      await ref
          .read(bookRepositoryProvider)
          .setFavorite(book.id, !book.isFavorite);
      ref.invalidate(libraryBooksProvider);
    }

    void toggleSelection(String bookId) {
      final next = {...selectedBookIds.value};
      if (!next.add(bookId)) next.remove(bookId);
      selectedBookIds.value = next;
    }

    void cancelSelection() {
      selectionMode.value = false;
      selectedBookIds.value = <String>{};
    }

    Future<void> updateSelectedFavorite(List<LibraryBook> items) async {
      final selected = selectedBookIds.value;
      if (selected.isEmpty || isBatchOperating.value) return;
      final selectedBooks = items.where((book) => selected.contains(book.id));
      final targetValue = selectedBooks.any((book) => !book.isFavorite);
      isBatchOperating.value = true;
      try {
        await ref
            .read(bookRepositoryProvider)
            .setFavoriteForBooks(selected, targetValue);
        ref.invalidate(libraryBooksProvider);
      } finally {
        if (context.mounted) isBatchOperating.value = false;
      }
    }

    Future<void> updateSelectedCategory(List<LibraryBook> items) async {
      final selected = selectedBookIds.value;
      if (selected.isEmpty || isBatchOperating.value) return;
      final update = await showDialog<CategoryUpdate>(
        context: context,
        builder: (context) => CategoryDialog(categories: categoriesFor(items)),
      );
      if (!context.mounted || update == null) return;
      isBatchOperating.value = true;
      try {
        await ref
            .read(bookRepositoryProvider)
            .setCategoryForBooks(selected, update.category);
        ref.invalidate(libraryBooksProvider);
      } finally {
        if (context.mounted) isBatchOperating.value = false;
      }
    }

    Future<void> removeSelectedBooks(List<LibraryBook> items) async {
      final selected = selectedBookIds.value;
      if (selected.isEmpty || isBatchOperating.value) return;
      final selectedBooks = items
          .where((book) => selected.contains(book.id))
          .toList();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除书籍'),
          content: Text('将删除选中的 ${selectedBooks.length} 本书及其本地文件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      isBatchOperating.value = true;
      try {
        for (final book in selectedBooks) {
          await ref.read(bookStorageServiceProvider).removeBook(book);
        }
        ref.invalidate(libraryBooksProvider);
        cancelSelection();
      } finally {
        if (context.mounted) isBatchOperating.value = false;
      }
    }

    return books.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => LibraryFailure(
        message: '无法读取书库：$error',
        onRetry: () => ref.invalidate(libraryBooksProvider),
      ),
      data: (items) {
        final visibleBooks = filterAndSortBooks(
          items,
          query: searchQuery.value,
          formatFilter: formatFilter.value,
          sort: sort.value,
          category: categoryFilter.value,
          tag: tagFilter.value,
          favoritesOnly: favoritesOnly.value,
        );
        final continueReadingBook = continueReadingBook(visibleBooks);
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final horizontalPadding = compact ? 16.0 : 32.0;
            Widget buildBookCard(int index) => BookCard(
              book: visibleBooks[index],
              onTap: () => selectionMode.value
                  ? toggleSelection(visibleBooks[index].id)
                  : onOpenBookDetails(visibleBooks[index]),
              onLongPress: () {
                selectionMode.value = true;
                toggleSelection(visibleBooks[index].id);
              },
              isSelected: selectedBookIds.value.contains(
                visibleBooks[index].id,
              ),
              selectionMode: selectionMode.value,
              isRemoving: removingBookId.value == visibleBooks[index].id,
              onDelete: () => removeBook(visibleBooks[index]),
              onToggleFavorite: () => toggleFavorite(visibleBooks[index]),
            );

            Widget buildBookListItem(int index) => BookListItem(
              book: visibleBooks[index],
              onTap: () => selectionMode.value
                  ? toggleSelection(visibleBooks[index].id)
                  : onOpenBookDetails(visibleBooks[index]),
              onLongPress: () {
                selectionMode.value = true;
                toggleSelection(visibleBooks[index].id);
              },
              isSelected: selectedBookIds.value.contains(
                visibleBooks[index].id,
              ),
              selectionMode: selectionMode.value,
              isRemoving: removingBookId.value == visibleBooks[index].id,
              onDelete: () => removeBook(visibleBooks[index]),
              onToggleFavorite: () => toggleFavorite(visibleBooks[index]),
            );

            final headerChildren = <Widget>[
              PageHeader(
                title: '书库',
                subtitle: '管理并继续阅读你的 EPUB 与 PDF 书籍。',
                actionLabel: isImporting.value ? '正在导入' : '导入书籍',
                actionIcon: Icons.add,
                onAction: isImporting.value ? null : importBooks,
              ),
              const SizedBox(height: 20),
              if (items.isEmpty)
                EmptyLibrary(onImport: isImporting.value ? null : importBooks)
              else ...[
                LibraryControls(
                  formatFilter: formatFilter.value,
                  sort: sort.value,
                  viewMode: viewMode.value,
                  onQueryChanged: (value) => searchQuery.value = value,
                  onFormatChanged: (value) => formatFilter.value = value,
                  onSortChanged: (value) => sort.value = value,
                  onViewModeChanged: (value) => viewMode.value = value,
                  categories: categoriesFor(items),
                  tags: tagsFor(items),
                  category: categoryFilter.value,
                  tag: tagFilter.value,
                  favoritesOnly: favoritesOnly.value,
                  onCategoryChanged: (value) => categoryFilter.value = value,
                  onTagChanged: (value) => tagFilter.value = value,
                  onFavoritesChanged: (value) => favoritesOnly.value = value,
                ),
                const SizedBox(height: 20),
                if (selectionMode.value)
                  LibrarySelectionToolbar(
                    selectedCount: selectedBookIds.value.length,
                    isWorking: isBatchOperating.value,
                    allSelectedAreFavorite: items
                        .where(
                          (book) => selectedBookIds.value.contains(book.id),
                        )
                        .every((book) => book.isFavorite),
                    onCancel: cancelSelection,
                    onToggleFavorite: () => updateSelectedFavorite(items),
                    onChangeCategory: () => updateSelectedCategory(items),
                    onDelete: () => removeSelectedBooks(items),
                  ),
                if (selectionMode.value) const SizedBox(height: 16),
                if (visibleBooks.isEmpty)
                  const NoMatchingBooks()
                else ...[
                  ContinueReadingCard(
                    book: continueReadingBook!,
                    onOpenReader: () => onOpenReader(continueReadingBook),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(
                        '全部书籍',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${visibleBooks.length} 本',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ];

            final headerSliver = SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 20 : 28,
                horizontalPadding,
                visibleBooks.isEmpty ? 40 : 0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(headerChildren),
              ),
            );

            if (visibleBooks.isEmpty) {
              return CustomScrollView(slivers: [headerSliver]);
            }

            final booksSliver = viewMode.value == LibraryViewMode.grid
                ? SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => buildBookCard(index),
                      childCount: visibleBooks.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 176,
                          mainAxisExtent: 286,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 20,
                        ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => index.isOdd
                          ? const SizedBox(height: 8)
                          : buildBookListItem(index ~/ 2),
                      childCount: visibleBooks.length * 2 - 1,
                    ),
                  );

            return CustomScrollView(
              slivers: [
                headerSliver,
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    40,
                  ),
                  sliver: booksSliver,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
