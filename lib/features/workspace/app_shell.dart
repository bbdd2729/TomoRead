import 'package:flutter/material.dart';

import '../../app/appearance.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reading_settings.dart';
import '../chat/chat_page.dart';
import '../library/library_home_page.dart';
import '../library/library_controller.dart';
import '../notes/notes_page.dart';
import '../reader/reader_workspace.dart';
import '../settings/settings_page.dart';
import '../skills/skills_page.dart';
import '../statistics/statistics_page.dart';

enum AppDestination {
  library,
  chat,
  notes,
  skills,
  statistics,
  settings,
  reader,
}

class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.title,
    required this.destination,
    this.bookId,
    this.closable = false,
  });

  final String id;
  final String title;
  final AppDestination destination;
  final String? bookId;
  final bool closable;
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.appearance,
    required this.readingSettings,
    required this.settingsRepository,
    required this.bookmarkRepository,
    required this.libraryController,
    required this.onAppearanceChanged,
    required this.onReadingSettingsChanged,
  });

  final AppAppearance appearance;
  final ReadingSettings readingSettings;
  final SettingsRepository settingsRepository;
  final BookmarkRepository bookmarkRepository;
  final LibraryController libraryController;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final ValueChanged<ReadingSettings> onReadingSettingsChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _desktopBreakpoint = 840.0;
  final _tabs = <WorkspaceTab>[
    const WorkspaceTab(
      id: 'library',
      title: '书库',
      destination: AppDestination.library,
    ),
  ];
  String _activeTabId = 'library';

  WorkspaceTab get _activeTab => _tabs.firstWhere(
    (tab) => tab.id == _activeTabId,
    orElse: () => _tabs.first,
  );

  void _openDestination(AppDestination destination) {
    final existingTab = _tabs
        .where((tab) => tab.destination == destination)
        .firstOrNull;
    setState(() {
      if (existingTab != null) {
        _activeTabId = existingTab.id;
      } else {
        final tab = WorkspaceTab(
          id: destination.name,
          title: _destinationLabel(destination),
          destination: destination,
          closable: destination != AppDestination.library,
        );
        _tabs.add(tab);
        _activeTabId = tab.id;
      }
    });
    Navigator.maybePop(context);
  }

  void _openReader(LibraryBook book) {
    final tabId = 'reader-${book.title}';
    final existingTab = _tabs.where((tab) => tab.id == tabId).firstOrNull;
    setState(() {
      if (existingTab == null) {
        _tabs.add(
          WorkspaceTab(
            id: tabId,
            title: book.title,
            destination: AppDestination.reader,
            bookId: book.id,
            closable: true,
          ),
        );
      }
      _activeTabId = tabId;
    });
  }

  void _closeTab(WorkspaceTab tab) {
    if (!tab.closable) return;
    setState(() {
      final index = _tabs.indexOf(tab);
      _tabs.remove(tab);
      if (_activeTabId == tab.id) {
        _activeTabId = _tabs[(index - 1).clamp(0, _tabs.length - 1)].id;
      }
    });
  }

  void _showPlaceholderMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        final activeDestination = _activeTab.destination;
        final content = _WorkspaceContent(
          destination: activeDestination,
          appearance: widget.appearance,
          readingSettings: widget.readingSettings,
          settingsRepository: widget.settingsRepository,
          bookmarkRepository: widget.bookmarkRepository,
          libraryController: widget.libraryController,
          readerBookId: _activeTab.bookId,
          readerTitle: _activeTab.title,
          onAppearanceChanged: widget.onAppearanceChanged,
          onReadingSettingsChanged: widget.onReadingSettingsChanged,
          onOpenReader: _openReader,
          onAction: _showPlaceholderMessage,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('TomoRead'),
            actions: [
              IconButton(
                tooltip: '搜索',
                onPressed: () => _showPlaceholderMessage('书库搜索将在下一阶段接入。'),
                icon: const Icon(Icons.search),
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _WorkspaceTabBar(
                tabs: _tabs,
                activeTabId: _activeTabId,
                onSelected: (tab) => setState(() => _activeTabId = tab.id),
                onClosed: _closeTab,
              ),
            ),
          ),
          drawer: isDesktop
              ? null
              : _AppNavigationDrawer(
                  selected: activeDestination,
                  onSelected: _openDestination,
                ),
          body: isDesktop
              ? Row(
                  children: [
                    _AppNavigationRail(
                      selected: activeDestination,
                      onSelected: _openDestination,
                      onAddBook: widget.libraryController.importFromPicker,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : content,
        );
      },
    );
  }
}

