enum LibraryFormatFilter { all, epub, pdf, text }

enum LibrarySort { recent, title, progress }

enum LibraryViewMode { grid, list }

const allCategoriesFilter = '__all_categories__';
const uncategorizedCategoryFilter = '_uncategorizedCategoryFilter__';

class LibraryWorkspaceState {
  const LibraryWorkspaceState({
    this.formatFilter = LibraryFormatFilter.all,
    this.sort = LibrarySort.recent,
    this.viewMode = LibraryViewMode.grid,
    this.category = allCategoriesFilter,
    this.tag,
    this.favoritesOnly = false,
  });

  static const version = 1;

  final LibraryFormatFilter formatFilter;
  final LibrarySort sort;
  final LibraryViewMode viewMode;
  final String category;
  final String? tag;
  final bool favoritesOnly;

  factory LibraryWorkspaceState.fromJson(Object? source) {
    if (source is! Map<Object?, Object?> || source['version'] != version) {
      return const LibraryWorkspaceState();
    }
    final category = source['category'];
    final tag = source['tag'];
    return LibraryWorkspaceState(
      formatFilter: _formatFilterFromName(source['formatFilter']),
      sort: _sortFromName(source['sort']),
      viewMode: _viewModeFromName(source['viewMode']),
      category: category is String && category.trim().isNotEmpty
          ? category.trim()
          : allCategoriesFilter,
      tag: tag is String && tag.trim().isNotEmpty ? tag.trim() : null,
      favoritesOnly: source['favoritesOnly'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'formatFilter': formatFilter.name,
    'sort': sort.name,
    'viewMode': viewMode.name,
    'category': category,
    'tag': tag,
    'favoritesOnly': favoritesOnly,
  };

  LibraryWorkspaceState copyWith({
    LibraryFormatFilter? formatFilter,
    LibrarySort? sort,
    LibraryViewMode? viewMode,
    String? category,
    String? tag,
    bool? favoritesOnly,
    bool clearTag = false,
  }) => LibraryWorkspaceState(
    formatFilter: formatFilter ?? this.formatFilter,
    sort: sort ?? this.sort,
    viewMode: viewMode ?? this.viewMode,
    category: category ?? this.category,
    tag: clearTag ? null : tag ?? this.tag,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
  );

  LibraryWorkspaceState normalizedForOptions({
    required Iterable<String> categories,
    required Iterable<String> tags,
  }) {
    final validCategory =
        category == allCategoriesFilter ||
            category == uncategorizedCategoryFilter ||
            categories.contains(category)
        ? category
        : allCategoriesFilter;
    final validTag = tag != null && tags.contains(tag) ? tag : null;
    return LibraryWorkspaceState(
      formatFilter: formatFilter,
      sort: sort,
      viewMode: viewMode,
      category: validCategory,
      tag: validTag,
      favoritesOnly: favoritesOnly,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryWorkspaceState &&
      other.formatFilter == formatFilter &&
      other.sort == sort &&
      other.viewMode == viewMode &&
      other.category == category &&
      other.tag == tag &&
      other.favoritesOnly == favoritesOnly;

  @override
  int get hashCode =>
      Object.hash(formatFilter, sort, viewMode, category, tag, favoritesOnly);
}

LibraryFormatFilter _formatFilterFromName(Object? value) =>
    LibraryFormatFilter.values.firstWhere(
      (item) => item.name == value,
      orElse: () => LibraryFormatFilter.all,
    );

LibrarySort _sortFromName(Object? value) => LibrarySort.values.firstWhere(
  (item) => item.name == value,
  orElse: () => LibrarySort.recent,
);

LibraryViewMode _viewModeFromName(Object? value) =>
    LibraryViewMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => LibraryViewMode.grid,
    );
