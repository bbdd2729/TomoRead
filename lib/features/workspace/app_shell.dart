import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/appearance.dart';
import '../../app/providers.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reading_settings.dart';
import '../library/book_details_page.dart';
import 'book_search_delegate.dart';
import 'desktop_header.dart';
import 'mobile_navigation_bar.dart';
import 'navigation_rail.dart';
import 'workspace_tab.dart';
import 'workspace_content.dart';
import '../../shared/widgets/resizable_pane.dart';

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
          title: destinationLabel(destination),
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

    void exitReaderToLibrary(WorkspaceTab tab) {
      if (tab.destination != AppDestination.reader ||
          !tabs.value.contains(tab)) {
        return;
      }
      final libraryTab = tabs.value.firstWhere(
        (item) => item.destination == AppDestination.library,
      );
      tabs.value = tabs.value.where((item) => item != tab).toList();
      activeTabId.value = libraryTab.id;
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
              final content = WorkspaceContent(
                destination: activeDestination,
                appearance: appearance,
                readingSettings: readingSettings,
                readerBookId: activeTab.bookId,
                readerFormat: activeTab.bookFormat,
                readerTitle: activeTab.title,
                onExitReader: () => isDesktop
                    ? closeTab(activeTab)
                    : exitReaderToLibrary(activeTab),
                onAppearanceChanged: onAppearanceChanged,
                onReadingSettingsChanged: onReadingSettingsChanged,
                onOpenBookDetails: openBookDetails,
                onOpenReader: openReader,
                onOpenChat: () => openDestination(AppDestination.chat),
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
                // The reader owns keyboard-aware overlays such as note
                // dialogs. Keeping its body stable prevents an IME from
                // resizing and rebuilding EPUB/TXT/PDF content underneath.
                resizeToAvoidBottomInset: !isReading,
                appBar: isReading || isDesktop
                    ? null
                    : AppBar(
                        toolbarHeight: 52,
                        title: const Text('TomoRead'),
                        actions: [
                          IconButton(
                            tooltip: '搜索',
                            key: const Key('global-search'),
                            onPressed: openLibrarySearch,
                            icon: const Icon(Icons.search),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                body: isReading
                    ? PopScope<void>(
                        canPop: isDesktop,
                        onPopInvokedWithResult: (didPop, _) {
                          if (!didPop && !isDesktop) {
                            exitReaderToLibrary(activeTab);
                          }
                        },
                        child: content,
                      )
                    : isDesktop
                    ? Row(
                        children: [
                          if (navigationCollapsed.value)
                            SizedBox(
                              width: 72,
                              child: AppNavigationRail(
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
                              child: AppNavigationRail(
                                extended: true,
                                selected: activeDestination,
                                onSelected: openDestination,
                                onAddBook: onImportBooks,
                              ),
                            ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: Column(
                              children: [
                                DesktopWorkspaceHeader(
                                  tabs: tabs.value,
                                  activeTabId: activeTabId.value,
                                  navigationCollapsed:
                                      navigationCollapsed.value,
                                  onSelected: (tab) =>
                                      activeTabId.value = tab.id,
                                  onClosed: closeTab,
                                  onToggleNavigation: toggleNavigation,
                                  onSearch: openLibrarySearch,
                                ),
                                Expanded(child: animatedContent),
                              ],
                            ),
                          ),
                        ],
                      )
                    : animatedContent,
                bottomNavigationBar: isReading || isDesktop
                    ? null
                    : MobileNavigationBar(
                        selected: activeDestination,
                        onSelected: openDestination,
                      ),
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
