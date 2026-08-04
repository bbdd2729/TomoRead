import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import '../../shared/widgets/book_cover.dart';
import 'reader_side_panel.dart';
import 'reader_toc_panel.dart';

class MobileReaderTocDrawer extends HookWidget {
  const MobileReaderTocDrawer({
    required this.title,
    required this.book,
    required this.chapterCount,
    required this.toc,
    required this.activeChapterIndex,
    required this.onSelected,
  });

  final String title;
  final LibraryBook? book;
  final int chapterCount;
  final List<EpubTocItem> toc;
  final int activeChapterIndex;
  final ValueChanged<EpubTocItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final query = useState('');
    final expandedKeys = useState(
      tocExpandedKeysForActive(toc, activeChapterIndex, rootKey: 'mobile'),
    );
    useEffect(() {
      final activePath = tocExpandedKeysForActive(
        toc,
        activeChapterIndex,
        rootKey: 'mobile',
      );
      if (activePath.any((key) => !expandedKeys.value.contains(key))) {
        expandedKeys.value = {...expandedKeys.value, ...activePath};
      }
      return null;
    }, [toc, activeChapterIndex]);

    void toggleNode(String key) {
      final next = {...expandedKeys.value};
      if (!next.add(key)) next.remove(key);
      expandedKeys.value = next;
    }

    final bookTitle = book?.title ?? title;
    final author = book?.author;
    return ReaderBottomSheet(
      child: Column(
        children: [
          Padding(
            key: const Key('reader-mobile-toc-header'),
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 92,
                  child: book == null
                      ? const DecoratedBox(
                          decoration: BoxDecoration(color: Colors.grey),
                          child: Icon(Icons.menu_book_outlined),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: BookCover(book: book!),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        author == null || author.isEmpty ? '未知作者' : author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$chapterCount 章',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('reader-mobile-toc-close'),
                  tooltip: '关闭目录',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const Key('reader-mobile-toc-search'),
              onChanged: (value) => query.value = value,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索目录',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: query.value.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () => query.value = '',
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: toc.isEmpty
                ? const Center(child: Text('暂无可用目录。'))
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (var index = 0; index < toc.length; index++)
                        _MobileTocEntry(
                          item: toc[index],
                          activeChapterIndex: activeChapterIndex,
                          onSelected: onSelected,
                          nodeKey: 'mobile/$index',
                          query: query.value,
                          expandedKeys: expandedKeys.value,
                          onToggle: toggleNode,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MobileTocEntry extends StatelessWidget {
  const _MobileTocEntry({
    required this.item,
    required this.activeChapterIndex,
    required this.onSelected,
    required this.nodeKey,
    required this.query,
    required this.expandedKeys,
    required this.onToggle,
    this.depth = 0,
  });

  final EpubTocItem item;
  final int activeChapterIndex;
  final ValueChanged<EpubTocItem> onSelected;
  final String nodeKey;
  final String query;
  final Set<String> expandedKeys;
  final ValueChanged<String> onToggle;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final matchesTitle =
        normalizedQuery.isEmpty ||
        item.title.toLowerCase().contains(normalizedQuery);
    final matchesChildren = _hasMatchingTocItem(item.children, query);
    if (!matchesTitle && !matchesChildren) return const SizedBox.shrink();
    final padding = EdgeInsetsDirectional.only(start: 12 + depth * 16.0);
    if (item.children.isEmpty) {
      return ListTile(
        contentPadding: padding,
        selected: item.spineIndex == activeChapterIndex,
        enabled: item.spineIndex >= 0,
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: item.spineIndex < 0 ? null : () => onSelected(item),
      );
    }
    final expanded =
        expandedKeys.contains(nodeKey) ||
        (normalizedQuery.isNotEmpty && matchesChildren);
    return Column(
      children: [
        ListTile(
          contentPadding: padding,
          selected: item.spineIndex == activeChapterIndex,
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: item.spineIndex < 0 ? null : () => onSelected(item),
          trailing: IconButton(
            tooltip: expanded ? '折叠章节' : '展开章节',
            onPressed: () => onToggle(nodeKey),
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ),
        ),
        if (expanded)
          for (var index = 0; index < item.children.length; index++)
            _MobileTocEntry(
              item: item.children[index],
              activeChapterIndex: activeChapterIndex,
              onSelected: onSelected,
              nodeKey: '$nodeKey/$index',
              query: query,
              expandedKeys: expandedKeys,
              onToggle: onToggle,
              depth: depth + 1,
            ),
      ],
    );
  }

  bool _hasMatchingTocItem(List<EpubTocItem> items, String searchQuery) {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    return items.any(
      (entry) =>
          entry.title.toLowerCase().contains(normalizedQuery) ||
          _hasMatchingTocItem(entry.children, searchQuery),
    );
  }
}
