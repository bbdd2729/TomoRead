import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/appearance.dart';
import '../../app/providers.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reading_settings.dart';
import '../chat/chat_page.dart';
import '../library/book_details_page.dart';
import '../library/library_home_page.dart';
import '../notes/notes_page.dart';
import '../reader/reader_workspace.dart';
import '../reader/pdf_reader_workspace.dart';
import '../settings/settings_page.dart';
import '../skills/skills_page.dart';
import '../statistics/statistics_page.dart';
import 'book_search_delegate.dart';
import '../../shared/widgets/resizable_pane.dart';

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
    this.bookFormat,
    this.closable = false,
  });

  final String id;
  final String title;
  final AppDestination destination;
  final String? bookId;
  final String? bookFormat;
  final bool closable;
}

class AppShell extends HookConsumerWidget {
  const AppShell({
    super.key,
    required this.appearance,
    required this.readingSettings,
    required this.onImportBooks,
    required this.onAppearanceChanged,
    required this.onReadingSettingsChanged,
  });

  final AppAppearance appearance;
  final ReadingSettings readingSettings;
  final Future<void> Function() onImportBooks;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final ValueChanged<ReadingSettings> onReadingSettingsChanged;

  static const _desktopBreakpoint = 840.0;
  static const _desktopNavigationMinWidth = 220.0;
  static const _desktopNavigationMaxWidth = 320.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = useState(<WorkspaceTab>[
      const WorkspaceTab(
        id: 'library',
        title: '书库',
        destination: AppDestination.library,
      ),
    ]);
    final activeTabId = useState('library');
    final navigationWidth = useState(appearance.desktopNavigationWidth);
    final navigationCollapsed = useState(appearance.desktopNavigationCollapsed);
    useEffect(
      () {
        navigationWidth.value = appearance.desktopNavigationWidth;
        navigationCollapsed.value = appearance.desktopNavigationCollapsed;
        return null;
      },
      [
        appearance.desktopNavigationWidth,
        appearance.desktopNavigationCollapsed,
      ],
    );
    final activeTab = tabs.value.firstWhere(
      (tab) => tab.id == activeTabId.value,
      orElse: () => tabs.value.first,
    );

    void openDestination(AppDestination destination) {
      final existingTab = tabs.value
          .where((tab) => tab.destination == destination)
          .firstOrNull;
      if (existingTab != null) {
        activeTabId.value = existingTab.id;
      } else {
        final tab = WorkspaceTab(
          id: destination.name,
          title: _destinationLabel(destination),
          destination: destination,
          closable: destination != AppDestination.library,
        );
        tabs.value = [...tabs.value, tab];
        activeTabId.value = tab.id;
      }
      Navigator.maybePop(context);
    }

    void openReader(LibraryBook book) {
      final tabId = 'reader-${book.id}';
      final existingTab = tabs.value
          .where((tab) => tab.id == tabId)
          .firstOrNull;
      if (existingTab == null) {
        tabs.value = [
          ...tabs.value,
          WorkspaceTab(
            id: tabId,
            title: book.title,
            destination: AppDestination.reader,
            bookId: book.id,
            bookFormat: book.format,
            closable: true,
          ),
        ];
      }
      activeTabId.value = tabId;
    }

