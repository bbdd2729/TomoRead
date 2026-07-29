import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/book_import_service.dart';
import '../../domain/models/library_book.dart';
import '../../shared/widgets/page_header.dart';

class LibraryHomePage extends HookConsumerWidget {
  const LibraryHomePage({super.key, required this.onOpenReader});

  final ValueChanged<LibraryBook> onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryBooksProvider);
    final isImporting = useState(false);
    final searchQuery = useState('');
    final formatFilter = useState(_LibraryFormatFilter.all);
    final sort = useState(_LibrarySort.recent);
    final removingBookId = useState<String?>(null);

    Future<void> importBooks() async {
      if (isImporting.value) return;
      isImporting.value = true;
      final results = await ref
          .read(libraryBooksProvider.notifier)
          .importFromPicker();
      isImporting.value = false;
      if (!context.mounted || results.isEmpty) return;
      final imported = results
          .where((result) => result.status == BookImportStatus.imported)
          .length;
      final duplicates = results
          .where((result) => result.status == BookImportStatus.duplicate)
          .length;
      final failed = results
          .where((result) => result.status == BookImportStatus.failed)
          .length;
      final message = [
        if (imported > 0) '已导入 $imported 本',
        if (duplicates > 0) '$duplicates 本已存在',
        if (failed > 0) '$failed 本导入失败',
      ].join('，');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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

    return books.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _LibraryFailure(
        message: '无法读取书库：$error',
        onRetry: () => ref.invalidate(libraryBooksProvider),
      ),
      data: (items) {
        final visibleBooks = _filterAndSortBooks(
          items,
          query: searchQuery.value,
          formatFilter: formatFilter.value,
          sort: sort.value,
        );
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            PageHeader(
              title: '书库',
              subtitle: '管理并继续阅读你的 EPUB 与 PDF 书籍。',
              actionLabel: isImporting.value ? '正在导入' : '导入书籍',
              actionIcon: Icons.add,
              onAction: isImporting.value ? null : importBooks,
            ),
            const SizedBox(height: 24),
            if (items.isEmpty)
              _EmptyLibrary(onImport: isImporting.value ? null : importBooks)
            else ...[
              _LibraryControls(
                formatFilter: formatFilter.value,
                sort: sort.value,
                onQueryChanged: (value) => searchQuery.value = value,
                onFormatChanged: (value) => formatFilter.value = value,
                onSortChanged: (value) => sort.value = value,
              ),
              const SizedBox(height: 24),
              if (visibleBooks.isEmpty)
                const _NoMatchingBooks()
              else ...[
                _ContinueReadingCard(
                  book: visibleBooks.first,
                  onOpenReader: () => onOpenReader(visibleBooks.first),
                ),
                const SizedBox(height: 28),
                Text('全部书籍', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisExtent: 270,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: visibleBooks.length,
                  itemBuilder: (context, index) => _BookCard(
                    book: visibleBooks[index],
                    onTap: () => onOpenReader(visibleBooks[index]),
                    isRemoving: removingBookId.value == visibleBooks[index].id,
                    onDelete: () => removeBook(visibleBooks[index]),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

enum _LibraryFormatFilter { all, epub, pdf }

extension on _LibraryFormatFilter {
  String get label => switch (this) {
    _LibraryFormatFilter.all => '全部',
    _LibraryFormatFilter.epub => 'EPUB',
    _LibraryFormatFilter.pdf => 'PDF',
  };
}

enum _LibrarySort { recent, title, progress }

extension on _LibrarySort {
  String get label => switch (this) {
    _LibrarySort.recent => '最近导入',
    _LibrarySort.title => '书名',
    _LibrarySort.progress => '阅读进度',
  };
}

List<LibraryBook> _filterAndSortBooks(
  List<LibraryBook> books, {
  required String query,
  required _LibraryFormatFilter formatFilter,
  required _LibrarySort sort,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = books.where((book) {
    final matchesFormat = switch (formatFilter) {
      _LibraryFormatFilter.all => true,
      _LibraryFormatFilter.epub => book.format == 'epub',
      _LibraryFormatFilter.pdf => book.format == 'pdf',
    };
    final searchableText = '${book.title} ${book.author}'.toLowerCase();
    return matchesFormat &&
        (normalizedQuery.isEmpty || searchableText.contains(normalizedQuery));
  }).toList();
  filtered.sort(switch (sort) {
    _LibrarySort.recent => (first, second) => second.importedAt.compareTo(
      first.importedAt,
    ),
    _LibrarySort.title =>
      (first, second) =>
          first.title.toLowerCase().compareTo(second.title.toLowerCase()),
    _LibrarySort.progress => (first, second) => second.progress.compareTo(
      first.progress,
    ),
  });
  return filtered;
}

class _LibraryControls extends StatelessWidget {
  const _LibraryControls({
    required this.formatFilter,
    required this.sort,
    required this.onQueryChanged,
    required this.onFormatChanged,
    required this.onSortChanged,
  });

  final _LibraryFormatFilter formatFilter;
  final _LibrarySort sort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_LibraryFormatFilter> onFormatChanged;
  final ValueChanged<_LibrarySort> onSortChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 320,
        child: TextField(
          key: const Key('library-search'),
          onChanged: onQueryChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索书名或作者',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      SegmentedButton<_LibraryFormatFilter>(
        segments: [
          for (final filter in _LibraryFormatFilter.values)
            ButtonSegment(value: filter, label: Text(filter.label)),
        ],
        selected: {formatFilter},
        onSelectionChanged: (selection) => onFormatChanged(selection.first),
      ),
      SizedBox(
        width: 152,
        child: DropdownButtonFormField<_LibrarySort>(
          initialValue: sort,
          decoration: const InputDecoration(
            labelText: '排序',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final option in _LibrarySort.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value != null) onSortChanged(value);
          },
        ),
      ),
    ],
  );
}

class _NoMatchingBooks extends StatelessWidget {
  const _NoMatchingBooks();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.manage_search_outlined, size: 44),
          const SizedBox(height: 12),
          Text('没有匹配的书籍', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 96),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_stories_outlined, size: 52),
          const SizedBox(height: 16),
          Text('还没有书籍', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('导入 EPUB 或 PDF 后会在这里显示。'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('导入书籍'),
          ),
        ],
      ),
    ),
  );
}

class _LibraryFailure extends StatelessWidget {
  const _LibraryFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: Text(message),
    ),
  );
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.book, required this.onOpenReader});

  final LibraryBook book;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(width: 96, height: 132, child: _BookCover(book: book)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('继续阅读', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  book.author.isEmpty ? '未知作者' : book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  book.format.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: book.progress),
                const SizedBox(height: 8),
                Text(
                  '已读 ${(book.progress * 100).round()}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton.filledTonal(
            tooltip: '继续阅读',
            onPressed: onOpenReader,
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
    ),
  );
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.isRemoving,
    required this.onDelete,
  });

  final LibraryBook book;
  final VoidCallback onTap;
  final bool isRemoving;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('book-${book.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: isRemoving ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _BookCover(book: book),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: '删除书籍',
                        onPressed: isRemoving ? null : onDelete,
                        icon: isRemoving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              book.author.isEmpty ? '未知作者' : book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: book.progress),
          ],
        ),
      ),
    ),
  );
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(
        File(coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
    ),
    child: Center(
      child: Icon(
        book.format == 'pdf'
            ? Icons.picture_as_pdf_outlined
            : Icons.menu_book_outlined,
        size: 44,
      ),
    ),
  );
}
