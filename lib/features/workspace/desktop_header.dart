import 'package:flutter/material.dart';

import 'workspace_tab.dart';

class DesktopWorkspaceHeader extends StatelessWidget {
  const DesktopWorkspaceHeader({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.navigationCollapsed,
    required this.onSelected,
    required this.onClosed,
    required this.onToggleNavigation,
    required this.onSearch,
  });

  final List<WorkspaceTab> tabs;
  final String activeTabId;
  final bool navigationCollapsed;
  final ValueChanged<WorkspaceTab> onSelected;
  final ValueChanged<WorkspaceTab> onClosed;
  final VoidCallback onToggleNavigation;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              key: const Key('desktop-navigation-toggle'),
              tooltip: navigationCollapsed ? '展开侧边栏' : '收起侧边栏',
              onPressed: onToggleNavigation,
              icon: Icon(
                navigationCollapsed
                    ? Icons.keyboard_double_arrow_right
                    : Icons.keyboard_double_arrow_left,
              ),
            ),
            Expanded(
              child: WorkspaceTabBar(
                tabs: tabs,
                activeTabId: activeTabId,
                onSelected: onSelected,
                onClosed: onClosed,
              ),
            ),
            IconButton(
              tooltip: '搜索书库',
              key: const Key('global-search'),
              onPressed: onSearch,
              icon: const Icon(Icons.search),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class WorkspaceTabBar extends StatelessWidget {
  const WorkspaceTabBar({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onSelected,
    required this.onClosed,
  });

  final List<WorkspaceTab> tabs;
  final String activeTabId;
  final ValueChanged<WorkspaceTab> onSelected;
  final ValueChanged<WorkspaceTab> onClosed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: tabs.length,
          separatorBuilder: (context, index) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final active = tab.id == activeTabId;
            return Material(
              color: active
                  ? Theme.of(context).colorScheme.surfaceContainerLow
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelected(tab),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(destinationIcon(tab.destination), size: 16),
                      const SizedBox(width: 7),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(tab.title, overflow: TextOverflow.ellipsis),
                      ),
                      if (tab.closable) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          tooltip: '关闭 ${tab.title}',
                          onPressed: () => onClosed(tab),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
