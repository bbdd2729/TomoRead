import 'package:flutter/material.dart';

import 'workspace_tab.dart';

class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.extended,
    required this.selected,
    required this.onSelected,
    required this.onAddBook,
  });

  final bool extended;
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final VoidCallback onAddBook;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = selected.index < 5 ? selected.index : null;
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 236,
      selectedIndex: selectedIndex,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        child: extended
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TomoReadBrand(compact: false),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onAddBook,
                      icon: const Icon(Icons.add),
                      label: const Text('导入书籍'),
                    ),
                  ),
                ],
              )
            : Tooltip(
                message: '导入书籍',
                child: IconButton.filledTonal(
                  onPressed: onAddBook,
                  icon: const Icon(Icons.add),
                ),
              ),
      ),
      trailing: extended
          ? Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TextButton.icon(
                  key: const Key('settings-navigation'),
                  onPressed: () => onSelected(AppDestination.settings),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('设置'),
                ),
              ),
            )
          : null,
      onDestinationSelected: (index) =>
          onSelected(navigationDestinations[index]),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.local_library_outlined),
          selectedIcon: Icon(Icons.local_library),
          label: Text('书库'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: Text('对话'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.sticky_note_2_outlined),
          selectedIcon: Icon(Icons.sticky_note_2),
          label: Text('笔记'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.extension_outlined),
          selectedIcon: Icon(Icons.extension),
          label: Text('技能'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: Text('阅读统计'),
        ),
      ],
    );
  }
}

class _TomoReadBrand extends StatelessWidget {
  const _TomoReadBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (compact) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.auto_stories, color: colors.onPrimaryContainer),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.auto_stories, color: colors.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TomoRead',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '阅读与思考',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