    Future<void> openBookDetails(LibraryBook book) =>
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 220),
            reverseTransitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (routeContext, _, _) => BookDetailsPage(
              book: book,
              onOpenReader: (selectedBook) {
                Navigator.of(routeContext).pop();
                openReader(selectedBook);
              },
            ),
            transitionsBuilder: (_, animation, secondaryAnimation, child) =>
                FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .985, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                ),
          ),
        );

    void closeTab(WorkspaceTab tab) {
      if (!tab.closable) return;
      final index = tabs.value.indexOf(tab);
      final remainingTabs = tabs.value.where((item) => item != tab).toList();
      tabs.value = remainingTabs;
      if (activeTabId.value == tab.id) {
        activeTabId.value =
            remainingTabs[(index - 1).clamp(0, remainingTabs.length - 1)].id;
      }
    }

    void toggleNavigation() {
      final collapsed = !navigationCollapsed.value;
      navigationCollapsed.value = collapsed;
      onAppearanceChanged(
        appearance.copyWith(desktopNavigationCollapsed: collapsed),
      );
    }

    Future<void> openLibrarySearch() async {
      try {
        final books = await ref.read(libraryBooksProvider.future);
        if (!context.mounted) return;
        final selected = await showSearch<LibraryBook?>(
          context: context,
          delegate: BookSearchDelegate(books),
        );
        if (selected != null) openBookDetails(selected);
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法搜索书库：$error')));
      }
    }

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _OpenLibrarySearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _ToggleNavigationIntent(),
      },
      child: Actions(
        actions: {
          _OpenLibrarySearchIntent: CallbackAction<_OpenLibrarySearchIntent>(
            onInvoke: (_) {
              if (activeTab.destination == AppDestination.reader) return null;
              openLibrarySearch();
              return null;
            },
          ),
          _ToggleNavigationIntent: CallbackAction<_ToggleNavigationIntent>(
            onInvoke: (_) {
              if (activeTab.destination == AppDestination.reader) return null;
              toggleNavigation();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
              final activeDestination = activeTab.destination;
              final isReading = activeDestination == AppDestination.reader;
              final content = _WorkspaceContent(
                destination: activeDestination,
                appearance: appearance,
                readingSettings: readingSettings,
                readerBookId: activeTab.bookId,
                readerFormat: activeTab.bookFormat,
                readerTitle: activeTab.title,
                onExitReader: () => closeTab(activeTab),
                onAppearanceChanged: onAppearanceChanged,
                onReadingSettingsChanged: onReadingSettingsChanged,
                onOpenBookDetails: openBookDetails,
              );
              final animatedContent = isReading
                  ? content
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      reverseDuration: const Duration(milliseconds: 120),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(.01, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(activeTab.id),
                        child: content,
                      ),
                    );

              return Scaffold(
                appBar: isReading
                    ? null
                    : AppBar(
                        toolbarHeight: 52,
                        title: const Text('TomoRead'),
                        actions: [
                          if (isDesktop)
                            IconButton(
                              key: const Key('desktop-navigation-toggle'),
                              tooltip: navigationCollapsed.value
                                  ? 'Show navigation'
                                  : 'Hide navigation',
                              onPressed: toggleNavigation,
                              icon: Icon(
                                navigationCollapsed.value
                                    ? Icons.keyboard_double_arrow_right
                                    : Icons.keyboard_double_arrow_left,
                              ),
                            ),
                          IconButton(
                            tooltip: '搜索',
                            key: const Key('global-search'),
                            onPressed: openLibrarySearch,
                            icon: const Icon(Icons.search),
                          ),
                          const SizedBox(width: 8),
                        ],
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(40),
                          child: _WorkspaceTabBar(
                            tabs: tabs.value,
                            activeTabId: activeTabId.value,
                            onSelected: (tab) => activeTabId.value = tab.id,
                            onClosed: closeTab,
                          ),
                        ),
                      ),
                drawer: isReading || isDesktop
                    ? null
                    : _AppNavigationDrawer(
                        selected: activeDestination,
                        onSelected: openDestination,
                      ),
                body: isReading
                    ? content
                    : isDesktop
                    ? Row(
                        children: [
                          if (navigationCollapsed.value)
                            SizedBox(
                              width: 72,
                              child: _AppNavigationRail(
                                extended: false,
                                selected: activeDestination,
                                onSelected: openDestination,
                                onAddBook: onImportBooks,
                              ),
                            )
                          else
                            ResizablePane(
                              width: navigationWidth.value,
                              minWidth: _desktopNavigationMinWidth,
                              maxWidth: _desktopNavigationMaxWidth,
                              defaultWidth: 240,
                              onWidthChanged: (value) =>
                                  navigationWidth.value = value,
                              onWidthChangeEnd: (value) => onAppearanceChanged(
                                appearance.copyWith(
                                  desktopNavigationWidth: value,
                                ),
                              ),
                              child: _AppNavigationRail(
                                extended: true,
                                selected: activeDestination,
                                onSelected: openDestination,
                                onAddBook: onImportBooks,
                              ),
                            ),
                          Expanded(child: animatedContent),
                        ],
                      )
                    : animatedContent,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OpenLibrarySearchIntent extends Intent {
  const _OpenLibrarySearchIntent();
}

class _ToggleNavigationIntent extends Intent {
  const _ToggleNavigationIntent();
}

class _WorkspaceContent extends StatelessWidget {
  const _WorkspaceContent({
    required this.destination,
    required this.appearance,
    required this.readingSettings,
    required this.readerBookId,
    required this.readerFormat,
    required this.readerTitle,
    required this.onExitReader,
    required this.onAppearanceChanged,
    required this.onReadingSettingsChanged,
    required this.onOpenBookDetails,
  });

  final AppDestination destination;
  final AppAppearance appearance;
  final ReadingSettings readingSettings;
  final String? readerBookId;
  final String? readerFormat;
  final String readerTitle;
  final VoidCallback onExitReader;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final ValueChanged<ReadingSettings> onReadingSettingsChanged;
  final ValueChanged<LibraryBook> onOpenBookDetails;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AppDestination.library => LibraryHomePage(
        onOpenBookDetails: onOpenBookDetails,
      ),
      AppDestination.reader =>
        readerFormat == 'pdf'
            ? PdfReaderWorkspace(
                key: ValueKey(readerBookId),
                bookId: readerBookId ?? '',
                title: readerTitle,
                onExitReader: onExitReader,
              )
            : ReaderWorkspace(
                bookId: readerBookId ?? 'demo-reading-art',
                title: readerTitle,
                readingSettings: readingSettings,
                onExitReader: onExitReader,
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
                      Icon(_destinationIcon(tab.destination), size: 16),
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

class _AppNavigationRail extends StatelessWidget {
  const _AppNavigationRail({
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
