import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/appearance.dart';
import '../../app/providers.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reader_chapter.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_settings.dart';
import '../../shared/widgets/resizable_pane.dart';
import '../../shared/widgets/book_cover.dart';
import 'epub_webview.dart';
import 'reader_runtime_controller.dart';
import 'reader_search_dialog.dart';

enum _MobileReaderToolbarAction { search, settings, focus }

void _noopReaderAction() {}

class _ReaderPreviousIntent extends Intent {
  const _ReaderPreviousIntent();
}

class _ReaderNextIntent extends Intent {
  const _ReaderNextIntent();
}

class _ReaderSearchIntent extends Intent {
  const _ReaderSearchIntent();
}

class _ReaderFocusIntent extends Intent {
  const _ReaderFocusIntent();
}

class ReaderWorkspace extends HookConsumerWidget {
  const ReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
    required this.readingSettings,
    this.onExitReader = _noopReaderAction,
    this.initialControlsVisible = false,
  });

  final String bookId;
  final String title;
  final ReadingSettings readingSettings;
  final VoidCallback onExitReader;
  final bool initialControlsVisible;

  static double _overallProgress(
    int chapterIndex,
    double chapterRatio,
    int chapterCount,
  ) {
    if (chapterCount == 0) return 0;
    return ((chapterIndex + chapterRatio.clamp(0, 1)) / chapterCount)
        .clamp(0, 1)
        .toDouble();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingOverride = ref.watch(bookReadingOverrideProvider(bookId));
    final runtimeController = ref.read(
      readerRuntimeControllerProvider.notifier,
    );
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    final readerBook = ref.watch(readerBookProvider(bookId));
    final manifest = ref.watch(readerManifestProvider(bookId));
    final annotationsState = ref.watch(annotationsForBookProvider(bookId));
    final appearance =
        ref.watch(appSettingsProvider).value?.appearance ??
        const AppAppearance();
    final tocVisible = useState(false);
    final sidePanelVisible = useState(false);
    final controlsVisible = useState(initialControlsVisible);
    final tocPanelWidth = useState(appearance.readerTocWidth);
    final sidePanelWidth = useState(appearance.readerSidePanelWidth);
    final showBookmarks = useState(false);
    final chapterIndex = useState(0);
    final scrollRatio = useState(0.0);
    final activeAnchor = useState<String?>(null);
    final activeCfi = useState<String?>(null);
    final restoreRevision = useState(0);
    final pageIndex = useState(0);
    final pageCount = useState(1);
    final requestedPage = useState<int?>(null);
    final focusedAnnotationId = useState<String?>(null);
    final annotationFocusRevision = useState(0);
    final progressWriteTimer = useRef<Timer?>(null);
    final selectedText = useState<ReaderTextSelection?>(null);
    final override = readingOverride.value;
    final bookmarkItems = bookmarks.value ?? const <Bookmark>[];
    final annotations = annotationsState.value ?? const <ReadingAnnotation>[];
    final settings = override?.settings ?? readingSettings;
    final isPaginated = settings.layoutMode == ReaderLayoutMode.paginated;
    final totalChapters = manifest.value?.spine.length ?? 0;
    final activeChapterIndex = totalChapters == 0
        ? chapterIndex.value
        : chapterIndex.value.clamp(0, totalChapters - 1).toInt();
    final chapter = ref.watch(
      readerChapterProvider((bookId: bookId, chapterIndex: activeChapterIndex)),
    );
    final currentLocation = EpubLocation(
      chapterIndex: activeChapterIndex,
      scrollRatio: scrollRatio.value,
      anchor: activeAnchor.value,
      cfi: activeCfi.value,
    );
    final currentLocator = currentLocation.toLocator();
    final chapterTitle =
        chapter.value?.title ?? '第 ${activeChapterIndex + 1} 章';
    final isLoading =
        readingOverride.isLoading || bookmarks.isLoading || chapter.isLoading;
    final isBookmarked = bookmarkItems.any(
      (bookmark) => EpubLocation.matchesLocator(
        bookmark.locator,
        currentLocation,
        fallbackChapterIndex: activeChapterIndex,
      ),
    );

    useEffect(() {
      tocPanelWidth.value = appearance.readerTocWidth;
      sidePanelWidth.value = appearance.readerSidePanelWidth;
      return null;
    }, [appearance.readerTocWidth, appearance.readerSidePanelWidth]);

    useEffect(() {
      final savedIndex = readerBook.value?.chapterIndex;
      if (savedIndex != null) {
        final location = EpubLocation.fromLocator(
          readerBook.value?.locator,
          fallbackChapterIndex: savedIndex,
        );
        chapterIndex.value = location.chapterIndex;
        scrollRatio.value = location.scrollRatio;
        activeAnchor.value = location.anchor;
        activeCfi.value = location.cfi;
        restoreRevision.value += 1;
      }
      return null;
    }, [bookId, readerBook.value?.chapterIndex, readerBook.value?.locator]);

    useEffect(
      () =>
          () => progressWriteTimer.value?.cancel(),
      [bookId],
    );

    useEffect(() {
      pageIndex.value = 0;
      pageCount.value = 1;
      requestedPage.value = null;
      return null;
    }, [activeChapterIndex, isPaginated]);

    void scheduleProgressWrite({
      required int index,
      required double chapterRatio,
      String? anchor,
      String? cfi,
    }) {
      progressWriteTimer.value?.cancel();
      progressWriteTimer.value = Timer(
        const Duration(milliseconds: 600),
        () async {
          await ref
              .read(bookRepositoryProvider)
              .updateReadingPosition(
                bookId: bookId,
                chapterIndex: index,
                progress: _overallProgress(index, chapterRatio, totalChapters),
                locator: EpubLocation(
                  chapterIndex: index,
                  scrollRatio: chapterRatio,
                  anchor: anchor,
                  cfi: cfi,
                ).toLocator(),
              );
          if (context.mounted) ref.invalidate(libraryBooksProvider);
        },
      );
    }

    Future<void> selectChapter(
      int index, {
      double scrollPosition = 0,
      String? anchor,
      String? cfi,
    }) async {
      if (totalChapters == 0 || index < 0 || index >= totalChapters) return;
      final revision = runtimeController.beginNavigation();
      progressWriteTimer.value?.cancel();
      chapterIndex.value = index;
      scrollRatio.value = scrollPosition.clamp(0, 1).toDouble();
      activeAnchor.value = anchor;
      activeCfi.value = cfi;
      restoreRevision.value += 1;
      requestedPage.value = null;
      try {
        await ref
            .read(bookRepositoryProvider)
            .updateReadingPosition(
              bookId: bookId,
              chapterIndex: index,
              progress: _overallProgress(
                index,
                scrollRatio.value,
                totalChapters,
              ),
              locator: EpubLocation(
                chapterIndex: index,
                scrollRatio: scrollRatio.value,
                anchor: anchor,
                cfi: cfi,
              ).toLocator(),
            );
        if (runtimeController.isCurrent(revision)) {
          ref.invalidate(libraryBooksProvider);
          runtimeController.completeNavigation(revision);
        }
      } catch (error) {
        runtimeController.reportFailure(revision, error);
      }
    }

    Future<void> toggleBookmark() async {
      final repository = ref.read(bookmarkRepositoryProvider);
      final existing = bookmarkItems
          .where(
            (bookmark) => EpubLocation.matchesLocator(
              bookmark.locator,
              currentLocation,
              fallbackChapterIndex: activeChapterIndex,
            ),
          )
          .firstOrNull;
      if (existing != null) {
        await repository.remove(existing.id);
      } else {
        await repository.add(
          bookId: bookId,
          locator: currentLocator,
          chapterTitle: chapterTitle,
        );
      }
      ref.invalidate(bookmarksForBookProvider(bookId));
    }

    Future<void> openBookSettings() async {
      final result = await showDialog<_BookSettingsResult>(
        context: context,
        builder: (context) => _BookReadingSettingsDialog(
          bookId: bookId,
          defaults: readingSettings,
          readingOverride: override,
        ),
      );
      if (result == null || !context.mounted) return;
      final repository = ref.read(settingsRepositoryProvider);
      if (result.bookOverride == null) {
        await repository.clearBookOverride(bookId);
      } else {
        await repository.saveBookOverride(result.bookOverride!);
      }
      ref.invalidate(bookReadingOverrideProvider(bookId));
    }

    Future<void> createAnnotation() async {
      final selection = selectedText.value;
      if (selection == null || selection.href != chapter.value?.href) return;
      final draft = await showDialog<_AnnotationDraft>(
        context: context,
        builder: (context) => _AnnotationDialog(selection: selection),
      );
      if (draft == null || !context.mounted) return;
      await ref
          .read(annotationRepositoryProvider)
          .add(
            bookId: bookId,
            href: selection.href,
            locator: selection.locator,
            selectedText: selection.text,
            color: draft.color,
            note: draft.note,
          );
      selectedText.value = null;
      ref.invalidate(annotationsForBookProvider(bookId));
    }

    Future<void> openSearch() async {
      final book = readerBook.value;
      final currentManifest = manifest.value;
      if (book == null || currentManifest == null) return;
      final result = await showDialog<EpubSearchResult>(
        context: context,
        builder: (context) =>
            ReaderSearchDialog(book: book, manifest: currentManifest),
      );
      if (result == null || !context.mounted) return;
      await selectChapter(
        result.chapterIndex,
        scrollPosition: result.chapterRatio,
      );
    }

    Future<void> selectBookmark(Bookmark bookmark) {
      final location = EpubLocation.fromLocator(
        bookmark.locator,
        fallbackChapterIndex: activeChapterIndex,
      );
      return selectChapter(
        location.chapterIndex,
        scrollPosition: location.scrollRatio,
        anchor: location.anchor,
        cfi: location.cfi,
      );
    }

    Future<void> removeBookmark(Bookmark bookmark) async {
      await ref.read(bookmarkRepositoryProvider).remove(bookmark.id);
      ref.invalidate(bookmarksForBookProvider(bookId));
    }

    Future<void> editBookmark(Bookmark bookmark) async {
      final label = await showDialog<String?>(
        context: context,
        builder: (context) => _BookmarkLabelDialog(bookmark: bookmark),
      );
      if (!context.mounted || label == null) return;
      await ref
          .read(bookmarkRepositoryProvider)
          .updateLabel(bookmark.id, label.trim().isEmpty ? null : label.trim());
      ref.invalidate(bookmarksForBookProvider(bookId));
    }

    void selectAnnotation(ReadingAnnotation annotation) {
      final nextIndex = manifest.value?.spine.indexWhere(
        (item) => item.href == annotation.href,
      );
      if (nextIndex == null || nextIndex < 0) return;
      focusedAnnotationId.value = annotation.id;
      annotationFocusRevision.value += 1;
      unawaited(selectChapter(nextIndex));
    }

    Future<void> editAnnotation(ReadingAnnotation annotation) async {
      final draft = await showDialog<_AnnotationNoteDraft>(
        context: context,
        builder: (context) => _AnnotationNoteDialog(annotation: annotation),
      );
      if (draft == null || !context.mounted) return;
      await ref
          .read(annotationRepositoryProvider)
          .updateNote(annotation.id, draft.note);
      ref.invalidate(annotationsForBookProvider(bookId));
    }

    void navigateToHref(String targetHref) {
      final target = Uri.tryParse(targetHref);
      final targetPath = target == null
          ? targetHref.split('#').first
          : target.path;
      final targetAnchor = target?.fragment.isEmpty ?? true
          ? null
          : target!.fragment;
      final nextIndex = manifest.value?.spine.indexWhere(
        (item) => item.href == targetPath,
      );
      if (nextIndex != null && nextIndex >= 0) {
        unawaited(selectChapter(nextIndex, anchor: targetAnchor));
      }
    }

    void goToPrevious() {
      if (isPaginated && pageIndex.value > 0) {
        requestedPage.value = pageIndex.value - 1;
        return;
      }
      if (activeChapterIndex > 0) {
        unawaited(
          selectChapter(
            activeChapterIndex - 1,
            scrollPosition: isPaginated ? 1 : 0,
          ),
        );
      }
    }

    void goToNext() {
      if (isPaginated && pageIndex.value < pageCount.value - 1) {
        requestedPage.value = pageIndex.value + 1;
        return;
      }
      if (totalChapters > 0 && activeChapterIndex < totalChapters - 1) {
        unawaited(selectChapter(activeChapterIndex + 1));
      }
    }

    void seekToOverallProgress(double value) {
      if (totalChapters == 0) return;
      final target = value.clamp(0, 1).toDouble();
      final scaled = target * totalChapters;
      final targetChapter = target >= 1
          ? totalChapters - 1
          : scaled.floor().clamp(0, totalChapters - 1).toInt();
      final targetRatio = target >= 1 ? 1.0 : scaled - targetChapter;

      if (isPaginated && targetChapter == activeChapterIndex) {
        final targetPage = pageCount.value <= 1
            ? 0
            : (targetRatio * (pageCount.value - 1))
                  .round()
                  .clamp(0, pageCount.value - 1)
                  .toInt();
        requestedPage.value = targetPage;
        return;
      }
      unawaited(selectChapter(targetChapter, scrollPosition: targetRatio));
    }

    void toggleToc() {
      final visible = !tocVisible.value;
      tocVisible.value = visible;
      unawaited(
        ref
            .read(appSettingsProvider.notifier)
            .updateAppearance(appearance.copyWith(readerTocVisible: visible)),
      );
    }

    void toggleSidePanel() {
      final visible = !sidePanelVisible.value;
      sidePanelVisible.value = visible;
      unawaited(
        ref
            .read(appSettingsProvider.notifier)
            .updateAppearance(
              appearance.copyWith(readerSidePanelVisible: visible),
            ),
      );
    }

    void toggleControls() => controlsVisible.value = !controlsVisible.value;

    Widget withReaderShortcuts(Widget child) => Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            _ReaderPreviousIntent(),
        SingleActivator(LogicalKeyboardKey.pageUp): _ReaderPreviousIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _ReaderNextIntent(),
        SingleActivator(LogicalKeyboardKey.pageDown): _ReaderNextIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _ReaderSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyM, control: true):
            _ReaderFocusIntent(),
      },
      child: Actions(
        actions: {
          _ReaderPreviousIntent: CallbackAction<_ReaderPreviousIntent>(
            onInvoke: (_) {
              goToPrevious();
              return null;
            },
          ),
          _ReaderNextIntent: CallbackAction<_ReaderNextIntent>(
            onInvoke: (_) {
              goToNext();
              return null;
            },
          ),
          _ReaderSearchIntent: CallbackAction<_ReaderSearchIntent>(
            onInvoke: (_) {
              unawaited(openSearch());
              return null;
            },
          ),
          _ReaderFocusIntent: CallbackAction<_ReaderFocusIntent>(
            onInvoke: (_) {
              toggleControls();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 840;
        final showToc =
            controlsVisible.value &&
            tocVisible.value &&
            !isMobile &&
            constraints.maxWidth >= tocPanelWidth.value + 160;
        final canShowBothPanels =
            constraints.maxWidth >=
            tocPanelWidth.value + sidePanelWidth.value + 320;
        final showSidePanel =
            controlsVisible.value &&
            sidePanelVisible.value &&
            !isMobile &&
            constraints.maxWidth >= sidePanelWidth.value + 160 &&
            (!showToc || canShowBothPanels);
        final panelTopInset = controlsVisible.value ? 64.0 : 8.0;
        final panelBottomInset = controlsVisible.value ? 72.0 : 8.0;
        Future<void> openMobileToc() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) => _MobileReaderTocDrawer(
            title: title,
            book: readerBook.value,
            chapterCount: totalChapters,
            toc: manifest.value?.toc ?? const [],
            activeChapterIndex: activeChapterIndex,
            onSelected: (item) {
              final target = Uri.tryParse(item.href);
              unawaited(
                selectChapter(
                  item.spineIndex,
                  anchor: target?.fragment.isEmpty ?? true
                      ? null
                      : target!.fragment,
                ),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
        );
        Future<void> openMobileSidePanel() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) => _MobileReaderSideDrawer(
            showBookmarks: showBookmarks.value,
            bookmarks: bookmarkItems,
            annotations: annotations,
            onPanelChanged: (value) => showBookmarks.value = value,
            onSelectBookmark: (bookmark) async {
              await selectBookmark(bookmark);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
            onRemoveBookmark: removeBookmark,
            onEditBookmark: editBookmark,
            onSelectAnnotation: (annotation) {
              selectAnnotation(annotation);
              Navigator.of(sheetContext).pop();
            },
            onEditAnnotation: editAnnotation,
            onRemoveAnnotation: (annotation) async {
              await ref
                  .read(annotationRepositoryProvider)
                  .remove(annotation.id);
              ref.invalidate(annotationsForBookProvider(bookId));
              if (focusedAnnotationId.value == annotation.id) {
                focusedAnnotationId.value = null;
              }
            },
          ),
        );
        final readerBody = Stack(
          children: [
            Positioned.fill(
              child: Material(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: isLoading
                          ? _ReaderCenterTapDetector(
                              key: const Key('reader-content'),
                              onTap: toggleControls,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _ReaderArticle(
                              settings: settings,
                              chapter: chapter.value,
                              error: chapter.error,
                              bookId: readerBook.value == null ? null : bookId,
                              initialScrollRatio: scrollRatio.value,
                              initialAnchor: activeAnchor.value,
                              direction:
                                  manifest.value?.direction ??
                                  ReadingDirection.ltr,
                              requestedPage: requestedPage.value,
                              annotations: annotations,
                              focusedAnnotationId: focusedAnnotationId.value,
                              annotationFocusRevision:
                                  annotationFocusRevision.value,
                              restoreRevision: restoreRevision.value,
                              onNavigateToHref: navigateToHref,
                              onScrollPositionChanged:
                                  (href, ratio, anchor, cfi) {
                                    runtimeController.reportRelocation();
                                    if (href != chapter.value?.href) return;
                                    final clampedRatio = ratio
                                        .clamp(0, 1)
                                        .toDouble();
                                    scrollRatio.value = clampedRatio;
                                    activeAnchor.value = anchor;
                                    activeCfi.value = cfi;
                                    scheduleProgressWrite(
                                      index: activeChapterIndex,
                                      chapterRatio: clampedRatio,
                                      anchor: anchor,
                                      cfi: cfi,
                                    );
                                  },
                              onPaginationChanged: (index, count) {
                                pageIndex.value = index;
                                pageCount.value = count;
                                if (requestedPage.value == index) {
                                  requestedPage.value = null;
                                }
                              },
                              onRequestPrevious: goToPrevious,
                              onRequestNext: goToNext,
                              onTextSelectionChanged: (selection) {
                                if (selection.href == chapter.value?.href) {
                                  selectedText.value = selection;
                                }
                              },
                              onToggleControls: toggleControls,
                            ),
                    ),
                    if (showToc)
                      Positioned(
                        left: 8,
                        top: panelTopInset,
                        bottom: panelBottomInset,
                        width: tocPanelWidth.value + 8,
                        child: ResizablePane(
                          width: tocPanelWidth.value,
                          minWidth: 240,
                          maxWidth: 480,
                          defaultWidth: 280,
                          onWidthChanged: (value) =>
                              tocPanelWidth.value = value,
                          onWidthChangeEnd: (value) => ref
                              .read(appSettingsProvider.notifier)
                              .updateAppearance(
                                appearance.copyWith(readerTocWidth: value),
                              ),
                          child: _ReaderOverlaySurface(
                            child: _ReaderTocPanel(
                              toc: manifest.value?.toc ?? const [],
                              activeChapterIndex: activeChapterIndex,
                              onSelected: (item) {
                                final target = Uri.tryParse(item.href);
                                unawaited(
                                  selectChapter(
                                    item.spineIndex,
                                    anchor: target?.fragment.isEmpty ?? true
                                        ? null
                                        : target!.fragment,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    if (showSidePanel)
                      Positioned(
                        right: 8,
                        top: panelTopInset,
                        bottom: panelBottomInset,
                        width: sidePanelWidth.value + 8,
                        child: ResizablePane(
                          edge: ResizablePaneEdge.leading,
                          width: sidePanelWidth.value,
                          minWidth: 280,
                          maxWidth: 520,
                          defaultWidth: 320,
                          onWidthChanged: (value) =>
                              sidePanelWidth.value = value,
                          onWidthChangeEnd: (value) => ref
                              .read(appSettingsProvider.notifier)
                              .updateAppearance(
                                appearance.copyWith(
                                  readerSidePanelWidth: value,
                                ),
                              ),
                          child: _ReaderOverlaySurface(
                            child: _ReaderSidePanel(
                              showBookmarks: showBookmarks.value,
                              bookmarks: bookmarkItems,
                              annotations: annotations,
                              onPanelChanged: (value) =>
                                  showBookmarks.value = value,
                              onSelectBookmark: selectBookmark,
                              onRemoveBookmark: removeBookmark,
                              onEditBookmark: editBookmark,
                              onSelectAnnotation: selectAnnotation,
                              onEditAnnotation: editAnnotation,
                              onRemoveAnnotation: (annotation) async {
                                await ref
                                    .read(annotationRepositoryProvider)
                                    .remove(annotation.id);
                                ref.invalidate(
                                  annotationsForBookProvider(bookId),
                                );
                                if (focusedAnnotationId.value ==
                                    annotation.id) {
                                  focusedAnnotationId.value = null;
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ReaderChrome(
                visible: controlsVisible.value,
                hiddenOffset: const Offset(0, -1),
                child: _ReaderToolbar(
                  title: title,
                  tocVisible: tocVisible.value,
                  sidePanelVisible: sidePanelVisible.value,
                  mobileReaderControls: isMobile,
                  bookmarked: isBookmarked,
                  canCreateAnnotation:
                      selectedText.value?.href == chapter.value?.href,
                  onExitReader: onExitReader,
                  onToggleToc: isMobile
                      ? () => unawaited(openMobileToc())
                      : toggleToc,
                  onToggleSidePanel: isMobile
                      ? () => unawaited(openMobileSidePanel())
                      : toggleSidePanel,
                  onHideControls: toggleControls,
                  onToggleBookmark: toggleBookmark,
                  onCreateAnnotation: createAnnotation,
                  onOpenBookSettings: openBookSettings,
                  onOpenSearch: openSearch,
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _ReaderChrome(
                visible: controlsVisible.value,
                hiddenOffset: const Offset(0, 1),
                child: _ReaderFooter(
                  chapterIndex: activeChapterIndex,
                  chapterCount: totalChapters,
                  layoutMode: settings.layoutMode,
                  chapterProgress: isPaginated
                      ? (pageCount.value <= 1
                            ? 0.0
                            : pageIndex.value / (pageCount.value - 1))
                      : scrollRatio.value,
                  pageIndex: pageIndex.value,
                  pageCount: pageCount.value,
                  onSeekProgress: seekToOverallProgress,
                  onPrevious:
                      activeChapterIndex > 0 ||
                          (isPaginated && pageIndex.value > 0)
                      ? goToPrevious
                      : null,
                  onNext:
                      totalChapters > 0 &&
                          (activeChapterIndex < totalChapters - 1 ||
                              (isPaginated &&
                                  pageIndex.value < pageCount.value - 1))
                      ? goToNext
                      : null,
                ),
              ),
            ),
          ],
        );
        return withReaderShortcuts(readerBody);
      },
    );
  }
}

class _ReaderToolbar extends StatelessWidget {
  const _ReaderToolbar({
    required this.title,
    required this.tocVisible,
    required this.sidePanelVisible,
    required this.mobileReaderControls,
    required this.bookmarked,
    required this.canCreateAnnotation,
    required this.onToggleToc,
    required this.onToggleSidePanel,
    required this.onExitReader,
    required this.onHideControls,
    required this.onToggleBookmark,
    required this.onCreateAnnotation,
    required this.onOpenBookSettings,
    required this.onOpenSearch,
  });

  final String title;
  final bool tocVisible;
  final bool sidePanelVisible;
  final bool mobileReaderControls;
  final bool bookmarked;
  final bool canCreateAnnotation;
  final VoidCallback onToggleToc;
  final VoidCallback onToggleSidePanel;
  final VoidCallback onExitReader;
  final VoidCallback onHideControls;
  final VoidCallback onToggleBookmark;
  final VoidCallback onCreateAnnotation;
  final VoidCallback onOpenBookSettings;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '返回书库',
              onPressed: onExitReader,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: mobileReaderControls
                  ? '打开目录'
                  : tocVisible
                  ? '隐藏目录'
                  : '显示目录',
              onPressed: onToggleToc,
              key: const Key('reader-toc'),
              icon: Icon(
                mobileReaderControls
                    ? Icons.menu
                    : tocVisible
                    ? Icons.format_list_bulleted
                    : Icons.menu_open,
              ),
            ),
            IconButton(
              tooltip: mobileReaderControls
                  ? '打开书签和笔记'
                  : sidePanelVisible
                  ? '隐藏笔记面板'
                  : '显示笔记面板',
              onPressed: onToggleSidePanel,
              key: const Key('reader-side-panel'),
              icon: const Icon(Icons.sticky_note_2_outlined),
            ),
            if (!mobileReaderControls) const VerticalDivider(width: 20),
            IconButton(
              tooltip: bookmarked ? '移除书签' : '添加书签',
              onPressed: onToggleBookmark,
              key: const Key('reader-bookmark'),
              icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
            ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: canCreateAnnotation ? '高亮或添加笔记' : '请先选择文本',
                onPressed: canCreateAnnotation ? onCreateAnnotation : null,
                icon: const Icon(Icons.highlight_alt_outlined),
              ),
            SizedBox(width: mobileReaderControls ? 4 : 12),
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
            if (!mobileReaderControls)
              IconButton(
                tooltip: '搜索书内内容',
                onPressed: onOpenSearch,
                icon: const Icon(Icons.search),
              ),
            if (!mobileReaderControls) const VerticalDivider(width: 20),
            if (!mobileReaderControls)
              IconButton(
                tooltip: '本书阅读设置',
                onPressed: onOpenBookSettings,
                key: const Key('reader-book-settings'),
                icon: const Icon(Icons.format_size),
              ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: '隐藏阅读控制',
                key: const Key('reader-focus-mode'),
                onPressed: onHideControls,
                icon: const Icon(Icons.center_focus_strong_outlined),
              ),
            if (mobileReaderControls)
              PopupMenuButton<_MobileReaderToolbarAction>(
                key: const Key('reader-mobile-more'),
                tooltip: '更多阅读控制',
                onSelected: (action) => switch (action) {
                  _MobileReaderToolbarAction.search => onOpenSearch(),
                  _MobileReaderToolbarAction.settings => onOpenBookSettings(),
                  _MobileReaderToolbarAction.focus => onHideControls(),
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.search,
                    child: ListTile(
                      leading: Icon(Icons.search),
                      title: Text('搜索书内内容'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.settings,
                    child: ListTile(
                      leading: Icon(Icons.format_size),
                      title: Text('本书阅读设置'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MobileReaderToolbarAction.focus,
                    child: ListTile(
                      leading: Icon(Icons.center_focus_strong_outlined),
                      title: Text('隐藏阅读控制'),
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderTocPanel extends HookWidget {
  const _ReaderTocPanel({
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
    final hasMatches = _hasMatchingItem(toc, query.value);
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
          ..._buildTocItems(toc, activeItemKey, 0, query.value),
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
    List<EpubTocItem> items, [
    GlobalKey? activeItemKey,
    int depth = 0,
    String query = '',
  ]) {
    final normalizedQuery = query.trim().toLowerCase();
    return [
      for (final item in items) ...[
        if (normalizedQuery.isEmpty ||
            item.title.toLowerCase().contains(normalizedQuery))
          _TocListItem(
            key: item.spineIndex == activeChapterIndex && item.children.isEmpty
                ? activeItemKey
                : null,
            title: item.title,
            depth: depth,
            enabled: item.spineIndex >= 0,
            selected: item.spineIndex == activeChapterIndex,
            onTap: item.spineIndex < 0 ? null : () => onSelected(item),
          ),
        ..._buildTocItems(item.children, activeItemKey, depth + 1, query),
      ],
    ];
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
  });

  final String title;
  final int depth;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;

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
          enabled: enabled,
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
        ),
      ),
    );
  }
}

class _MobileReaderTocDrawer extends StatelessWidget {
  const _MobileReaderTocDrawer({
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
    final bookTitle = book?.title ?? title;
    final author = book?.author;
    return _ReaderBottomSheet(
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
          Expanded(
            child: toc.isEmpty
                ? const Center(child: Text('暂无可用目录。'))
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final item in toc)
                        _MobileTocEntry(
                          item: item,
                          activeChapterIndex: activeChapterIndex,
                          onSelected: onSelected,
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
    this.depth = 0,
  });

  final EpubTocItem item;
  final int activeChapterIndex;
  final ValueChanged<EpubTocItem> onSelected;
  final int depth;

  @override
  Widget build(BuildContext context) {
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
    return ExpansionTile(
      key: PageStorageKey('${item.href}-$activeChapterIndex'),
      tilePadding: padding,
      initiallyExpanded: _containsActiveChapter(item),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        for (final child in item.children)
          _MobileTocEntry(
            item: child,
            activeChapterIndex: activeChapterIndex,
            onSelected: onSelected,
            depth: depth + 1,
          ),
      ],
    );
  }

  bool _containsActiveChapter(EpubTocItem entry) =>
      entry.spineIndex == activeChapterIndex ||
      entry.children.any(_containsActiveChapter);
}

class _MobileReaderSideDrawer extends StatelessWidget {
  const _MobileReaderSideDrawer({
    required this.showBookmarks,
    required this.bookmarks,
    required this.annotations,
    required this.onPanelChanged,
    required this.onSelectBookmark,
    required this.onRemoveBookmark,
    required this.onEditBookmark,
    required this.onSelectAnnotation,
    required this.onEditAnnotation,
    required this.onRemoveAnnotation,
  });

  final bool showBookmarks;
  final List<Bookmark> bookmarks;
  final List<ReadingAnnotation> annotations;
  final ValueChanged<bool> onPanelChanged;
  final Future<void> Function(Bookmark bookmark) onSelectBookmark;
  final Future<void> Function(Bookmark bookmark) onRemoveBookmark;
  final Future<void> Function(Bookmark bookmark) onEditBookmark;
  final ValueChanged<ReadingAnnotation> onSelectAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onEditAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onRemoveAnnotation;

  @override
  Widget build(BuildContext context) => _ReaderBottomSheet(
    child: Column(
      children: [
        Padding(
          key: const Key('reader-mobile-side-header'),
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '书签与笔记',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭面板',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _ReaderSidePanel(
            showBookmarks: showBookmarks,
            bookmarks: bookmarks,
            annotations: annotations,
            onPanelChanged: onPanelChanged,
            onSelectBookmark: onSelectBookmark,
            onRemoveBookmark: onRemoveBookmark,
            onEditBookmark: onEditBookmark,
            onSelectAnnotation: onSelectAnnotation,
            onEditAnnotation: onEditAnnotation,
            onRemoveAnnotation: onRemoveAnnotation,
          ),
        ),
      ],
    ),
  );
}

class _ReaderBottomSheet extends StatelessWidget {
  const _ReaderBottomSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .82,
    alignment: Alignment.bottomCenter,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class _ReaderArticle extends StatelessWidget {
  const _ReaderArticle({
    required this.settings,
    required this.chapter,
    required this.error,
    required this.bookId,
    required this.initialScrollRatio,
    required this.initialAnchor,
    required this.direction,
    required this.requestedPage,
    required this.restoreRevision,
    required this.annotations,
    required this.focusedAnnotationId,
    required this.annotationFocusRevision,
    required this.onNavigateToHref,
    required this.onScrollPositionChanged,
    required this.onPaginationChanged,
    required this.onRequestPrevious,
    required this.onRequestNext,
    required this.onTextSelectionChanged,
    required this.onToggleControls,
  });

  final ReadingSettings settings;
  final ReaderChapter? chapter;
  final Object? error;
  final String? bookId;
  final double initialScrollRatio;
  final String? initialAnchor;
  final ReadingDirection direction;
  final int? requestedPage;
  final int restoreRevision;
  final List<ReadingAnnotation> annotations;
  final String? focusedAnnotationId;
  final int annotationFocusRevision;
  final ValueChanged<String> onNavigateToHref;
  final void Function(String href, double ratio, String? anchor, String? cfi)
  onScrollPositionChanged;
  final void Function(int pageIndex, int pageCount) onPaginationChanged;
  final VoidCallback onRequestPrevious;
  final VoidCallback onRequestNext;
  final ValueChanged<ReaderTextSelection> onTextSelectionChanged;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context) {
    if (chapter == null) {
      return _ReaderCenterTapDetector(
        key: const Key('reader-content'),
        onTap: onToggleControls,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error == null ? '正在加载章节…' : '无法加载章节：$error'),
          ),
        ),
      );
    }
    if (bookId != null) {
      return EpubWebView(
        bookId: bookId!,
        href: chapter!.href,
        settings: settings,
        initialScrollRatio: initialScrollRatio,
        initialAnchor: initialAnchor,
        direction: direction,
        requestedPage: requestedPage,
        restoreRevision: restoreRevision,
        annotations: annotations,
        focusedAnnotationId: focusedAnnotationId,
        annotationFocusRevision: annotationFocusRevision,
        onNavigateToHref: onNavigateToHref,
        onScrollPositionChanged: onScrollPositionChanged,
        onPaginationChanged: onPaginationChanged,
        onRequestPrevious: onRequestPrevious,
        onRequestNext: onRequestNext,
        onTextSelectionChanged: onTextSelectionChanged,
        onToggleControls: onToggleControls,
      );
    }
    final blocks = chapter!.blocks;
    final titleBlock = blocks.where((block) => block.isHeading).firstOrNull;
    final bodyBlocks = titleBlock == null
        ? blocks
        : blocks.where((block) => !identical(block, titleBlock)).toList();
    return _ReaderCenterTapDetector(
      onTap: onToggleControls,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              settings.pageMargin,
              36,
              settings.pageMargin,
              48,
            ),
            children: [
              Text(
                '第 ${chapter!.index + 1} 章',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                chapter!.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFamily: settings.font.fontFamily,
                ),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final canUseDoubleColumn =
                      settings.doubleColumn && constraints.maxWidth >= 760;
                  if (!canUseDoubleColumn) {
                    return _ArticleColumn(
                      blocks: bodyBlocks,
                      settings: settings,
                    );
                  }
                  final splitAt = (bodyBlocks.length / 2).ceil();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ArticleColumn(
                          blocks: bodyBlocks.take(splitAt).toList(),
                          settings: settings,
                        ),
                      ),
                      const SizedBox(width: 48),
                      Expanded(
                        child: _ArticleColumn(
                          blocks: bodyBlocks.skip(splitAt).toList(),
                          settings: settings,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderChrome extends StatelessWidget {
  const _ReaderChrome({
    required this.visible,
    required this.hiddenOffset,
    required this.child,
  });

  final bool visible;
  final Offset hiddenOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : hiddenOffset,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: visible ? 1 : 0,
        child: child,
      ),
    ),
  );
}

class _ReaderOverlaySurface extends StatelessWidget {
  const _ReaderOverlaySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 4,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _ReaderCenterTapDetector extends StatelessWidget {
  const _ReaderCenterTapDetector({
    super.key,
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerUp: (event) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final size = box.size;
      final position = event.localPosition;
      final inCenter =
          position.dx >= size.width * .25 &&
          position.dx <= size.width * .75 &&
          position.dy >= size.height * .25 &&
          position.dy <= size.height * .75;
      if (inCenter) onTap();
    },
    child: child,
  );
}

class _ArticleColumn extends StatelessWidget {
  const _ArticleColumn({required this.blocks, required this.settings});

  final List<ReaderChapterBlock> blocks;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: blocks
        .map(
          (block) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              block.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontFamily: settings.font.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
                fontWeight: block.isHeading ? FontWeight.w600 : null,
              ),
            ),
          ),
        )
        .toList(),
  );
}

class _ReaderSidePanel extends StatelessWidget {
  const _ReaderSidePanel({
    required this.showBookmarks,
    required this.bookmarks,
    required this.annotations,
    required this.onPanelChanged,
    required this.onSelectBookmark,
    required this.onRemoveBookmark,
    required this.onEditBookmark,
    required this.onSelectAnnotation,
    required this.onEditAnnotation,
    required this.onRemoveAnnotation,
  });

  final bool showBookmarks;
  final List<Bookmark> bookmarks;
  final List<ReadingAnnotation> annotations;
  final ValueChanged<bool> onPanelChanged;
  final Future<void> Function(Bookmark bookmark) onSelectBookmark;
  final Future<void> Function(Bookmark bookmark) onRemoveBookmark;
  final Future<void> Function(Bookmark bookmark) onEditBookmark;
  final ValueChanged<ReadingAnnotation> onSelectAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onEditAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onRemoveAnnotation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: Text('笔记 ${annotations.length}'),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.bookmark_border),
                label: Text('书签 ${bookmarks.length}'),
              ),
            ],
            selected: {showBookmarks},
            onSelectionChanged: (selection) => onPanelChanged(selection.first),
          ),
          const SizedBox(height: 20),
          if (showBookmarks) ...[
            Text('书签', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (bookmarks.isEmpty)
              const Expanded(child: Center(child: Text('当前书籍还没有书签。')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = bookmarks[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bookmark),
                      title: Text(bookmark.label ?? bookmark.chapterTitle),
                      subtitle: Text(
                        '保存于 ${bookmark.createdAt.hour.toString().padLeft(2, '0')}:${bookmark.createdAt.minute.toString().padLeft(2, '0')}',
                      ),
                      onTap: () => onSelectBookmark(bookmark),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑书签',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => onEditBookmark(bookmark),
                          ),
                          IconButton(
                            tooltip: '删除书签',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onRemoveBookmark(bookmark),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ] else ...[
            Text('笔记与标注', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (annotations.isEmpty)
              const Expanded(child: Center(child: Text('选中文本后可创建高亮和笔记。')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: annotations.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final annotation = annotations[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 8,
                        backgroundColor: _annotationColor(annotation.color),
                      ),
                      title: Text(
                        annotation.selectedText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: annotation.note == null
                          ? const Text('高亮')
                          : Text(annotation.note!, maxLines: 3),
                      onTap: () => onSelectAnnotation(annotation),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑笔记',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => onEditAnnotation(annotation),
                          ),
                          IconButton(
                            tooltip: '删除标注',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onRemoveAnnotation(annotation),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _annotationColor(AnnotationColor color) => switch (color) {
    AnnotationColor.yellow => Colors.amber,
    AnnotationColor.green => Colors.green,
    AnnotationColor.blue => Colors.lightBlue,
    AnnotationColor.pink => Colors.pink,
  };
}

class _BookmarkLabelDialog extends HookWidget {
  const _BookmarkLabelDialog({required this.bookmark});

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: bookmark.label ?? '');
    return AlertDialog(
      title: const Text('编辑书签'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: '书签名称',
            hintText: bookmark.chapterTitle,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _AnnotationDraft {
  const _AnnotationDraft({required this.color, this.note});

  final AnnotationColor color;
  final String? note;
}

class _AnnotationNoteDraft {
  const _AnnotationNoteDraft(this.note);

  final String note;
}

class _AnnotationNoteDialog extends HookWidget {
  const _AnnotationNoteDialog({required this.annotation});

  final ReadingAnnotation annotation;

  @override
  Widget build(BuildContext context) {
    final noteController = useTextEditingController(
      text: annotation.note ?? '',
    );
    return AlertDialog(
      title: const Text('编辑笔记'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              annotation.selectedText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: noteController,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '笔记（留空以移除）',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _AnnotationNoteDraft(noteController.text)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _AnnotationDialog extends HookWidget {
  const _AnnotationDialog({required this.selection});

  final ReaderTextSelection selection;

  @override
  Widget build(BuildContext context) {
    final color = useState(AnnotationColor.yellow);
    final noteController = useTextEditingController();
    return AlertDialog(
      title: const Text('添加高亮与笔记'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selection.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                for (final option in AnnotationColor.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: option.label,
                      child: IconButton(
                        isSelected: color.value == option,
                        onPressed: () => color.value = option,
                        icon: CircleAvatar(
                          radius: 12,
                          backgroundColor: _annotationSwatch(option),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '笔记（可选）',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _AnnotationDraft(color: color.value, note: noteController.text),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }

  Color _annotationSwatch(AnnotationColor color) => switch (color) {
    AnnotationColor.yellow => Colors.amber,
    AnnotationColor.green => Colors.green,
    AnnotationColor.blue => Colors.lightBlue,
    AnnotationColor.pink => Colors.pink,
  };
}

class _ReaderFooter extends StatelessWidget {
  const _ReaderFooter({
    required this.chapterIndex,
    required this.chapterCount,
    required this.layoutMode,
    required this.chapterProgress,
    required this.pageIndex,
    required this.pageCount,
    required this.onSeekProgress,
    required this.onPrevious,
    required this.onNext,
  });

  final int chapterIndex;
  final int chapterCount;
  final ReaderLayoutMode layoutMode;
  final double chapterProgress;
  final int pageIndex;
  final int pageCount;
  final ValueChanged<double> onSeekProgress;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final progress = chapterCount == 0
        ? 0.0
        : (chapterIndex + chapterProgress.clamp(0, 1)) / chapterCount;
    return Material(
      key: const Key('reader-footer'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Row(
          children: [
            IconButton(
              tooltip: layoutMode == ReaderLayoutMode.paginated
                  ? '上一页，或上一章'
                  : '上一章',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReaderProgressSlider(
                progress: progress,
                onChanged: onSeekProgress,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              chapterCount == 0
                  ? '正在读取目录'
                  : layoutMode == ReaderLayoutMode.paginated
                  ? '${(progress * 100).round()}% · 第 ${pageIndex + 1} / $pageCount 页 · 第 ${chapterIndex + 1} / $chapterCount 章'
                  : '${(progress * 100).round()}% · ${chapterIndex + 1} / $chapterCount',
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: layoutMode == ReaderLayoutMode.paginated
                  ? '下一页，或下一章'
                  : '下一章',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderProgressSlider extends StatefulWidget {
  const _ReaderProgressSlider({
    required this.progress,
    required this.onChanged,
  });

  final double progress;
  final ValueChanged<double> onChanged;

  @override
  State<_ReaderProgressSlider> createState() => _ReaderProgressSliderState();
}

class _ReaderProgressSliderState extends State<_ReaderProgressSlider> {
  double? _dragProgress;

  @override
  Widget build(BuildContext context) {
    final value = (_dragProgress ?? widget.progress).clamp(0, 1).toDouble();
    return Slider(
      key: const Key('reader-progress-slider'),
      value: value,
      label: '${(value * 100).round()}%',
      semanticFormatterCallback: (next) => '${(next * 100).round()}%',
      onChanged: (next) => setState(() => _dragProgress = next),
      onChangeEnd: (next) {
        setState(() => _dragProgress = null);
        widget.onChanged(next);
      },
    );
  }
}

class _BookSettingsResult {
  const _BookSettingsResult(this.bookOverride);

  final BookReadingOverride? bookOverride;
}

class _BookReadingSettingsDialog extends HookWidget {
  const _BookReadingSettingsDialog({
    required this.bookId,
    required this.defaults,
    required this.readingOverride,
  });

  final String bookId;
  final ReadingSettings defaults;
  final BookReadingOverride? readingOverride;

  @override
  Widget build(BuildContext context) {
    final useOverride = useState(readingOverride != null);
    final settings = useState(readingOverride?.settings ?? defaults);
    return AlertDialog(
      title: const Text('本书阅读设置'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: useOverride.value,
              onChanged: (value) => useOverride.value = value,
              title: const Text('使用本书独立设置'),
              subtitle: const Text('关闭后，本书将跟随全局阅读设置。'),
            ),
            if (useOverride.value) ...[
              DropdownButtonFormField<FontChoice>(
                initialValue: settings.value.font,
                decoration: const InputDecoration(labelText: '书本字体'),
                items: FontChoice.values
                    .map(
                      (font) => DropdownMenuItem(
                        value: font,
                        child: Text(font.label),
                      ),
                    )
                    .toList(),
                onChanged: (font) {
                  if (font != null) {
                    settings.value = settings.value.copyWith(font: font);
                  }
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<ReaderLayoutMode>(
                segments: [
                  for (final mode in ReaderLayoutMode.values)
                    ButtonSegment(
                      value: mode,
                      icon: Icon(
                        mode == ReaderLayoutMode.scroll
                            ? Icons.swap_vert
                            : Icons.auto_stories_outlined,
                      ),
                      label: Text(mode.label),
                    ),
                ],
                selected: {settings.value.layoutMode},
                onSelectionChanged: (selection) {
                  settings.value = settings.value.copyWith(
                    layoutMode: selection.first,
                  );
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<ReaderPageTransition>(
                segments: [
                  for (final transition in ReaderPageTransition.values)
                    ButtonSegment(
                      value: transition,
                      icon: Icon(switch (transition) {
                        ReaderPageTransition.slide => Icons.swipe,
                        ReaderPageTransition.cover => Icons.layers_outlined,
                        ReaderPageTransition.fade => Icons.opacity,
                        ReaderPageTransition.none =>
                          Icons.do_not_disturb_alt_outlined,
                      }),
                      label: Text(transition.label),
                    ),
                ],
                selected: {settings.value.pageTransition},
                onSelectionChanged: (selection) {
                  settings.value = settings.value.copyWith(
                    pageTransition: selection.first,
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('字号')),
                  Expanded(
                    child: Slider(
                      value: settings.value.fontSize,
                      min: 14,
                      max: 28,
                      divisions: 14,
                      label: settings.value.fontSize.round().toString(),
                      onChanged: (value) => settings.value = settings.value
                          .copyWith(fontSize: value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('行高')),
                  Expanded(
                    child: Slider(
                      value: settings.value.lineHeight,
                      min: 1.4,
                      max: 2.2,
                      divisions: 8,
                      label: settings.value.lineHeight.toStringAsFixed(1),
                      onChanged: (value) => settings.value = settings.value
                          .copyWith(lineHeight: value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('页边距')),
                  Expanded(
                    child: Slider(
                      key: const Key('book-reading-margin'),
                      value: settings.value.pageMargin,
                      min: 16,
                      max: 64,
                      divisions: 12,
                      label: settings.value.pageMargin.round().toString(),
                      onChanged: (value) => settings.value = settings.value
                          .copyWith(pageMargin: value),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                key: const Key('book-reading-double-column'),
                contentPadding: EdgeInsets.zero,
                value: settings.value.doubleColumn,
                onChanged: settings.value.layoutMode == ReaderLayoutMode.scroll
                    ? (value) => settings.value = settings.value.copyWith(
                        doubleColumn: value,
                      )
                    : null,
                title: const Text('双栏阅读'),
                subtitle: Text(
                  settings.value.layoutMode == ReaderLayoutMode.scroll
                      ? '宽屏时显示双栏排版。'
                      : '分页模式固定使用单栏排版。',
                ),
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
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _BookSettingsResult(
              useOverride.value
                  ? BookReadingOverride(
                      bookId: bookId,
                      settings: settings.value,
                    )
                  : null,
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
