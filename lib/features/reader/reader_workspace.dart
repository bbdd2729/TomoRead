import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/appearance.dart';
import '../../app/providers.dart';
import '../../data/services/content_chunk_service.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/content_chunk.dart';
import '../../domain/models/embedding_models.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/document_locator.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/epub_section_progress.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reader_theme.dart';
import '../../domain/models/reading_activity.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_context.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/reader_commands.dart';
import '../../domain/models/text_coloring.dart';
import '../../domain/models/tts.dart';
import '../../domain/models/visual_artifact.dart';
import '../../shared/widgets/resizable_pane.dart';
import 'reader_command_controller.dart';
import 'reader_command_shortcuts.dart';
import 'reader_chrome.dart';
import 'reader_chrome_widgets.dart';
import 'reader_article.dart';
import 'reader_annotation_dialogs.dart';
import 'reader_drafts.dart';
import 'reader_progress_coordinator.dart';
import 'reader_reading_settings_dialog.dart';
import 'reader_selection_menu.dart';
import 'reader_side_panel.dart';
import 'reader_top_bar.dart';
import 'reader_toc_drawer.dart';
import 'reader_toc_panel.dart';
import 'reader_navigation_command.dart';
import 'reader_runtime_controller.dart';
import 'reader_theme_controller.dart';
import 'reader_theme_data.dart';
import 'content_search_dialog.dart';
import 'pomodoro_controller.dart';
import 'pomodoro_widgets.dart';
import 'text_coloring_controller.dart';
import 'text_coloring_widgets.dart';
import 'tts_controller.dart';
import '../chat/chat_controller.dart';
import '../assistant/content_index_controller.dart';
import '../notes/notes_providers.dart';
import '../visualization/reader_visualization_dialog.dart';

void _noopReaderAction() {}

class ReaderWorkspace extends ConsumerWidget {
  const ReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
    required this.readingSettings,
    this.onExitReader = _noopReaderAction,
    this.onOpenChat = _noopReaderAction,
    this.initialControlsVisible = false,
  });

  final String bookId;
  final String title;
  final ReadingSettings readingSettings;
  final VoidCallback onExitReader;
  final VoidCallback onOpenChat;
  final bool initialControlsVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(bookReadingOverrideProvider(bookId)).value;
    final customThemes =
        ref.watch(customReaderThemesProvider).value ??
        const <CustomReaderTheme>[];
    final settings = override?.settings ?? readingSettings;
    return Theme(
      data: ReaderThemeData.build(Theme.of(context), settings, customThemes),
      child: _ReaderWorkspaceContent(
        bookId: bookId,
        title: title,
        readingSettings: readingSettings,
        onExitReader: onExitReader,
        onOpenChat: onOpenChat,
        initialControlsVisible: initialControlsVisible,
      ),
    );
  }
}

class _ReaderWorkspaceContent extends HookConsumerWidget {
  const _ReaderWorkspaceContent({
    required this.bookId,
    required this.title,
    required this.readingSettings,
    required this.onExitReader,
    required this.onOpenChat,
    required this.initialControlsVisible,
  });

