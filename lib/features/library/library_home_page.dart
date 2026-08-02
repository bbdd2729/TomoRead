import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/book_import_service.dart';
import '../../data/services/text_decoder_service.dart';
import '../../domain/models/library_book.dart';
import '../../shared/widgets/book_cover.dart';
import '../../shared/widgets/page_header.dart';

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
    final searchQuery = useState('');
    final formatFilter = useState(_LibraryFormatFilter.all);
    final sort = useState(_LibrarySort.recent);
    final viewMode = useState(_LibraryViewMode.grid);
    final categoryFilter = useState(_allCategories);
    final tagFilter = useState<String?>(null);
    final favoritesOnly = useState(false);
    final selectionMode = useState(false);
    final selectedBookIds = useState(<String>{});
    final removingBookId = useState<String?>(null);
    final isBatchOperating = useState(false);

    Future<void> importBooks() async {
      if (isImporting.value) return;
      isImporting.value = true;
      final initialResults = await ref
          .read(libraryBooksProvider.notifier)
          .importFromPicker();
      final results = <BookImportResult>[];
      for (final result in initialResults) {
        if (result.status != BookImportStatus.needsEncoding ||
            !context.mounted) {
          results.add(result);
          continue;
        }
        final encoding = await showDialog<String>(
          context: context,
          builder: (context) => _TextEncodingDialog(result: result),
        );
        if (encoding == null || !context.mounted) {
          results.add(result);
          continue;
        }
        results.add(
          await ref
              .read(libraryBooksProvider.notifier)
              .importTextWithEncoding(result.sourcePath, encoding),
        );
      }
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
      final pendingEncoding = results
          .where((result) => result.status == BookImportStatus.needsEncoding)
          .length;
      final message = [
        if (imported > 0) '已导入 $imported 本',
        if (duplicates > 0) '$duplicates 本已存在',
        if (failed > 0) '$failed 本导入失败',
        if (pendingEncoding > 0) '$pendingEncoding 本等待确认编码',
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
      final update = await showDialog<_CategoryUpdate>(
        context: context,
        builder: (context) =>
            _CategoryDialog(categories: _categoriesFor(items)),
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
          category: categoryFilter.value,
          tag: tagFilter.value,
          favoritesOnly: favoritesOnly.value,
        );
        final continueReadingBook = _continueReadingBook(visibleBooks);
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final horizontalPadding = compact ? 16.0 : 32.0;
            Widget buildBookCard(int index) => _BookCard(
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

            Widget buildBookListItem(int index) => _BookListItem(
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
                _EmptyLibrary(onImport: isImporting.value ? null : importBooks)
              else ...[
                _LibraryControls(
                  formatFilter: formatFilter.value,
                  sort: sort.value,
                  viewMode: viewMode.value,
                  onQueryChanged: (value) => searchQuery.value = value,
                  onFormatChanged: (value) => formatFilter.value = value,
                  onSortChanged: (value) => sort.value = value,
                  onViewModeChanged: (value) => viewMode.value = value,
                  categories: _categoriesFor(items),
                  tags: _tagsFor(items),
                  category: categoryFilter.value,
                  tag: tagFilter.value,
                  favoritesOnly: favoritesOnly.value,
                  onCategoryChanged: (value) => categoryFilter.value = value,
                  onTagChanged: (value) => tagFilter.value = value,
                  onFavoritesChanged: (value) => favoritesOnly.value = value,
                ),
                const SizedBox(height: 20),
                if (selectionMode.value)
                  _SelectionToolbar(
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
                  const _NoMatchingBooks()
                else ...[
                  _ContinueReadingCard(
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

            final booksSliver = viewMode.value == _LibraryViewMode.grid
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

class _TextEncodingDialog extends ConsumerStatefulWidget {
  const _TextEncodingDialog({required this.result});

  final BookImportResult result;

  @override
  ConsumerState<_TextEncodingDialog> createState() =>
      _TextEncodingDialogState();
}

class _TextEncodingDialogState extends ConsumerState<_TextEncodingDialog> {
  late String encoding =
      widget.result.detectedEncoding ?? supportedTextEncodings.first;
  late String preview = widget.result.textPreview ?? '';
  var loadingPreview = false;
  String? previewError;

  Future<void> selectEncoding(String value) async {
    setState(() {
      encoding = value;
      loadingPreview = true;
      previewError = null;
    });
    try {
      final decoded = await ref
          .read(textDecoderServiceProvider)
          .decodeFile(widget.result.sourcePath, encodingOverride: value);
      if (!mounted) return;
      setState(() => preview = decoded.preview);
    } on Object catch (error) {
      if (mounted) setState(() => previewError = error.toString());
    } finally {
      if (mounted) setState(() => loadingPreview = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认文本编码'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('自动识别结果置信度不足，请预览并选择正确编码。'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: encoding,
            decoration: const InputDecoration(labelText: '编码'),
            items: supportedTextEncodings
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) unawaited(selectEncoding(value));
            },
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: loadingPreview
                  ? const Center(child: CircularProgressIndicator())
                  : previewError != null
                  ? Text('无法使用该编码预览：$previewError')
                  : SelectableText(preview),
            ),
          ),
          const SizedBox(height: 8),
          const Text('选择后会重新解码并重建章节；原始文件不会被改写。'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, encoding),
        child: const Text('使用此编码导入'),
      ),
    ],
  );
}

enum _LibraryFormatFilter { all, epub, pdf, text }

extension on _LibraryFormatFilter {
  String get label => switch (this) {
    _LibraryFormatFilter.all => '全部',
    _LibraryFormatFilter.epub => 'EPUB',
    _LibraryFormatFilter.pdf => 'PDF',
    _LibraryFormatFilter.text => 'TXT/Markdown',
  };
}

enum _LibrarySort { recent, title, progress }

enum _LibraryViewMode { grid, list }

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
  required String category,
  required String? tag,
  required bool favoritesOnly,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = books.where((book) {
    final matchesFormat = switch (formatFilter) {
      _LibraryFormatFilter.all => true,
      _LibraryFormatFilter.epub => book.format == 'epub',
      _LibraryFormatFilter.pdf => book.format == 'pdf',
      _LibraryFormatFilter.text =>
        book.format == 'txt' || book.format == 'markdown',
    };
    final matchesCategory =
        category == _allCategories ||
        (category == _uncategorized
            ? book.category?.isEmpty ?? true
            : book.category == category);
    final matchesTag = tag == null || book.tags.contains(tag);
    final searchableText =
        '${book.title} ${book.author} ${book.category ?? ''} ${book.tags.join(' ')}'
            .toLowerCase();
    return matchesFormat &&
        matchesCategory &&
        matchesTag &&
        (!favoritesOnly || book.isFavorite) &&
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

LibraryBook? _continueReadingBook(List<LibraryBook> books) {
  if (books.isEmpty) return null;
  final startedBooks =
      books.where((book) => book.progress > 0 || book.locator != null).toList()
        ..sort(
          (first, second) => (second.updatedAt ?? second.importedAt).compareTo(
            first.updatedAt ?? first.importedAt,
          ),
        );
  return startedBooks.isEmpty ? books.first : startedBooks.first;
}

const _allCategories = '__all_categories__';
const _uncategorized = '__uncategorized__';

List<String> _categoriesFor(List<LibraryBook> books) {
  final categories =
      books
          .map((book) => book.category?.trim() ?? '')
          .where((category) => category.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return categories;
}

List<String> _tagsFor(List<LibraryBook> books) {
  final tags = books.expand((book) => book.tags).toSet().toList()..sort();
  return tags;
}

class _LibraryControls extends StatelessWidget {
  const _LibraryControls({
    required this.formatFilter,
    required this.sort,
    required this.viewMode,
    required this.onQueryChanged,
    required this.onFormatChanged,
    required this.onSortChanged,
    required this.onViewModeChanged,
    required this.categories,
    required this.tags,
    required this.category,
    required this.tag,
    required this.favoritesOnly,
    required this.onCategoryChanged,
    required this.onTagChanged,
    required this.onFavoritesChanged,
  });

  final _LibraryFormatFilter formatFilter;
  final _LibrarySort sort;
  final _LibraryViewMode viewMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_LibraryFormatFilter> onFormatChanged;
  final ValueChanged<_LibrarySort> onSortChanged;
  final ValueChanged<_LibraryViewMode> onViewModeChanged;
  final List<String> categories;
  final List<String> tags;
  final String category;
  final String? tag;
  final bool favoritesOnly;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<bool> onFavoritesChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final searchWidth = constraints.maxWidth < 520
          ? constraints.maxWidth
          : 320.0;
      final colors = Theme.of(context).colorScheme;
      return Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: searchWidth,
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
                    onSelectionChanged: (selection) =>
                        onFormatChanged(selection.first),
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
                          DropdownMenuItem(
                            value: option,
                            child: Text(option.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onSortChanged(value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(category),
                      initialValue: category,
                      decoration: const InputDecoration(
                        labelText: '分类',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: _allCategories,
                          child: Text('全部分类'),
                        ),
                        const DropdownMenuItem(
                          value: _uncategorized,
                          child: Text('未分类'),
                        ),
                        for (final item in categories)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) {
                        if (value != null) onCategoryChanged(value);
                      },
                    ),
                  ),
                  FilterChip(
                    selected: favoritesOnly,
                    onSelected: onFavoritesChanged,
                    avatar: Icon(
                      favoritesOnly ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                    ),
                    label: const Text('收藏'),
                  ),
                  Tooltip(
                    message: '切换书库视图',
                    child: SegmentedButton<_LibraryViewMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _LibraryViewMode.grid,
                          icon: Icon(Icons.grid_view_outlined),
                        ),
                        ButtonSegment(
                          value: _LibraryViewMode.list,
                          icon: Icon(Icons.view_list_outlined),
                        ),
                      ],
                      selected: {viewMode},
                      onSelectionChanged: (selection) =>
                          onViewModeChanged(selection.first),
                    ),
                  ),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in tags)
                      ChoiceChip(
                        selected: tag == item,
                        onSelected: (selected) =>
                            onTagChanged(selected ? item : null),
                        label: Text(item),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectedCount,
    required this.isWorking,
    required this.allSelectedAreFavorite,
    required this.onCancel,
    required this.onToggleFavorite,
    required this.onChangeCategory,
    required this.onDelete,
  });

  final int selectedCount;
  final bool isWorking;
  final bool allSelectedAreFavorite;
  final VoidCallback onCancel;
  final VoidCallback onToggleFavorite;
  final VoidCallback onChangeCategory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('library-selection-toolbar'),
    color: Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '退出多选',
            onPressed: isWorking ? null : onCancel,
            icon: const Icon(Icons.close),
          ),
          Expanded(child: Text('已选择 $selectedCount 本书')),
          IconButton(
            tooltip: allSelectedAreFavorite ? '取消收藏' : '收藏书籍',
            onPressed: isWorking || selectedCount == 0
                ? null
                : onToggleFavorite,
            icon: Icon(
              allSelectedAreFavorite ? Icons.favorite : Icons.favorite_border,
            ),
          ),
          IconButton(
            tooltip: '设置分类',
            onPressed: isWorking || selectedCount == 0
                ? null
                : onChangeCategory,
            icon: const Icon(Icons.folder_outlined),
          ),
          IconButton(
            tooltip: '删除书籍',
            onPressed: isWorking || selectedCount == 0 ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
}

class _CategoryUpdate {
  const _CategoryUpdate(this.category);

  final String? category;
}

class _CategoryDialog extends HookWidget {
  const _CategoryDialog({required this.categories});

  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    return AlertDialog(
      title: const Text('设置分类'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '分类名称',
                border: OutlineInputBorder(),
              ),
            ),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    ActionChip(
                      label: Text(category),
                      onPressed: () => controller.text = category,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, const _CategoryUpdate(null)),
          child: const Text('清除分类'),
        ),
        FilledButton(
          onPressed: () {
            final category = controller.text.trim();
            if (category.isEmpty) return;
            Navigator.pop(context, _CategoryUpdate(category));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: Key('continue-reading-${book.id}'),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 96,
                height: 132,
                child: BookCover(book: book),
              ),
            ),
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
}

class _BookCard extends HookWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onLongPress,
    required this.isSelected,
    required this.selectionMode,
    required this.isRemoving,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;
  final bool selectionMode;
  final bool isRemoving;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final isHovered = useState(false);
    final colorScheme = Theme.of(context).colorScheme;
    final background = isSelected
        ? colorScheme.secondaryContainer
        : isHovered.value
        ? colorScheme.surfaceContainerLow
        : colorScheme.surface;
    final border = isSelected
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: AnimatedContainer(
        key: Key('book-${book.id}'),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isRemoving ? null : onTap,
            onLongPress: isRemoving ? null : onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Hero(
                            tag: bookCoverHeroTag(book),
                            child: BookCover(book: book),
                          ),
                        ),
                        if (selectionMode)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => onTap(),
                            ),
                          ),
                        if (!selectionMode)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              shape: const CircleBorder(),
                              child: PopupMenuButton<String>(
                                tooltip: '更多操作',
                                enabled: !isRemoving,
                                onSelected: (action) => action == 'favorite'
                                    ? onToggleFavorite()
                                    : onDelete(),
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'favorite',
                                    child: Text(
                                      book.isFavorite ? '取消收藏' : '收藏书籍',
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除书籍'),
                                  ),
                                ],
                                icon: isRemoving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.more_vert),
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
        ),
      ),
    );
  }
}

class _BookListItem extends StatelessWidget {
  const _BookListItem({
    required this.book,
    required this.onTap,
    required this.onLongPress,
    required this.isSelected,
    required this.selectionMode,
    required this.isRemoving,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;
  final bool selectionMode;
  final bool isRemoving;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('book-list-${book.id}'),
    color: isSelected ? Theme.of(context).colorScheme.secondaryContainer : null,
    child: InkWell(
      onTap: isRemoving ? null : onTap,
      onLongPress: isRemoving ? null : onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (selectionMode)
              Checkbox(value: isSelected, onChanged: (_) => onTap()),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 52,
                height: 76,
                child: Hero(
                  tag: bookCoverHeroTag(book),
                  child: BookCover(book: book),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author.isEmpty ? '未知作者' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        book.format.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LinearProgressIndicator(value: book.progress),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(book.progress * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!selectionMode)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                enabled: !isRemoving,
                onSelected: (action) =>
                    action == 'favorite' ? onToggleFavorite() : onDelete(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(book.isFavorite ? '取消收藏' : '收藏书籍'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('删除书籍')),
                ],
                icon: isRemoving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.more_vert),
              ),
          ],
        ),
      ),
    ),
  );
}
