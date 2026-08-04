import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../domain/models/epub_manifest.dart';

Set<String> tocExpandedKeysForActive(
  List<EpubTocItem> items,
  int activeChapterIndex, {
  required String rootKey,
}) {
  final expanded = <String>{};

  bool visit(List<EpubTocItem> entries, String parentKey) {
    var containsActive = false;
    for (var index = 0; index < entries.length; index++) {
      final item = entries[index];
      final nodeKey = '$parentKey/$index';
      final childContainsActive = visit(item.children, nodeKey);
      final itemContainsActive =
          item.spineIndex == activeChapterIndex || childContainsActive;
      if (itemContainsActive && item.children.isNotEmpty) {
        expanded.add(nodeKey);
      }
      if (itemContainsActive) containsActive = true;
    }
    return containsActive;
  }

  visit(items, rootKey);
  return expanded;
}

class ReaderTocPanel extends HookWidget {
  const ReaderTocPanel({
    required this.toc,
    required this.activeChapterIndex,
    required this.onSelected,
  });

  final List<EpubTocItem> toc;
  final int activeChapterIndex;
  final ValueChanged<EpubTocItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final query = useState('');
    final scrollController = useScrollController();
    final activeItemKey = useMemoized(GlobalKey.new);
    final expandedKeys = useState(
      tocExpandedKeysForActive(toc, activeChapterIndex, rootKey: 'desktop'),
    );
    final hasMatches = _hasMatchingItem(toc, query.value);
    useEffect(() {
      final activePath = tocExpandedKeysForActive(
        toc,
        activeChapterIndex,
        rootKey: 'desktop',
      );
      if (activePath.any((key) => !expandedKeys.value.contains(key))) {
        expandedKeys.value = {...expandedKeys.value, ...activePath};
      }
      return null;
    }, [toc, activeChapterIndex]);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = activeItemKey.currentContext;
        if (targetContext != null) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 180),
            alignment: 0.3,
          );
        }
      });
      return null;
    }, [activeChapterIndex, query.value]);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Text('目录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          key: const Key('reader-toc-search'),
          onChanged: (value) => query.value = value,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: '搜索目录',
            border: const OutlineInputBorder(),
            suffixIcon: query.value.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: () => query.value = '',
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (toc.isEmpty)
          const Text('该书没有可用目录。')
        else if (!hasMatches)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('没有匹配的章节。')),
          )
        else
          ..._buildTocItems(
            toc,
            activeItemKey: activeItemKey,
            depth: 0,
            query: query.value,
            parentKey: 'desktop',
            expandedKeys: expandedKeys.value,
            onToggle: (key) {
              final next = {...expandedKeys.value};
              if (!next.add(key)) next.remove(key);
              expandedKeys.value = next;
            },
          ),
      ],
    );
  }

  bool _hasMatchingItem(List<EpubTocItem> items, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    return items.any(
      (item) =>
          item.title.toLowerCase().contains(normalizedQuery) ||
          _hasMatchingItem(item.children, query),
    );
  }

  List<Widget> _buildTocItems(
    List<EpubTocItem> items, {
    required GlobalKey activeItemKey,
    required int depth,
    required String query,
    required String parentKey,
    required Set<String> expandedKeys,
    required ValueChanged<String> onToggle,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final widgets = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final nodeKey = '$parentKey/$index';
      final matchesTitle =
          normalizedQuery.isEmpty ||
          item.title.toLowerCase().contains(normalizedQuery);
      final matchesChildren = _hasMatchingItem(item.children, query);
      if (!matchesTitle && !matchesChildren) continue;
      final hasChildren = item.children.isNotEmpty;
      final expanded =
          expandedKeys.contains(nodeKey) ||
          (normalizedQuery.isNotEmpty && matchesChildren);
      widgets.add(
        _TocListItem(
          key: item.spineIndex == activeChapterIndex ? activeItemKey : null,
          title: item.title,
          depth: depth,
          enabled: item.spineIndex >= 0,
          selected: item.spineIndex == activeChapterIndex,
          onTap: item.spineIndex < 0 ? null : () => onSelected(item),
          hasChildren: hasChildren,
          expanded: expanded,
          onToggle: hasChildren ? () => onToggle(nodeKey) : null,
        ),
      );
      if (hasChildren && expanded) {
        widgets.addAll(
          _buildTocItems(
            item.children,
            activeItemKey: activeItemKey,
            depth: depth + 1,
            query: query,
            parentKey: nodeKey,
            expandedKeys: expandedKeys,
            onToggle: onToggle,
          ),
        );
      }
    }
    return widgets;
  }
}

class _TocListItem extends StatelessWidget {
  const _TocListItem({
    super.key,
    required this.title,
    required this.depth,
    required this.enabled,
    required this.selected,
    required this.onTap,
    required this.hasChildren,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final int depth;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Material(
        color: selected ? colorScheme.surfaceContainerLow : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(
          contentPadding: EdgeInsets.only(left: depth * 16.0 + 12, right: 12),
          enabled: enabled || hasChildren,
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: selected
                ? TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  )
                : null,
          ),
          onTap: onTap,
          trailing: hasChildren
              ? IconButton(
                  tooltip: expanded ? '折叠章节' : '展开章节',
                  onPressed: onToggle,
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                )
              : null,
        ),
      ),
    );
  }
}