  final String bookId;
  final String title;
  final ReadingSettings readingSettings;
  final VoidCallback onExitReader;
  final VoidCallback onOpenChat;
  final bool initialControlsVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingOverride = ref.watch(bookReadingOverrideProvider(bookId));
    final textColoringOverride = ref.watch(
      bookTextColoringOverrideProvider(bookId),
    );
    final textColoringState = ref.watch(resolvedTextColoringProvider(bookId));
    final readerCommandState = ref.watch(readerCommandSettingsProvider);
    final defaultReaderCommands = useMemoized(ReaderCommandSettings.defaults);
    final readerCommands = readerCommandState.value ?? defaultReaderCommands;
    // Keep the auto-dispose runtime controller alive for the lifetime of the
    // reader. WebView callbacks can arrive after a navigation frame, so a
    // notifier obtained only with ref.read may otherwise be disposed between
    // relocate events.
    final runtimeState = ref.watch(readerRuntimeControllerProvider);
    final runtimeController = ref.read(
      readerRuntimeControllerProvider.notifier,
    );
    final activityTracker = ref.read(readingActivityTrackerProvider);
    // Keep an app-scoped notifier reference for delayed writes. During effect
    // cleanup the widget's `ref` is already unsafe to read.
    final libraryBooksController = ref.read(libraryBooksProvider.notifier);
    final progressCoordinator = useMemoized(
      () => ReaderProgressCoordinator(
        report: (pending) => libraryBooksController.reportReadingPosition(
          bookId: bookId,
          chapterIndex: pending.chapterIndex,
          progress: pending.progress,
          locator: pending.locator,
        ),
        persist: (pending) => libraryBooksController.updateReadingPosition(
          bookId: bookId,
          chapterIndex: pending.chapterIndex,
          progress: pending.progress,
          locator: pending.locator,
        ),
      ),
      [bookId],
    );
    useEffect(() => progressCoordinator.dispose, [progressCoordinator]);
    final lifecycleState = useAppLifecycleState();
    final pomodoro = ref.watch(pomodoroControllerProvider).value;
    final pomodoroBreakActive =
        pomodoro?.isBreak == true && pomodoro?.isRunning == true;
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    final readerBook = ref.watch(readerBookProvider(bookId));
    final manifest = ref.watch(readerManifestProvider(bookId));
    final contentIndexState = ref.watch(contentIndexStateProvider(bookId));
    final ttsController = useMemoized(
      () => TtsPlaybackController(
        engine: ref.read(ttsEngineProvider),
        queue: ref.read(ttsQueueServiceProvider),
        store: ref.read(ttsRepositoryProvider),
        wakeLock: ref.read(ttsWakeLockProvider),
      ),
      [bookId],
    );
    useListenable(ttsController);
    final ttsState = ttsController.state;
    final sectionProgressState = ref.watch(epubSectionProgressProvider(bookId));
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
    final chapterProgressMeasured = useState(false);
    final activeAnchor = useState<String?>(null);
    final activeCfi = useState<String?>(null);
    final restoreRevision = useState(0);
    final pageIndex = useState(0);
    final pageCount = useState(1);
    final navigationCommand = useState<ReaderNavigationCommand?>(null);
    final autoScrollActive = useState(false);
    final navigationSequence = useRef(0);
    final navigationGate = useRef(ReaderNavigationGate());
    final focusedAnnotationId = useState<String?>(null);
    final annotationFocusRevision = useState(0);
    final selectedText = useState<ReaderTextSelection?>(null);
    final selectionMenuVisible = useRef(false);
    final searchQuery = useState<String?>(null);
    final override = readingOverride.value;
    final bookmarkItems = bookmarks.value ?? const <Bookmark>[];
    final annotations = annotationsState.value ?? const <ReadingAnnotation>[];
    final settings = override?.settings ?? readingSettings;
    ref.watch(readingFontReadyProvider(settings.font));
    final textColoring =
        textColoringState.value ?? ResolvedTextColoring.disabled();
    final isPaginated = settings.layoutMode == ReaderLayoutMode.paginated;
    final totalChapters = manifest.value?.spine.length ?? 0;
    final sectionProgress =
        sectionProgressState.value ?? EpubSectionProgress.even(totalChapters);
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
    // Foliate reports this value for every relocate event on both desktop and
    // Android. Use it as the reader-facing progress source, just as ReadAny
    // does, instead of coupling visible progress to optional text offsets.
    final chapterProgress = scrollRatio.value.clamp(0, 1).toDouble();
    final chapterTitle =
        chapter.value?.title ?? '第 ${activeChapterIndex + 1} 章';
    final isLoading =
        readingOverride.isLoading ||
        bookmarks.isLoading ||
        chapter.isLoading ||
        runtimeState.phase == ReaderRuntimePhase.navigating;
    final isBookmarked = bookmarkItems.any(
      (bookmark) => EpubLocation.matchesLocator(
        bookmark.locator,
        currentLocation,
        fallbackChapterIndex: activeChapterIndex,
      ),
    );

    useEffect(() => ttsController.dispose, [ttsController]);

    useEffect(() {
      tocPanelWidth.value = appearance.readerTocWidth;
      sidePanelWidth.value = appearance.readerSidePanelWidth;
      return null;
    }, [appearance.readerTocWidth, appearance.readerSidePanelWidth]);

    useEffect(
      () {
        final book = readerBook.value;
        final bookManifest = manifest.value;
        final index = contentIndexState.value;
        if (book == null ||
            bookManifest == null ||
            contentIndexState.isLoading) {
          return null;
        }
        final needsRebuild =
            index == null ||
            index.status == ContentIndexStatus.failed ||
            index.contentHash != book.fileHash ||
            index.indexVersion != ContentChunkService.indexVersion;
        if (needsRebuild && index?.status != ContentIndexStatus.indexing) {
          unawaited(
            ref
                .read(contentIndexControllerProvider)
                .rebuildEpub(book: book, manifest: bookManifest),
          );
        }
        return null;
      },
      [
        bookId,
        readerBook.value?.fileHash,
        manifest.value?.chapterCount,
        contentIndexState.isLoading,
        contentIndexState.value?.status,
        contentIndexState.value?.contentHash,
      ],
    );

    useEffect(
      () {
        final book = readerBook.value;
        if (book == null ||
            contentIndexState.value?.status != ContentIndexStatus.ready) {
          return null;
        }
        unawaited(
          ttsController.prepare(
            bookId: bookId,
            format: book.format,
            chapterIndex: activeChapterIndex,
            currentLocator: currentLocator,
          ),
        );
        return null;
      },
      [
        ttsController,
        readerBook.value?.fileHash,
        contentIndexState.value?.status,
        activeChapterIndex,
      ],
    );

