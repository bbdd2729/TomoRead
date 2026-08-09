import 'package:flutter/material.dart';

import '../../domain/models/library_book.dart';
import '../../domain/models/library_workspace_state.dart';

extension on LibraryFormatFilter {
  String get label => switch (this) {
    LibraryFormatFilter.all => '全部',
    LibraryFormatFilter.epub => 'EPUB',
    LibraryFormatFilter.pdf => 'PDF',
    LibraryFormatFilter.text => 'TXT/Markdown',
  };
}

extension on LibrarySort {
  String get label => switch (this) {
    LibrarySort.recent => '最近阅读',
    LibrarySort.title => '书名',
    LibrarySort.progress => '阅读进度',
  };
}

List<LibraryBook> filterAndSortBooks(
  List<LibraryBook> books, {
  required String query,
  required LibraryFormatFilter formatFilter,
  required LibrarySort sort,
  required String category,
  required String? tag,
  required bool favoritesOnly,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = books.where((book) {
    final matchesFormat = switch (formatFilter) {
      LibraryFormatFilter.all => true,
      LibraryFormatFilter.epub => book.format == 'epub',
      LibraryFormatFilter.pdf => book.format == 'pdf',
      LibraryFormatFilter.text =>
        book.format == 'txt' || book.format == 'markdown',
    };
    final matchesCategory =
        category == allCategoriesFilter ||
        (category == uncategorizedCategoryFilter
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
    LibrarySort.recent =>
      (first, second) => (second.updatedAt ?? second.importedAt).compareTo(
        first.updatedAt ?? first.importedAt,
      ),
    LibrarySort.title => (first, second) => first.title.toLowerCase().compareTo(
      second.title.toLowerCase(),
    ),
    LibrarySort.progress => (first, second) => second.progress.compareTo(
      first.progress,
    ),
  });
  return filtered;
}

LibraryBook? continueReadingBook(List<LibraryBook> books) {
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

List<String> categoriesFor(List<LibraryBook> books) {
  final categories =
      books
          .map((book) => book.category?.trim() ?? '')
          .where((category) => category.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return categories;
}

List<String> tagsFor(List<LibraryBook> books) {
  final tags = books.expand((book) => book.tags).toSet().toList()..sort();
  return tags;
}

class LibraryControls extends StatelessWidget {
  const LibraryControls({
    super.key,
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

  final LibraryFormatFilter formatFilter;
  final LibrarySort sort;
  final LibraryViewMode viewMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<LibraryFormatFilter> onFormatChanged;
  final ValueChanged<LibrarySort> onSortChanged;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
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
      final compact = constraints.maxWidth < 600;
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
                  compact
                      ? SizedBox(
                          width: constraints.maxWidth,
                          child: DropdownButtonFormField<LibraryFormatFilter>(
                            key: const Key('library-format-selector'),
                            initialValue: formatFilter,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '格式',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final filter in LibraryFormatFilter.values)
                                DropdownMenuItem(
                                  value: filter,
                                  child: Text(
                                    filter.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) onFormatChanged(value);
                            },
                          ),
                        )
                      : SegmentedButton<LibraryFormatFilter>(
                          segments: [
                            for (final filter in LibraryFormatFilter.values)
                              ButtonSegment(
                                value: filter,
                                label: Text(
                                  filter.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          selected: {formatFilter},
                          onSelectionChanged: (selection) =>
                              onFormatChanged(selection.first),
                        ),
                  SizedBox(
                    width: 152,
                    child: DropdownButtonFormField<LibrarySort>(
                      initialValue: sort,
                      decoration: const InputDecoration(
                        labelText: '排序',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final option in LibrarySort.values)
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
                          value: allCategoriesFilter,
                          child: Text('全部分类'),
                        ),
                        const DropdownMenuItem(
                          value: uncategorizedCategoryFilter,
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
                    child: SegmentedButton<LibraryViewMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: LibraryViewMode.grid,
                          icon: Icon(Icons.grid_view_outlined),
                        ),
                        ButtonSegment(
                          value: LibraryViewMode.list,
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