class _WorkspaceContent extends StatelessWidget {
  const _WorkspaceContent({
    required this.destination,
    required this.appearance,
    required this.readingSettings,
    required this.settingsRepository,
    required this.bookmarkRepository,
    required this.libraryController,
    required this.readerBookId,
    required this.readerTitle,
    required this.onAppearanceChanged,
    required this.onReadingSettingsChanged,
    required this.onOpenReader,
    required this.onAction,
  });

  final AppDestination destination;
  final AppAppearance appearance;
  final ReadingSettings readingSettings;
  final SettingsRepository settingsRepository;
  final BookmarkRepository bookmarkRepository;
  final LibraryController libraryController;
  final String? readerBookId;
  final String readerTitle;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final ValueChanged<ReadingSettings> onReadingSettingsChanged;
  final ValueChanged<LibraryBook> onOpenReader;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AppDestination.library => LibraryHomePage(
        controller: libraryController,
        onOpenReader: onOpenReader,
      ),
      AppDestination.reader => ReaderWorkspace(
        bookId: readerBookId ?? 'demo-reading-art',
        title: readerTitle,
        readingSettings: readingSettings,
        settingsRepository: settingsRepository,
        bookmarkRepository: bookmarkRepository,
      ),
      AppDestination.chat => const ChatPage(),
      AppDestination.notes => const NotesPage(),
      AppDestination.skills => const SkillsPage(),
      AppDestination.statistics => const StatisticsPage(),
      AppDestination.settings => SettingsPage(
        appearance: appearance,
        readingSettings: readingSettings,
        onAppearanceChanged: onAppearanceChanged,
        onReadingSettingsChanged: onReadingSettingsChanged,
      ),
    };
  }
}

class _WorkspaceTabBar extends StatelessWidget {
  const _WorkspaceTabBar({
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
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: tabs.length,
          separatorBuilder: (context, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final active = tab.id == activeTabId;
            return Material(
              color: active
                  ? Theme.of(context).colorScheme.secondaryContainer
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
                      Icon(_destinationIcon(tab.destination), size: 18),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(tab.title, overflow: TextOverflow.ellipsis),
                      ),
                      if (tab.closable) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
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

class _AppNavigationRail extends StatelessWidget {
  const _AppNavigationRail({
    required this.selected,
    required this.onSelected,
    required this.onAddBook,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final VoidCallback onAddBook;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = selected.index < 5 ? selected.index : null;
    return NavigationRail(
      extended: true,
      minExtendedWidth: 220,
      selectedIndex: selectedIndex,
      leading: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FloatingActionButton.small(
          tooltip: '添加书籍',
          onPressed: onAddBook,
          child: const Icon(Icons.add),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: TextButton.icon(
            key: const Key('settings-navigation'),
            onPressed: () => onSelected(AppDestination.settings),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('设置'),
          ),
        ),
      ),
      onDestinationSelected: (index) =>
          onSelected(_navigationDestinations[index]),
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

class _AppNavigationDrawer extends StatelessWidget {
  const _AppNavigationDrawer({
    required this.selected,
    required this.onSelected,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _navigationDestinations.indexOf(selected);
    return NavigationDrawer(
      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
      onDestinationSelected: (index) => onSelected(_drawerDestinations[index]),
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: Text(
            'TomoRead',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.local_library_outlined),
          selectedIcon: Icon(Icons.local_library),
          label: Text('书库'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: Text('对话'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.sticky_note_2_outlined),
          selectedIcon: Icon(Icons.sticky_note_2),
          label: Text('笔记'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.extension_outlined),
          selectedIcon: Icon(Icons.extension),
          label: Text('技能'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: Text('阅读统计'),
        ),
        Divider(),
        NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('设置'),
        ),
      ],
    );
  }
}

const _navigationDestinations = [
  AppDestination.library,
  AppDestination.chat,
  AppDestination.notes,
  AppDestination.skills,
  AppDestination.statistics,
];

const _drawerDestinations = [
  ..._navigationDestinations,
  AppDestination.settings,
];

String _destinationLabel(AppDestination destination) => switch (destination) {
  AppDestination.library => '书库',
  AppDestination.chat => '对话',
  AppDestination.notes => '笔记',
  AppDestination.skills => '技能',
  AppDestination.statistics => '阅读统计',
  AppDestination.settings => '设置',
  AppDestination.reader => '阅读器',
};

IconData _destinationIcon(AppDestination destination) => switch (destination) {
  AppDestination.library => Icons.local_library,
  AppDestination.chat => Icons.forum,
  AppDestination.notes => Icons.sticky_note_2,
  AppDestination.skills => Icons.extension,
  AppDestination.statistics => Icons.bar_chart,
  AppDestination.settings => Icons.settings,
  AppDestination.reader => Icons.menu_book,
};