    useEffect(() {
      final savedIndex = readerBook.value?.chapterIndex;
      if (savedIndex != null) {
        final savedLocator = readerBook.value?.locator;
        final documentLocator = EpubDocumentLocator.tryParse(
          savedLocator,
          fallbackChapterIndex: savedIndex,
        );
        final location =
            documentLocator?.location ??
            EpubLocation(chapterIndex: savedIndex, scrollRatio: 0);
        if (savedLocator != null &&
            savedLocator.isNotEmpty &&
            documentLocator == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('无法恢复到上次的精确位置，已打开保存的章节。')),
            );
          });
        }
        chapterIndex.value = location.chapterIndex;
        scrollRatio.value = location.scrollRatio;
        chapterProgressMeasured.value = false;
        activeAnchor.value = location.anchor;
        activeCfi.value = location.cfi;
        restoreRevision.value += 1;
      }
      return null;
    }, [bookId, readerBook.value?.chapterIndex, readerBook.value?.locator]);

    useEffect(() {
      final book = readerBook.value;
      if (book == null) return null;
      final savedLocation = EpubLocation.fromLocator(
        book.locator,
        fallbackChapterIndex: book.chapterIndex,
      );
      // Opening a book is itself a reading event. Persisting the current
      // locator makes a first-page book eligible for "continue reading" and
      // moves it to the recent-reading position before the first relocation
      // callback arrives from the WebView. Deferred out of the build phase so
      // the provider can be updated after the widget tree is done building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        unawaited(
          ref
              .read(libraryBooksProvider.notifier)
              .updateReadingPosition(
                bookId: bookId,
                chapterIndex: savedLocation.chapterIndex,
                progress: book.progress,
                locator: book.locator ?? savedLocation.toLocator(),
              ),
        );
      });
      activityTracker.open(
        ReaderIdentity(bookId: bookId, format: ReaderFormat.epub),
        ReaderPosition(progress: book.progress, locator: book.locator),
      );
      return () => unawaited(activityTracker.close());
    }, [bookId, readerBook.value?.id]);

    useEffect(() {
      activityTracker.setForeground(
        (lifecycleState == null ||
                lifecycleState == AppLifecycleState.resumed) &&
            !pomodoroBreakActive,
      );
      if ((lifecycleState != null &&
              lifecycleState != AppLifecycleState.resumed) ||
          pomodoroBreakActive) {
        if (autoScrollActive.value) {
          autoScrollActive.value = false;
          navigationCommand.value = ReaderNavigationCommand.stopAutoScroll(
            id: ++navigationSequence.value,
          );
        }
        if (ttsState.status == TtsPlaybackStatus.playing) {
          unawaited(ttsController.pause());
        }
      }
      return null;
    }, [lifecycleState, pomodoroBreakActive, ttsState.status, ttsController]);

    useEffect(() {
      // A new book or reader-mode switch has no valid runtime page position.
      pageIndex.value = 0;
      pageCount.value = 1;
      chapterProgressMeasured.value = false;
      if (isPaginated && autoScrollActive.value) {
        autoScrollActive.value = false;
        navigationCommand.value = ReaderNavigationCommand.stopAutoScroll(
          id: ++navigationSequence.value,
        );
      }
      return null;
    }, [bookId, activeChapterIndex, isPaginated]);

    useEffect(() {
      // Android can pause or kill the activity without waiting for the reader
      // route to dispose. Flush the latest stable locator when backgrounding,
      // rather than relying on the normal debounce or an eventual exit tap.
      if (lifecycleState != null &&
          lifecycleState != AppLifecycleState.resumed) {
        unawaited(progressCoordinator.flush());
      }
      return null;
    }, [lifecycleState]);

    void stopAutoScroll() {
      if (!autoScrollActive.value) return;
      autoScrollActive.value = false;
      navigationCommand.value = ReaderNavigationCommand.stopAutoScroll(
        id: ++navigationSequence.value,
      );
    }

    void scheduleProgressWrite({
      required int index,
      required double chapterRatio,
      String? anchor,
      String? cfi,
    }) {
      final pending = PendingReaderProgress(
        chapterIndex: index,
        progress: sectionProgress.overallProgress(index, chapterRatio),
        locator: EpubLocation(
          chapterIndex: index,
          scrollRatio: chapterRatio,
          anchor: anchor,
          cfi: cfi,
        ).toLocator(),
      );
      progressCoordinator.capture(pending);
    }

    Future<void> selectChapter(
      int index, {
      double scrollPosition = 0,
      String? anchor,
      String? cfi,
    }) async {
      if (autoScrollActive.value) {
        autoScrollActive.value = false;
        navigationCommand.value = ReaderNavigationCommand.stopAutoScroll(
          id: ++navigationSequence.value,
        );
      }
      if (totalChapters == 0 || index < 0 || index >= totalChapters) return;
      final target = manifest.value?.spine[index];
      if (target == null) return;
      await ttsController.stop();
      unawaited(progressCoordinator.flush());
      final commandId = ++navigationSequence.value;
      if (!navigationGate.value.tryStart(commandId)) return;
      navigationCommand.value = ReaderNavigationCommand.goToLocation(
        id: commandId,
        href: target.href,
        ratio: scrollPosition,
        anchor: anchor,
        cfi: cfi,
      );
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
      stopAutoScroll();
      final result = await showDialog<BookSettingsResult>(
        context: context,
        builder: (context) => BookReadingSettingsDialog(
          bookId: bookId,
          defaults: readingSettings,
          readingOverride: override,
          textColoringSettings: textColoring.settings,
          textColoringOverride: textColoringOverride.value,
        ),
      );
      if (result == null || !context.mounted) return;
      final repository = ref.read(settingsRepositoryProvider);
      if (result.bookOverride == null) {
        await repository.clearBookOverride(bookId);
      } else {
        await repository.saveBookOverride(result.bookOverride!);
      }
      await ref
          .read(textColoringControllerProvider)
          .saveBookOverride(bookId, result.textColoringOverride);
      ref.invalidate(bookReadingOverrideProvider(bookId));
    }

    Future<void> addTextColorTerm(ReaderTextSelection selection) async {
      final draft = await showDialog<TextColorTermDraft>(
        context: context,
        builder: (context) => TextColorTermChoiceDialog(
          text: selection.text,
          settings: textColoring.settings,
        ),
      );
      if (draft == null || !context.mounted) return;
      try {
        await ref
            .read(textColoringControllerProvider)
            .assignTerm(
              term: selection.text,
              tone: draft.tone,
              bookId: draft.global ? null : bookId,
            );
        if (selectedText.value?.locator == selection.locator) {
          selectedText.value = null;
        }
      } on TextColoringException catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }

    Future<void> saveAnnotation(
      ReaderTextSelection selection,
      AnnotationColor color, {
      String? note,
      AnnotationRenderStyle renderStyle = AnnotationRenderStyle.highlight,
    }) async {
      final normalizedNote = note?.trim();
      final selectionChapterIndex = manifest.value == null
          ? null
          : epubSpineIndexForHref(manifest.value!, selection.href);
      await ref
          .read(annotationControllerProvider)
          .add(
            bookId: bookId,
            href: selection.href,
            locator: selection.locator,
            selectedText: selection.text,
            color: color,
            renderStyle: renderStyle,
            note: normalizedNote?.isEmpty ?? true ? null : normalizedNote,
            chapterIndex: selectionChapterIndex ?? activeChapterIndex,
            chapterTitle: chapterTitle,
          );
      if (selectedText.value?.locator == selection.locator) {
        selectedText.value = null;
      }
    }

    void openAiWithSelection(ReaderTextSelection selection, String prompt) {
      ref
          .read(pendingChatDraftProvider.notifier)
          .set(
            PendingChatDraft(
              attachment: ChatContextAttachment(
                bookId: bookId,
                bookTitle: readerBook.value?.title ?? title,
                href: selection.href,
                locator: selection.locator,
                chapterIndex: activeChapterIndex,
                chapterTitle: chapterTitle,
                quote: selection.text,
              ),
              prompt: prompt,
            ),
          );
      onOpenChat();
    }

    Future<void> openReadingAssistant() async {
      stopAutoScroll();
      final actions = ReadingAssistantAction.values
          .where((action) => action != ReadingAssistantAction.explainSelection)
          .toList();
      final action = await showDialog<ReadingAssistantAction>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('阅读助手'),
          children: [
            for (final action in actions)
              ListTile(
                leading: Icon(switch (action) {
                  ReadingAssistantAction.explainSelection =>
                    Icons.lightbulb_outline,
                  ReadingAssistantAction.summarizeChapter =>
                    Icons.summarize_outlined,
                  ReadingAssistantAction.generateQuestions =>
                    Icons.quiz_outlined,
                  ReadingAssistantAction.extractPeopleAndTerms =>
                    Icons.people_outline,
                  ReadingAssistantAction.buildTimeline => Icons.timeline,
                }),
                title: Text(action.label),
                onTap: () => Navigator.pop(dialogContext, action),
              ),
          ],
        ),
      );
      if (action == null || !context.mounted) return;
      final bundle = await ref
          .read(readingContextAssemblerProvider)
          .assemble(
            bookId: bookId,
            currentChapterIndex: activeChapterIndex,
            includeCurrentChapter: true,
            allowFutureChapters: false,
          );
      if (bundle.segments.isEmpty || !context.mounted) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('当前章节索引尚未就绪，请稍后重试。')));
        }
        return;
      }
      final first = bundle.segments.first;
      ref
          .read(pendingChatDraftProvider.notifier)
          .set(
            PendingChatDraft(
              attachment: ChatContextAttachment(
                bookId: bookId,
                bookTitle: readerBook.value?.title ?? title,
                href: first.href,
                locator: first.locator,
                chapterIndex: first.chapterIndex,
                chapterTitle: first.chapterTitle,
                quote: bundle.segments
                    .map(
                      (segment) =>
                          '[${segment.chapterTitle} · ${segment.locator}]\n${segment.text}',
                    )
                    .join('\n\n'),
              ),
              prompt:
                  '${action.prompt}\n\n仅使用当前阅读进度及之前的内容，避免剧透。'
                  '请使用书内搜索工具核对书内事实并附上可点击引用。'
                  '\n上下文校验：${bundle.contextHash}',
            ),
          );
      onOpenChat();
    }

    Future<void> navigateToArtifactCitation(ArtifactCitation citation) async {
      final currentManifest = manifest.value;
      final hrefIndex = currentManifest == null
          ? null
          : epubSpineIndexForHref(currentManifest, citation.href);
      final nextIndex = hrefIndex ?? citation.chapterIndex;
      final ratio = citation.locator.startsWith('ratio:')
          ? double.tryParse(citation.locator.substring(6)) ?? 0.0
          : 0.0;
      await selectChapter(
        nextIndex,
        scrollPosition: ratio.clamp(0, 1).toDouble(),
      );
    }

    Future<void> openVisualization() async {
      stopAutoScroll();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ReaderVisualizationDialog(
          bookId: bookId,
          bookTitle: readerBook.value?.title ?? title,
          currentChapterIndex: activeChapterIndex,
          onOpenCitation: (citation) {
            Navigator.pop(dialogContext);
            unawaited(navigateToArtifactCitation(citation));
          },
        ),
      );
    }

    Future<void> createAnnotation([ReaderTextSelection? source]) async {
      stopAutoScroll();
      final selection = source ?? selectedText.value;
      if (selection == null) return;
      final draft = await showDialog<AnnotationDraft>(
        context: context,
        builder: (context) => AnnotationDialog(selection: selection),
      );
      if (draft == null || !context.mounted) return;
      await saveAnnotation(selection, draft.color, note: draft.note);
    }

    Future<void> openSelectionContextMenu(
      ReaderSelectionContextMenu menu,
    ) async {
      // Android WebView can dispatch more than one context-menu event for a
      // single long-press. A popup route is modal, so only the first event
      // should be allowed to create it.
      if (selectionMenuVisible.value) return;
      selectionMenuVisible.value = true;
      stopAutoScroll();
      selectedText.value = menu.selection;
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      final size = overlay?.size ?? MediaQuery.sizeOf(context);
      final localPosition =
          overlay?.globalToLocal(Offset(menu.x, menu.y)) ??
          Offset(menu.x, menu.y);
      final x = localPosition.dx.clamp(8, size.width - 8).toDouble();
      final y = localPosition.dy.clamp(8, size.height - 8).toDouble();
      final menuPosition = RelativeRect.fromLTRB(
        x,
        y,
        size.width - x,
        size.height - y,
      );
      try {
        final action = await showMenu<ReaderSelectionContextAction>(
          context: context,
          position: menuPosition,
          items: const [
            PopupMenuItem(
              value: ReaderSelectionContextAction.highlight,
              child: ReaderSelectionActionMenuItem(
                icon: Icons.highlight_outlined,
                label: '高亮',
                hasSubmenu: true,
              ),
            ),
            PopupMenuItem(
              value: ReaderSelectionContextAction.underline,
              child: ReaderSelectionActionMenuItem(
                icon: Icons.format_underlined,
                label: '划线',
                hasSubmenu: true,
              ),
            ),
            PopupMenuItem(
              value: ReaderSelectionContextAction.note,
              child: ReaderSelectionActionMenuItem(
                icon: Icons.sticky_note_2_outlined,
                label: '笔记',
              ),
            ),
            PopupMenuItem(
              value: ReaderSelectionContextAction.textColor,
              child: ReaderSelectionActionMenuItem(
                icon: Icons.format_color_text_outlined,
                label: '文字颜色',
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: ReaderSelectionContextAction.ai,
              child: ReaderSelectionActionMenuItem(
                icon: Icons.auto_awesome_outlined,
                label: 'AI 助手',
                hasSubmenu: true,
              ),
            ),
          ],
        );
        if (action == null || !context.mounted) return;
        switch (action) {
          case ReaderSelectionContextAction.highlight:
            final highlightColor = await showMenu<AnnotationColor>(
              context: context,
              position: menuPosition,
              items: const [
                PopupMenuItem(
                  value: AnnotationColor.yellow,
                  child: ReaderSelectionContextMenuItem(
                    color: AnnotationColor.yellow,
                  ),
                ),
                PopupMenuItem(
                  value: AnnotationColor.green,
                  child: ReaderSelectionContextMenuItem(
                    color: AnnotationColor.green,
                  ),
                ),
                PopupMenuItem(
                  value: AnnotationColor.blue,
                  child: ReaderSelectionContextMenuItem(
                    color: AnnotationColor.blue,
                  ),
                ),
                PopupMenuItem(
                  value: AnnotationColor.pink,
                  child: ReaderSelectionContextMenuItem(
                    color: AnnotationColor.pink,
                  ),
                ),
              ],
            );
            if (highlightColor != null && context.mounted) {
              await saveAnnotation(menu.selection, highlightColor);
            }
          case ReaderSelectionContextAction.underline:
            final color = await showDialog<AnnotationColor>(
              context: context,
              builder: (context) => const ReaderUnderlineColorDialog(),
            );
            if (color != null && context.mounted) {
              await saveAnnotation(
                menu.selection,
                color,
                renderStyle: AnnotationRenderStyle.underline,
              );
            }
          case ReaderSelectionContextAction.note:
            await createAnnotation(menu.selection);
          case ReaderSelectionContextAction.textColor:
            await addTextColorTerm(menu.selection);
          case ReaderSelectionContextAction.ai:
            final aiAction = await showMenu<ReaderSelectionAiAction>(
              context: context,
              position: menuPosition,
              items: const [
                PopupMenuItem(
                  value: ReaderSelectionAiAction.ask,
                  child: ReaderSelectionActionMenuItem(
                    icon: Icons.auto_awesome_outlined,
                    label: '询问 AI',
                  ),
                ),
                PopupMenuItem(
                  value: ReaderSelectionAiAction.explain,
                  child: ReaderSelectionActionMenuItem(
                    icon: Icons.lightbulb_outline,
                    label: '解释这段',
                  ),
                ),
                PopupMenuItem(
                  value: ReaderSelectionAiAction.summarize,
                  child: ReaderSelectionActionMenuItem(
                    icon: Icons.summarize_outlined,
                    label: '总结这段',
                  ),
                ),
              ],
            );
            if (aiAction == null || !context.mounted) return;
            switch (aiAction) {
              case ReaderSelectionAiAction.ask:
                openAiWithSelection(menu.selection, '关于这段文字，我想问：');
              case ReaderSelectionAiAction.explain:
                openAiWithSelection(menu.selection, '请解释这段文字的含义和关键概念。');
              case ReaderSelectionAiAction.summarize:
                openAiWithSelection(menu.selection, '请简洁总结这段文字的核心观点。');
            }
        }
      } finally {
        selectionMenuVisible.value = false;
      }
    }

    Future<void> openSearch() async {
      stopAutoScroll();
      final result = await showDialog<HybridSearchResult>(
        context: context,
        builder: (context) => ContentSearchDialog(
          bookId: bookId,
          maxChapterIndex: activeChapterIndex,
          maxRawOffset: chapter.value == null
              ? null
              : (chapter.value!.plainText.length * scrollRatio.value).round(),
        ),
      );
      if (result == null || !context.mounted) return;
      searchQuery.value = null;
      final ratio = result.locator.startsWith('ratio:')
          ? double.tryParse(result.locator.substring('ratio:'.length)) ?? 0
          : 0.0;
      await selectChapter(
        result.chapterIndex,
        scrollPosition: ratio.clamp(0, 1).toDouble(),
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
      stopAutoScroll();
      final label = await showDialog<String?>(
        context: context,
        builder: (context) => BookmarkLabelDialog(bookmark: bookmark),
      );
      if (!context.mounted || label == null) return;
      await ref
          .read(bookmarkRepositoryProvider)
          .updateLabel(bookmark.id, label.trim().isEmpty ? null : label.trim());
      ref.invalidate(bookmarksForBookProvider(bookId));
    }

    void selectAnnotation(ReadingAnnotation annotation) {
      final currentManifest = manifest.value;
      if (currentManifest == null) return;
      final nextIndex = epubSpineIndexForHref(currentManifest, annotation.href);
      if (nextIndex == null) return;
      focusedAnnotationId.value = annotation.id;
      annotationFocusRevision.value += 1;
      unawaited(
        selectChapter(
          nextIndex,
          cfi: annotation.locator.startsWith('cfi:')
              ? annotation.locator.substring(4)
              : null,
        ),
      );
    }

    Future<void> editAnnotation(ReadingAnnotation annotation) async {
      stopAutoScroll();
      final draft = await showDialog<AnnotationNoteDraft>(
        context: context,
        builder: (context) => AnnotationNoteDialog(annotation: annotation),
      );
      if (draft == null || !context.mounted) return;
      await ref
          .read(annotationControllerProvider)
          .updateNote(annotation.id, draft.note);
    }

    void navigateToHref(String targetHref) {
      final target = Uri.tryParse(targetHref);
      final targetPath = target == null
          ? targetHref.split('#').first
          : target.path;
      final targetAnchor = target?.fragment.isEmpty ?? true
          ? null
          : target!.fragment;
      final currentManifest = manifest.value;
      final nextIndex = currentManifest == null
          ? null
          : epubSpineIndexForHref(currentManifest, targetPath);
      if (nextIndex != null) {
        unawaited(selectChapter(nextIndex, anchor: targetAnchor));
      }
    }

    void goToPrevious() {
      autoScrollActive.value = false;
      final commandId = ++navigationSequence.value;
      if (!navigationGate.value.tryStart(commandId)) return;
      navigationCommand.value = ReaderNavigationCommand.previousPage(
        id: commandId,
      );
    }

    void goToNext() {
      autoScrollActive.value = false;
      final commandId = ++navigationSequence.value;
      if (!navigationGate.value.tryStart(commandId)) return;
      navigationCommand.value = ReaderNavigationCommand.nextPage(id: commandId);
    }

    void seekToChapterProgress(double value) {
      autoScrollActive.value = false;
      if (totalChapters == 0) return;
      final targetItem = manifest.value?.spine[activeChapterIndex];
      if (targetItem == null) return;
      // Keep the slider at the requested position until the runtime reports
      // its measured location after layout and scrolling complete.
      final targetRatio = value.clamp(0, 1).toDouble();
      scrollRatio.value = targetRatio;
      activeAnchor.value = null;
      activeCfi.value = null;
      navigationCommand.value = ReaderNavigationCommand.goToLocation(
        id: ++navigationSequence.value,
        href: targetItem.href,
        ratio: targetRatio,
      );
    }

    void toggleToc() {
      if (autoScrollActive.value) {
        navigationCommand.value = ReaderNavigationCommand.stopAutoScroll(
          id: ++navigationSequence.value,
        );
        autoScrollActive.value = false;
      }
      final visible = !tocVisible.value;
      tocVisible.value = visible;
      unawaited(
        ref
            .read(appSettingsProvider.notifier)
            .updateAppearance(appearance.copyWith(readerTocVisible: visible)),
      );
    }

    void toggleSidePanel() {
      if (autoScrollActive.value) {
        navigationCommand.value = ReaderNavigationCommand.stopAutoScroll(
          id: ++navigationSequence.value,
        );
        autoScrollActive.value = false;
      }
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

    void scrollByCommand(double amount) {
      autoScrollActive.value = false;
      navigationCommand.value = ReaderNavigationCommand.scrollBy(
        id: ++navigationSequence.value,
        amount: amount,
      );
    }

    void toggleAutoScroll() {
      if (settings.layoutMode != ReaderLayoutMode.scroll) return;
      if (autoScrollActive.value) {
        stopAutoScroll();
        return;
      }
      autoScrollActive.value = true;
      navigationCommand.value = ReaderNavigationCommand.startAutoScroll(
        id: ++navigationSequence.value,
        unit: readerCommands.autoScroll.unit.name,
        speed: readerCommands.autoScroll.speed,
      );
    }

    Future<void> adjustFontSize(double delta) async {
      stopAutoScroll();
      final size = (settings.fontSize + delta).clamp(14, 28).toDouble();
      if (size == settings.fontSize) return;
      await ref
          .read(settingsRepositoryProvider)
          .saveBookOverride(
            BookReadingOverride(
              bookId: bookId,
              settings: settings.copyWith(fontSize: size),
            ),
          );
      ref.invalidate(bookReadingOverrideProvider(bookId));
    }

    Future<void> toggleTextColoring() async {
      stopAutoScroll();
      await ref
          .read(textColoringControllerProvider)
          .saveBookOverride(bookId, !textColoring.enabled);
    }

    void togglePomodoro() {
      final controller = ref.read(pomodoroControllerProvider.notifier);
      if (pomodoro?.isRunning == true) {
        unawaited(controller.pause());
      } else {
        unawaited(controller.startOrResume(bookId: bookId));
      }
    }

    final commandCallbacks = <ReaderCommand, VoidCallback>{
      ReaderCommand.previousPage: goToPrevious,
      ReaderCommand.nextPage: goToNext,
      ReaderCommand.scrollUp: () => scrollByCommand(-0.25),
      ReaderCommand.scrollDown: () => scrollByCommand(0.25),
      ReaderCommand.openTableOfContents: toggleToc,
      ReaderCommand.toggleBookmark: () => unawaited(toggleBookmark()),
      ReaderCommand.search: () => unawaited(openSearch()),
      ReaderCommand.toggleFocusMode: toggleControls,
      ReaderCommand.increaseFontSize: () => unawaited(adjustFontSize(1)),
      ReaderCommand.decreaseFontSize: () => unawaited(adjustFontSize(-1)),
      ReaderCommand.toggleTextColoring: () => unawaited(toggleTextColoring()),
      ReaderCommand.togglePomodoro: togglePomodoro,
      ReaderCommand.ttsPlayPause: () => unawaited(ttsController.playPause()),
      ReaderCommand.ttsStop: () => unawaited(ttsController.stop()),
      ReaderCommand.toggleAutoScroll: toggleAutoScroll,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final chromeLayout = ReaderChromeLayout.resolve(
          context,
          maxWidth: constraints.maxWidth,
        );
        final usesOverflowActions = chromeLayout.usesOverflowActions(
          constraints.maxWidth,
        );
        final usesModalPanels = chromeLayout.usesModalPanels;
        final showToc =
            controlsVisible.value &&
            tocVisible.value &&
            !usesModalPanels &&
            constraints.maxWidth >= tocPanelWidth.value + 160;
        final canShowBothPanels =
            constraints.maxWidth >=
            tocPanelWidth.value + sidePanelWidth.value + 320;
        final showSidePanel =
            controlsVisible.value &&
            sidePanelVisible.value &&
            !usesModalPanels &&
            constraints.maxWidth >= sidePanelWidth.value + 160 &&
            (!showToc || canShowBothPanels);
        final systemTopInset = MediaQuery.viewPaddingOf(context).top;
        final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;
        final toolbarHeight =
            (chromeLayout.isCompact ? kToolbarHeight : 64.0) + systemTopInset;
        final panelTopInset = controlsVisible.value ? toolbarHeight : 8.0;
        final footerHeight =
            (chromeLayout.isCompact ? 56.0 : 74.0) + systemBottomInset;
        final panelBottomInset = controlsVisible.value ? footerHeight : 8.0;
        Future<void> openMobileToc() {
          stopAutoScroll();
          return showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetContext) => MobileReaderTocDrawer(
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
        }

        Future<void> openMobileSidePanel() {
          stopAutoScroll();
          return showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetContext) => MobileReaderSideDrawer(
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
                    .read(annotationControllerProvider)
                    .remove(annotation.id);
                if (focusedAnnotationId.value == annotation.id) {
                  focusedAnnotationId.value = null;
                }
              },
            ),
          );
        }

        void openProgressSheet() {
          final positionLabel = totalChapters == 0
              ? '正在读取目录'
              : !chapterProgressMeasured.value
              ? '第 ${activeChapterIndex + 1} / $totalChapters 章 · 正在定位'
              : '第 ${activeChapterIndex + 1} / $totalChapters 章 · '
                    '本章 ${(chapterProgress * 100).round()}%';
          unawaited(
            showReaderProgressSheet(
              context,
              title: '阅读进度',
              positionLabel: positionLabel,
              progress: chapterProgress,
              onChangeEnd: seekToChapterProgress,
            ),
          );
        }

        final readerBody = Stack(
          children: [
            Positioned.fill(
              child: Material(
                child: Stack(
                  children: [
                    Positioned.fill(
                      // Keep the EPUB viewport stable while reader controls
                      // slide over it. Resizing the WebView here causes the
                      // section to reflow and visibly jumps the reading spot.
                      child: isLoading
                          ? ReaderContentTapDetector(
                              key: const Key('reader-content'),
                              onTap: toggleControls,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : ReaderArticle(
                              settings: settings,
                              textColoring: textColoring,
                              controlsVisible: controlsVisible.value,
                              chapter: chapter.value,
                              error: chapter.error,
                              bookId: readerBook.value == null ? null : bookId,
                              initialScrollRatio: scrollRatio.value,
                              initialAnchor: activeAnchor.value,
                              initialCfi: activeCfi.value,
                              direction:
                                  manifest.value?.direction ??
                                  ReadingDirection.ltr,
                              navigationCommand: navigationCommand.value,
                              annotations: annotations,
                              searchQuery: searchQuery.value,
                              focusedAnnotationId: focusedAnnotationId.value,
                              ttsSegment:
                                  ttsState.status ==
                                          TtsPlaybackStatus.playing ||
                                      ttsState.status ==
                                          TtsPlaybackStatus.paused
                                  ? ttsState.currentSegment
                                  : null,
                              annotationFocusRevision:
                                  annotationFocusRevision.value,
                              restoreRevision: restoreRevision.value,
                              onNavigateToHref: navigateToHref,
                              onScrollPositionChanged:
                                  (href, ratio, anchor, cfi, _, _) {
                                    if (!context.mounted) return;
                                    runtimeController.reportRelocation();
                                    final currentManifest = manifest.value;
                                    final relocatedIndex =
                                        currentManifest == null
                                        ? null
                                        : epubSpineIndexForHref(
                                            currentManifest,
                                            href,
                                          );
                                    if (relocatedIndex == null) {
                                      return;
                                    }
                                    final clampedRatio = ratio
                                        .clamp(0, 1)
                                        .toDouble();
                                    chapterIndex.value = relocatedIndex;
                                    scrollRatio.value = clampedRatio;
                                    chapterProgressMeasured.value = true;
                                    activeAnchor.value = anchor;
                                    activeCfi.value = cfi;
                                    scheduleProgressWrite(
                                      index: relocatedIndex,
                                      chapterRatio: clampedRatio,
                                      anchor: anchor,
                                      cfi: cfi,
                                    );
                                    activityTracker.recordInteraction(
                                      ReaderPosition(
                                        progress: sectionProgress
                                            .overallProgress(
                                              relocatedIndex,
                                              clampedRatio,
                                            ),
                                        locator: EpubLocation(
                                          chapterIndex: relocatedIndex,
                                          scrollRatio: clampedRatio,
                                          anchor: anchor,
                                          cfi: cfi,
                                        ).toLocator(),
                                      ),
                                      isPaginated
                                          ? ReadingInteraction.pageTurn
                                          : ReadingInteraction.scroll,
                                    );
                                  },
                              onPaginationChanged: (index, count) {
                                pageIndex.value = index;
                                pageCount.value = count;
                              },
                              onRequestPrevious: goToPrevious,
                              onRequestNext: goToNext,
                              onNavigationCommandFinished: (id) {
                                navigationGate.value.complete(id);
                                if (navigationCommand.value?.id == id) {
                                  navigationCommand.value = null;
                                }
                              },
                              onAutoScrollChanged: (active) {
                                autoScrollActive.value = active;
                              },
                              onTextSelectionChanged: (selection) {
                                if (!context.mounted) return;
                                selectedText.value = selection;
                                activityTracker.recordInteraction(
                                  ReaderPosition(
                                    progress: sectionProgress.overallProgress(
                                      activeChapterIndex,
                                      scrollRatio.value,
                                    ),
                                    locator: currentLocator,
                                  ),
                                  ReadingInteraction.selection,
                                );
                              },
                              onSelectionContextMenu: (menu) {
                                if (!context.mounted) return;
                                unawaited(openSelectionContextMenu(menu));
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
                          child: ReaderOverlaySurface(
                            child: ReaderTocPanel(
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
                          child: ReaderOverlaySurface(
                            child: ReaderSidePanel(
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
                                    .read(annotationControllerProvider)
                                    .remove(annotation.id);
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
              child: ReaderChromeContainer(
                visible: controlsVisible.value,
                hiddenOffset: const Offset(0, -1),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: chromeLayout.isCompact ? 0 : systemTopInset,
                  ),
                  child: ReaderTopBar(
                    title: title,
                    contextLabel: chapterTitle,
                    tocVisible: tocVisible.value,
                    sidePanelVisible: sidePanelVisible.value,
                    chromeLayout: chromeLayout,
                    usesOverflowActions: usesOverflowActions,
                    bookmarked: isBookmarked,
                    canCreateAnnotation: selectedText.value != null,
                    autoScrollActive: autoScrollActive.value,
                    canAutoScroll:
                        settings.layoutMode == ReaderLayoutMode.scroll,
                    onExitReader: () {
                      unawaited(progressCoordinator.flush());
                      unawaited(ttsController.stop());
                      onExitReader();
                    },
                    onToggleToc: usesModalPanels
                        ? () => unawaited(openMobileToc())
                        : toggleToc,
                    onToggleSidePanel: usesModalPanels
                        ? () => unawaited(openMobileSidePanel())
                        : toggleSidePanel,
                    onHideControls: toggleControls,
                    onToggleBookmark: toggleBookmark,
                    onCreateAnnotation: createAnnotation,
                    onOpenBookSettings: openBookSettings,
                    onOpenSearch: openSearch,
                    onOpenAssistant: openReadingAssistant,
                    onOpenVisualization: openVisualization,
                    onToggleAutoScroll: toggleAutoScroll,
                    ttsController: ttsController,
                    bookId: bookId,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 20,
              bottom:
                  systemBottomInset +
                  (controlsVisible.value
                      ? (chromeLayout.isCompact ? 68 : 86)
                      : 20),
              child: const PomodoroBreakBanner(),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ReaderChromeContainer(
                visible: controlsVisible.value,
                hiddenOffset: const Offset(0, 1),
                child: ReaderFooter(
                  chapterIndex: activeChapterIndex,
                  chapterCount: totalChapters,
                  layoutMode: settings.layoutMode,
                  chromeLayout: chromeLayout,
                  chapterProgress: chapterProgress,
                  chapterProgressMeasured: chapterProgressMeasured.value,
                  onSeekProgress: seekToChapterProgress,
                  onOpenToc: usesModalPanels
                      ? () => unawaited(openMobileToc())
                      : toggleToc,
                  onOpenStyle: () => unawaited(openBookSettings()),
                  onOpenProgress: openProgressSheet,
                  onPrevious:
                      scrollRatio.value > 0.001 ||
                          activeChapterIndex > 0 ||
                          (isPaginated && pageIndex.value > 0)
                      ? goToPrevious
                      : null,
                  onNext:
                      totalChapters > 0 &&
                          (activeChapterIndex < totalChapters - 1 ||
                              scrollRatio.value < 0.999 ||
                              (isPaginated &&
                                  pageIndex.value < pageCount.value - 1))
                      ? goToNext
                      : null,
                ),
              ),
            ),
          ],
        );
        return ReaderCommandShortcuts(
          settings: readerCommands,
          callbacks: commandCallbacks,
          child: readerBody,
        );
      },
    );
  }
}
