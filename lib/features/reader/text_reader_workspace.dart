import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/text_decoder_service.dart';
import '../../data/services/content_chunk_service.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/display_projection.dart';
import '../../domain/models/document_locator.dart';
import '../../domain/models/content_chunk.dart';
import '../../domain/models/embedding_models.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/reading_context.dart';
import '../../domain/models/reading_activity.dart';
import '../../domain/models/reading_position_metrics.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/reader_commands.dart';
import '../../domain/models/text_chapter.dart';
import '../../domain/models/text_coloring.dart';
import '../../domain/models/text_coloring_layout.dart';
import '../../domain/models/tts.dart';
import '../../domain/models/visual_artifact.dart';
import 'pomodoro_controller.dart';
import 'pomodoro_widgets.dart';
import 'reader_auto_scroll.dart';
import 'reader_command_controller.dart';
import 'reader_command_shortcuts.dart';
import 'content_search_dialog.dart';
import 'text_coloring_controller.dart';
import 'text_coloring_text.dart';
import 'text_coloring_widgets.dart';
import 'tts_controller.dart';
import 'tts_controls.dart';
import '../text_import/text_content_controller.dart';
import '../text_import/text_projection_controller.dart';
import '../text_import/text_projection_dialog.dart';
import '../assistant/content_index_controller.dart';
import '../chat/chat_controller.dart';
import '../visualization/reader_visualization_dialog.dart';

enum _TextChapterAction { rename, split, mergeNext }

class TextReaderWorkspace extends HookConsumerWidget {
  const TextReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
    required this.readingSettings,
    required this.onExitReader,
    required this.onOpenChat,
  });

  final String bookId;
  final String title;
  final ReadingSettings readingSettings;
  final VoidCallback onExitReader;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentState = ref.watch(textBookDocumentProvider(bookId));
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
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
    final readingOverride = ref.watch(bookReadingOverrideProvider(bookId)).value;
    final settings = readingOverride?.settings ?? readingSettings;
    ref.watch(readingFontReadyProvider(settings.font));
    final chapterIndex = useState(0);
    final scrollController = useScrollController();
    final currentScrollRatio = useState(0.0);
    final scrollSaveTimer = useRef<Timer?>(null);
    final selectedContext = useState<ReadingContextSelection?>(null);
    final projectionConfigState = ref.watch(
      textProjectionConfigProvider(bookId),
    );
    final textColoringState = ref.watch(resolvedTextColoringProvider(bookId));
    final textColoringOverride = ref.watch(
      bookTextColoringOverrideProvider(bookId),
    );
    final readerCommandState = ref.watch(readerCommandSettingsProvider);
    final defaultReaderCommands = useMemoized(ReaderCommandSettings.defaults);
    final readerCommands = readerCommandState.value ?? defaultReaderCommands;
    final autoScrollController = useMemoized(
      () => ReaderAutoScrollController(preference: readerCommands.autoScroll),
    );
    useListenable(autoScrollController);
    final focusMode = useState(false);
    final disabledTextColoring = useMemoized(ResolvedTextColoring.disabled);
    final textColoring = textColoringState.value ?? disabledTextColoring;
    final selectedColorText = useState<String?>(null);
    final lifecycle = useAppLifecycleState();
    final pomodoro = ref.watch(pomodoroControllerProvider).value;
    final breakActive = pomodoro?.isBreak == true && pomodoro?.isRunning == true;
    final tracker = ref.read(readingActivityTrackerProvider);
    final document = documentState.value;
    final textPositionIndex = useMemoized(
      () => ReadingTextPositionIndex.fromText(document?.rawText ?? ''),
      [document?.profile.contentHash],
    );
    final activeChapter = document == null || document.chapters.isEmpty
        ? null
        : document.chapters[
            chapterIndex.value
                .clamp(0, document.chapters.length - 1)
                .toInt()
          ];
    final rawChapterText = activeChapter == null
        ? ''
        : document!.rawText.substring(
            activeChapter.rawStart.clamp(0, document.rawText.length).toInt(),
            activeChapter.rawEnd
                .clamp(activeChapter.rawStart, document.rawText.length)
                .toInt(),
          );
    final projectionConfig =
        projectionConfigState.value ??
        const TextProjectionConfig(
          settings: TextProjectionSettings(),
          rules: [],
        );
    final projectionJob = useMemoized(
      () => ref.read(textDisplayTransformServiceProvider).startProjection(
        bookId: bookId,
        rawText: rawChapterText,
        settings: projectionConfig.settings,
        rules: projectionConfig.rules,
      ),
      [bookId, rawChapterText, projectionConfig],
    );
    final projectionSnapshot = useFuture(projectionJob.result);
    final fallbackProjection = useMemoized(
      () => DisplayProjection.identity(rawChapterText),
      [rawChapterText],
    );
    final effectiveProjection = projectionSnapshot.data?.rawText == rawChapterText
        ? projectionSnapshot.data!
        : fallbackProjection;
    final markdown = document?.book.format == 'markdown';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final coloringLayoutJob = useMemoized(
      () => ref.read(textColoringLayoutServiceProvider).startLayout(
        projection: effectiveProjection,
        coloring: textColoring,
        markdown: markdown,
        dark: dark,
      ),
      [effectiveProjection, textColoring, markdown, dark],
    );
    final coloringLayoutSnapshot = useFuture(
      coloringLayoutJob.result,
      preserveState: false,
    );

    useEffect(() => ttsController.dispose, [ttsController]);

    useEffect(
      () => () => unawaited(projectionJob.cancel()),
      [projectionJob],
    );
    useEffect(
      () => () => unawaited(coloringLayoutJob.cancel()),
      [coloringLayoutJob],
    );
    useEffect(() {
      autoScrollController.updatePreference(readerCommands.autoScroll);
      return null;
    }, [autoScrollController, readerCommands.autoScroll]);
    useEffect(
      () => autoScrollController.dispose,
      [autoScrollController],
    );

    useEffect(() {
      final current = document;
      final index = contentIndexState.value;
      if (current == null || contentIndexState.isLoading) return null;
      final needsRebuild =
          index == null ||
          index.status == ContentIndexStatus.failed ||
          index.contentHash != current.profile.contentHash ||
          index.indexVersion != ContentChunkService.indexVersion;
      if (needsRebuild && index?.status != ContentIndexStatus.indexing) {
        unawaited(
          ref.read(contentIndexControllerProvider).rebuildText(
            bookId: bookId,
            rawText: current.rawText,
            contentHash: current.profile.contentHash,
            chapters: current.chapters,
          ),
        );
      }
      return null;
    }, [
      bookId,
      document?.profile.contentHash,
      contentIndexState.isLoading,
      contentIndexState.value?.status,
      contentIndexState.value?.contentHash,
    ]);

    useEffect(() {
      final current = document;
      final chapter = activeChapter;
      if (current == null ||
          chapter == null ||
          contentIndexState.value?.status != ContentIndexStatus.ready) {
        return null;
      }
      final rawOffset = (chapter.rawStart +
              (chapter.rawEnd - chapter.rawStart) * currentScrollRatio.value)
          .round()
          .clamp(chapter.rawStart, chapter.rawEnd)
          .toInt();
      unawaited(
        ttsController.prepare(
          bookId: bookId,
          format: current.book.format,
          chapterIndex: chapter.ordinal,
          currentLocator: chapter.locator(start: rawOffset, end: rawOffset),
        ),
      );
      return null;
    }, [
      ttsController,
      document?.profile.contentHash,
      contentIndexState.value?.status,
      activeChapter?.id,
    ]);

    useEffect(() {
      final book = document?.book;
      if (book != null && document!.chapters.isNotEmpty) {
        final savedLocator = TextDocumentLocator.tryParse(book.locator);
        chapterIndex.value = (savedLocator?.chapterIndex ?? book.chapterIndex).clamp(
          0,
          document.chapters.length - 1,
        ).toInt();
        final rawOffset = savedLocator?.rawStart;
        if (rawOffset != null) {
          final chapter = document.chapters[chapterIndex.value];
          final ratio = chapter.rawEnd <= chapter.rawStart
              ? 0.0
              : ((rawOffset - chapter.rawStart) /
                        (chapter.rawEnd - chapter.rawStart))
                    .clamp(0, 1)
                    .toDouble();
          currentScrollRatio.value = ratio;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients) {
              scrollController.jumpTo(
                scrollController.position.maxScrollExtent * ratio,
              );
            }
          });
        }
        tracker.open(
          ReaderIdentity(bookId: bookId, format: ReaderFormat.text),
          ReaderPosition(progress: book.progress, locator: book.locator),
        );
        tracker.recordInteraction(
          ReaderPosition(progress: book.progress, locator: book.locator),
          ReadingInteraction.navigation,
        );
      }
      return book == null ? null : () => unawaited(tracker.close());
    }, [bookId, document?.book.id, document?.book.locator]);

    useEffect(() {
      tracker.setForeground(
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
            !breakActive,
      );
      if ((lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          breakActive) {
        autoScrollController.stop(AutoScrollStopReason.lifecycle);
        if (ttsState.status == TtsPlaybackStatus.playing) {
          unawaited(ttsController.pause());
        }
      }
      return null;
    }, [
      lifecycle,
      breakActive,
      autoScrollController,
      ttsState.status,
      ttsController,
    ]);

    useEffect(() {
      if (settings.layoutMode != ReaderLayoutMode.scroll) {
        autoScrollController.stop(AutoScrollStopReason.layoutUnavailable);
      }
      return null;
    }, [settings.layoutMode, autoScrollController]);

    useEffect(() {
      final current = document;
      final chapter = activeChapter;
      if (current == null || chapter == null) return null;

      void handleScroll() {
        if (!scrollController.hasClients) return;
        final extent = scrollController.position.maxScrollExtent;
        final ratio = extent <= 0
            ? 0.0
            : (scrollController.offset / extent).clamp(0, 1).toDouble();
        if ((ratio - currentScrollRatio.value).abs() < 0.001) return;
        currentScrollRatio.value = ratio;
        final rawOffset = (chapter.rawStart +
                (chapter.rawEnd - chapter.rawStart) * ratio)
            .round()
            .clamp(chapter.rawStart, chapter.rawEnd)
            .toInt();
        final progress = current.rawText.isEmpty
            ? 0.0
            : rawOffset / current.rawText.length;
        final locator = chapter.locator(start: rawOffset, end: rawOffset);
        scrollSaveTimer.value?.cancel();
        scrollSaveTimer.value = Timer(const Duration(milliseconds: 600), () {
          unawaited(
            ref
                .read(bookRepositoryProvider)
                .updateReadingPosition(
                  bookId: bookId,
                  chapterIndex: chapter.ordinal,
                  progress: progress,
                  locator: locator,
                ),
          );
          tracker.recordInteraction(
            ReaderPosition(progress: progress, locator: locator),
            ReadingInteraction.scroll,
          );
        });
      }

      scrollController.addListener(handleScroll);
      return () {
        scrollController.removeListener(handleScroll);
        scrollSaveTimer.value?.cancel();
        scrollSaveTimer.value = null;
      };
    }, [
      bookId,
      scrollController,
      activeChapter?.id,
      document?.profile.contentHash,
    ]);

    Future<void> selectChapter(int index) async {
      autoScrollController.stop(AutoScrollStopReason.chapterChange);
      final current = document;
      if (current == null || index < 0 || index >= current.chapters.length) {
        return;
      }
      await ttsController.stop();
      chapterIndex.value = index;
      currentScrollRatio.value = 0;
      selectedContext.value = null;
      if (scrollController.hasClients) scrollController.jumpTo(0);
      final chapter = current.chapters[index];
      final progress = current.rawText.isEmpty
          ? 0.0
          : chapter.rawStart / current.rawText.length;
      await ref.read(bookRepositoryProvider).updateReadingPosition(
        bookId: bookId,
        chapterIndex: index,
        progress: progress,
        locator: chapter.locator(),
      );
      tracker.recordInteraction(
        ReaderPosition(progress: progress, locator: chapter.locator()),
        ReadingInteraction.navigation,
      );
    }

    Future<void> openChapters(List<TextChapter> chapters) async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('章节目录'),
          content: SizedBox(
            width: 420,
            height: 520,
            child: ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, index) => ListTile(
                selected: index == chapterIndex.value,
                leading: Text('${index + 1}'),
                title: Text(chapters[index].title),
                onTap: () => Navigator.pop(context, index),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      if (selected != null && context.mounted) await selectChapter(selected);
    }

    Future<void> changeEncoding() async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      final profile = document?.profile;
      if (profile == null) return;
      final encoding = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('重新选择文本编码'),
          children: supportedTextEncodings
              .map(
                (value) => ListTile(
                  selected: value == profile.encoding,
                  leading: Icon(
                    value == profile.encoding
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(value.toUpperCase()),
                  onTap: () => Navigator.pop(context, value),
                ),
              )
              .toList(),
        ),
      );
      if (encoding == null || encoding == profile.encoding || !context.mounted) {
        return;
      }
      try {
        await ref
            .read(textContentControllerProvider)
            .rebuildWithEncoding(bookId, encoding);
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重新解析失败：$error')),
          );
        }
      }
    }

    Future<void> editCurrentChapter() async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      final current = document;
      if (current == null || current.chapters.isEmpty) return;
      final index = chapterIndex.value.clamp(
        0,
        current.chapters.length - 1,
      ).toInt();
      final chapter = current.chapters[index];
      final action = await showMenu<_TextChapterAction>(
        context: context,
        position: const RelativeRect.fromLTRB(200, 72, 24, 0),
        items: [
          const PopupMenuItem(
            value: _TextChapterAction.rename,
            child: Text('重命名当前章节'),
          ),
          PopupMenuItem(
            value: _TextChapterAction.split,
            enabled: chapter.rawEnd - chapter.rawStart >= 2,
            child: const Text('拆分当前章节'),
          ),
          PopupMenuItem(
            value: _TextChapterAction.mergeNext,
            enabled: index + 1 < current.chapters.length,
            child: const Text('与下一章合并'),
          ),
        ],
      );
      if (action == null || !context.mounted) return;
      final controller = ref.read(textContentControllerProvider);
      switch (action) {
        case _TextChapterAction.rename:
          final titleController = TextEditingController(text: chapter.title);
          final title = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('重命名章节'),
              content: TextField(
                controller: titleController,
                autofocus: true,
                maxLength: 120,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, titleController.text),
                  child: const Text('保存'),
                ),
              ],
            ),
          );
          titleController.dispose();
          if (title != null && context.mounted) {
            await controller.renameChapter(bookId, chapter.id, title);
          }
        case _TextChapterAction.split:
          final chapterText = current.rawText.substring(
            chapter.rawStart,
            chapter.rawEnd,
          );
          final splitOffset = chapter.rawStart + _safeSplitOffset(chapterText);
          final nextTitleController = TextEditingController(
            text: '${chapter.title}（下）',
          );
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('拆分章节'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('将在接近章节中点的空行处分割；原始文本不会改变。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nextTitleController,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: '后半章标题'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('拆分'),
                ),
              ],
            ),
          );
          final nextTitle = nextTitleController.text;
          nextTitleController.dispose();
          if (confirmed == true && context.mounted) {
            await controller.splitChapter(
              bookId: bookId,
              ordinal: index,
              rawOffset: splitOffset,
              nextTitle: nextTitle,
            );
          }
        case _TextChapterAction.mergeNext:
          await controller.mergeWithNext(bookId, index);
      }
    }

    Future<void> copyOriginalChapter() async {
      if (rawChapterText.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: rawChapterText));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制当前章节原文。')),
        );
      }
    }

    String? currentTextLocator() {
      final chapter = activeChapter;
      if (chapter == null) return null;
      final offset = (chapter.rawStart +
              (chapter.rawEnd - chapter.rawStart) * currentScrollRatio.value)
          .round()
          .clamp(chapter.rawStart, chapter.rawEnd)
          .toInt();
      return chapter.locator(start: offset, end: offset);
    }

    Future<void> toggleBookmark() async {
      final locator = currentTextLocator();
      final chapter = activeChapter;
      if (locator == null || chapter == null) return;
      final repository = ref.read(bookmarkRepositoryProvider);
      final existing = (bookmarks.value ?? const <Bookmark>[])
          .where((bookmark) => bookmark.locator == locator)
          .firstOrNull;
      if (existing == null) {
        await repository.add(
          bookId: bookId,
          locator: locator,
          chapterTitle: chapter.title,
        );
      } else {
        await repository.remove(existing.id);
      }
      ref.invalidate(bookmarksForBookProvider(bookId));
    }

    Future<void> searchIndexedContent() async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      final result = await showDialog<HybridSearchResult>(
        context: context,
        builder: (context) => ContentSearchDialog(
          bookId: bookId,
          maxChapterIndex: chapterIndex.value,
          maxRawOffset: activeChapter == null
              ? null
              : (activeChapter.rawStart +
                        (activeChapter.rawEnd - activeChapter.rawStart) *
                            currentScrollRatio.value)
                    .round(),
        ),
      );
      final current = document;
      if (result == null || current == null || !context.mounted) return;
      chapterIndex.value = result.chapterIndex
          .clamp(0, current.chapters.length - 1)
          .toInt();
      selectedContext.value = null;
      await ref.read(bookRepositoryProvider).updateReadingPosition(
        bookId: bookId,
        chapterIndex: chapterIndex.value,
        progress: current.rawText.isEmpty
            ? 0
            : result.rawStart / current.rawText.length,
        locator: result.locator,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final chapter = current.chapters[chapterIndex.value];
        final ratio = chapter.rawEnd <= chapter.rawStart
            ? 0.0
            : ((result.rawStart - chapter.rawStart) /
                      (chapter.rawEnd - chapter.rawStart))
                  .clamp(0, 1)
                  .toDouble();
        currentScrollRatio.value = ratio;
        if (scrollController.hasClients) {
          scrollController.jumpTo(
            scrollController.position.maxScrollExtent * ratio,
          );
        }
      });
    }

    Future<void> openReadingAssistant() async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      final action = await showDialog<ReadingAssistantAction>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('阅读助手'),
          children: [
            for (final action in ReadingAssistantAction.values)
              ListTile(
                enabled:
                    action != ReadingAssistantAction.explainSelection ||
                    selectedContext.value != null,
                leading: Icon(switch (action) {
                  ReadingAssistantAction.explainSelection => Icons.lightbulb_outline,
                  ReadingAssistantAction.summarizeChapter => Icons.summarize_outlined,
                  ReadingAssistantAction.generateQuestions => Icons.quiz_outlined,
                  ReadingAssistantAction.extractPeopleAndTerms => Icons.people_outline,
                  ReadingAssistantAction.buildTimeline => Icons.timeline,
                }),
                title: Text(action.label),
                onTap:
                    action == ReadingAssistantAction.explainSelection &&
                        selectedContext.value == null
                    ? null
                    : () => Navigator.pop(dialogContext, action),
              ),
          ],
        ),
      );
      if (action == null || !context.mounted) return;
      final bundle = await ref.read(readingContextAssemblerProvider).assemble(
        bookId: bookId,
        currentChapterIndex: chapterIndex.value,
        selection: action == ReadingAssistantAction.explainSelection
            ? selectedContext.value
            : null,
        includeCurrentChapter:
            action != ReadingAssistantAction.explainSelection,
        allowFutureChapters: false,
      );
      if (bundle.segments.isEmpty || !context.mounted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前章节索引尚未就绪，请稍后重试。')),
          );
        }
        return;
      }
      final first = bundle.segments.first;
      final quote = bundle.segments
          .map(
            (segment) =>
                '[${segment.chapterTitle} · ${segment.locator}]\n${segment.text}',
          )
          .join('\n\n');
      ref.read(pendingChatDraftProvider.notifier).set(
        PendingChatDraft(
          attachment: ChatContextAttachment(
            bookId: bookId,
            bookTitle: title,
            href: first.href,
            locator: first.locator,
            chapterIndex: first.chapterIndex,
            chapterTitle: first.chapterTitle,
            quote: quote,
          ),
          prompt:
              '${action.prompt}\n\n仅使用当前进度及之前的内容，避免剧透。'
              '请使用书内搜索工具核对书内事实并附上可点击引用。'
              '\n上下文校验：${bundle.contextHash}',
        ),
      );
      onOpenChat();
    }

    Future<void> navigateToArtifactCitation(
      ArtifactCitation citation,
    ) async {
      final current = document;
      if (current == null || current.chapters.isEmpty) return;
      final nextIndex = citation.chapterIndex
          .clamp(0, current.chapters.length - 1)
          .toInt();
      chapterIndex.value = nextIndex;
      selectedContext.value = null;
      final chapter = current.chapters[nextIndex];
      final rawOffset = TextDocumentLocator.tryParse(
        citation.locator,
      )?.rawStart;
      final targetOffset = rawOffset ?? chapter.rawStart;
      final progress = current.rawText.isEmpty
          ? 0.0
          : targetOffset / current.rawText.length;
      await ref.read(bookRepositoryProvider).updateReadingPosition(
        bookId: bookId,
        chapterIndex: nextIndex,
        progress: progress,
        locator: citation.locator,
      );
      tracker.recordInteraction(
        ReaderPosition(progress: progress, locator: citation.locator),
        ReadingInteraction.navigation,
      );
      if (!context.mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        final ratio = rawOffset == null || chapter.rawEnd <= chapter.rawStart
            ? 0.0
            : ((rawOffset - chapter.rawStart) /
                      (chapter.rawEnd - chapter.rawStart))
                  .clamp(0, 1)
                  .toDouble();
        currentScrollRatio.value = ratio;
        scrollController.jumpTo(
          scrollController.position.maxScrollExtent * ratio,
        );
      });
    }

    Future<void> openVisualization() async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ReaderVisualizationDialog(
          bookId: bookId,
          bookTitle: title,
          currentChapterIndex: chapterIndex.value,
          onOpenCitation: (citation) {
            Navigator.pop(dialogContext);
            unawaited(navigateToArtifactCitation(citation));
          },
        ),
      );
    }

    Future<void> addSelectedTextColor() async {
      autoScrollController.stop(AutoScrollStopReason.selection);
      final selection = selectedColorText.value;
      if (selection == null || selection.trim().isEmpty) return;
      final draft = await showDialog<TextColorTermDraft>(
        context: context,
        builder: (context) => TextColorTermChoiceDialog(
          text: selection,
          settings: textColoring.settings,
        ),
      );
      if (draft == null || !context.mounted) return;
      try {
        await ref
            .read(textColoringControllerProvider)
            .assignTerm(
              term: selection,
              tone: draft.tone,
              bookId: draft.global ? null : bookId,
            );
        selectedColorText.value = null;
      } on TextColoringException catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }

    Future<void> openTextColoringSettings() async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      final result = await showDialog<_TextColoringOverrideResult>(
        context: context,
        builder: (context) => _TextColoringBookDialog(
          bookId: bookId,
          settings: textColoring.settings,
          bookOverride: textColoringOverride.value,
        ),
      );
      if (result == null || !context.mounted) return;
      await ref
          .read(textColoringControllerProvider)
          .saveBookOverride(bookId, result.value);
    }

    Future<void> openProjectionSettings() async {
      autoScrollController.stop(AutoScrollStopReason.dialog);
      await showDialog<void>(
        context: context,
        builder: (context) => TextProjectionDialog(bookId: bookId),
      );
    }

    void scrollByCommand(double direction) {
      autoScrollController.stop(AutoScrollStopReason.userInput);
      if (!scrollController.hasClients) return;
      final position = scrollController.position;
      final target = (scrollController.offset +
              position.viewportDimension * 0.85 * direction)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      unawaited(
        scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    }

    Future<void> adjustFontSize(double delta) async {
      autoScrollController.stop(AutoScrollStopReason.layoutUnavailable);
      final size = (settings.fontSize + delta).clamp(14, 28).toDouble();
      if (size == settings.fontSize) return;
      await ref.read(settingsRepositoryProvider).saveBookOverride(
        BookReadingOverride(
          bookId: bookId,
          settings: settings.copyWith(fontSize: size),
        ),
      );
      ref.invalidate(bookReadingOverrideProvider(bookId));
    }

    Future<void> toggleTextColoring() async {
      autoScrollController.stop(AutoScrollStopReason.layoutUnavailable);
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

    void toggleAutoScroll() {
      if (settings.layoutMode != ReaderLayoutMode.scroll) return;
      if (autoScrollController.active) {
        autoScrollController.stop();
      } else if (scrollController.hasClients) {
        autoScrollController.start();
      }
    }

    void toggleFocusMode() {
      autoScrollController.stop(AutoScrollStopReason.layoutUnavailable);
      focusMode.value = !focusMode.value;
    }

    final commandCallbacks = <ReaderCommand, VoidCallback>{
      ReaderCommand.previousPage: () {
        if (scrollController.hasClients && scrollController.offset > 1) {
          scrollByCommand(-1);
        } else if (chapterIndex.value > 0) {
          unawaited(selectChapter(chapterIndex.value - 1));
        }
      },
      ReaderCommand.nextPage: () {
        final chapterCount = document?.chapters.length ?? 0;
        if (scrollController.hasClients &&
            scrollController.offset <
                scrollController.position.maxScrollExtent - 1) {
          scrollByCommand(1);
        } else if (chapterIndex.value + 1 < chapterCount) {
          unawaited(selectChapter(chapterIndex.value + 1));
        }
      },
      ReaderCommand.scrollUp: () => scrollByCommand(-0.25),
      ReaderCommand.scrollDown: () => scrollByCommand(0.25),
      ReaderCommand.openTableOfContents: () {
        final chapters = document?.chapters;
        if (chapters != null) unawaited(openChapters(chapters));
      },
      ReaderCommand.toggleBookmark: () => unawaited(toggleBookmark()),
      ReaderCommand.search: () => unawaited(searchIndexedContent()),
      ReaderCommand.toggleFocusMode: toggleFocusMode,
      ReaderCommand.increaseFontSize: () => unawaited(adjustFontSize(1)),
      ReaderCommand.decreaseFontSize: () => unawaited(adjustFontSize(-1)),
      ReaderCommand.toggleTextColoring: () => unawaited(toggleTextColoring()),
      ReaderCommand.togglePomodoro: togglePomodoro,
      ReaderCommand.ttsPlayPause: () => unawaited(ttsController.playPause()),
      ReaderCommand.ttsStop: () => unawaited(ttsController.stop()),
      ReaderCommand.toggleAutoScroll: toggleAutoScroll,
    };

    final scaffold = Scaffold(
      appBar: focusMode.value
          ? null
          : AppBar(
              leading: IconButton(
                tooltip: '返回书库',
                onPressed: () {
                  unawaited(ttsController.stop());
                  onExitReader();
                },
                icon: const Icon(Icons.arrow_back),
              ),
              title: Text(title, overflow: TextOverflow.ellipsis),
              actions: [
          TtsToolbarButton(
            controller: ttsController,
            onBeforeOpen: () => autoScrollController.stop(
              AutoScrollStopReason.dialog,
            ),
          ),
          PomodoroToolbarButton(
            bookId: bookId,
            onOpen: () => autoScrollController.stop(
              AutoScrollStopReason.dialog,
            ),
          ),
          IconButton(
            key: const Key('text-reader-auto-scroll'),
            tooltip: settings.layoutMode == ReaderLayoutMode.scroll
                ? autoScrollController.active
                      ? '停止自动滚动'
                      : '开始自动滚动'
                : '自动滚动仅支持滚动布局',
            onPressed: settings.layoutMode == ReaderLayoutMode.scroll
                ? toggleAutoScroll
                : null,
            isSelected: autoScrollController.active,
            icon: Icon(
              autoScrollController.active
                  ? Icons.pause_circle_outline
                  : Icons.slow_motion_video_outlined,
            ),
          ),
          IconButton(
            tooltip: '章节目录',
            onPressed: document == null
                ? null
                : () => openChapters(document.chapters),
            icon: const Icon(Icons.format_list_bulleted),
          ),
          IconButton(
            key: const Key('text-reader-bookmark'),
            tooltip: (bookmarks.value ?? const <Bookmark>[]).any(
              (bookmark) => bookmark.locator == currentTextLocator(),
            )
                ? '移除书签'
                : '添加书签',
            onPressed: document == null ? null : toggleBookmark,
            icon: Icon(
              (bookmarks.value ?? const <Bookmark>[]).any(
                (bookmark) => bookmark.locator == currentTextLocator(),
              )
                  ? Icons.bookmark
                  : Icons.bookmark_border,
            ),
          ),
          IconButton(
            tooltip: '文本编码',
            onPressed: document == null ? null : changeEncoding,
            icon: const Icon(Icons.text_snippet_outlined),
          ),
          IconButton(
            tooltip: '搜索本地正文',
            onPressed: searchIndexedContent,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: '编辑章节',
            onPressed: document == null ? null : editCurrentChapter,
            icon: const Icon(Icons.edit_note),
          ),
          IconButton(
            tooltip: '文本显示投影',
            onPressed: openProjectionSettings,
            icon: const Icon(Icons.translate),
          ),
          IconButton(
            tooltip: '将选中文字设为前景色',
            onPressed: selectedColorText.value == null
                ? null
                : addSelectedTextColor,
            icon: const Icon(Icons.format_color_text_outlined),
          ),
          IconButton(
            tooltip: '本书文字前景色设置',
            onPressed: openTextColoringSettings,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: '阅读助手',
            onPressed: openReadingAssistant,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: '词云与思维导图',
            onPressed: openVisualization,
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: '复制当前章节原文',
            onPressed: rawChapterText.isEmpty ? null : copyOriginalChapter,
            icon: const Icon(Icons.content_copy_outlined),
          ),
              ],
            ),
      body: Stack(
        children: [
          documentState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('无法打开文本书籍：$error')),
            data: (value) {
              if (value.chapters.isEmpty) {
                return const Center(child: Text('未识别到可阅读内容。'));
              }
              final index = chapterIndex.value.clamp(
                0,
                value.chapters.length - 1,
              ).toInt();
              final chapter = value.chapters[index];
              final start = chapter.rawStart
                  .clamp(0, value.rawText.length)
                  .toInt();
              final end = chapter.rawEnd
                  .clamp(start, value.rawText.length)
                  .toInt();
              final rawContent = value.rawText.substring(start, end);
              final rawOffset = (start +
                      (end - start) * currentScrollRatio.value)
                  .round()
                  .clamp(start, end)
                  .toInt();
              final positionMetrics = textPositionIndex.metricsForOffset(
                rawOffset,
              );
              final projection = effectiveProjection.rawText == rawContent
                  ? effectiveProjection
                  : DisplayProjection.identity(rawContent);
              final layout = coloringLayoutSnapshot.data ??
                  TextColoringLayout.plain(projection.displayText);
              final textStyle = TextStyle(
                fontFamily: settings.font.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
              );
              TextEmphasisRange? ttsEmphasis;
              final ttsSegment = ttsState.currentSegment;
              if ((ttsState.status == TtsPlaybackStatus.playing ||
                      ttsState.status == TtsPlaybackStatus.paused) &&
                  ttsSegment != null &&
                  ttsSegment.chapterIndex == index) {
                final displayRange = projection.rawToDisplay(
                  ttsSegment.rawStart - start,
                  ttsSegment.rawEnd - start,
                );
                final visibleRange = layout.displayToVisible(
                  displayRange.start,
                  displayRange.end,
                );
                if (visibleRange.end > visibleRange.start) {
                  ttsEmphasis = TextEmphasisRange(
                    start: visibleRange.start,
                    end: visibleRange.end,
                  );
                }
              }
              return Column(
                children: [
                  if (projectionSnapshot.hasError)
                    MaterialBanner(
                      content: Text('显示转换失败，已回退原文：${projectionSnapshot.error}'),
                      actions: const [SizedBox.shrink()],
                    )
                  else if (projection.hasAmbiguousRanges)
                    const MaterialBanner(
                      content: Text(
                        '本章含无法精确映射的转换区段；这些区段不会创建可回跳标注或文字颜色。',
                      ),
                      actions: [SizedBox.shrink()],
                    ),
                  if (coloringLayoutSnapshot.hasError)
                    MaterialBanner(
                      content: Text(
                        '文字前景色计算失败，已显示无颜色正文：${coloringLayoutSnapshot.error}',
                      ),
                      actions: const [SizedBox.shrink()],
                    ),
                  Material(
                    key: const Key('text-reader-sticky-chapter-title'),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    elevation: 1,
                    child: InkWell(
                      onTap: focusMode.value ? toggleFocusMode : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                chapter.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            if (autoScrollController.active) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.slow_motion_video, size: 18),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReaderAutoScrollRegion(
                      controller: autoScrollController,
                      scrollController: scrollController,
                      lineExtent: settings.fontSize * settings.lineHeight,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        key: ValueKey(chapter.id),
                        padding: EdgeInsets.symmetric(
                          horizontal: settings.pageMargin,
                          vertical: 32,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: TextColoringSelectableText(
                              key: const Key('text-reader-selectable-content'),
                              layout: layout,
                              style: textStyle,
                              emphasisRange: ttsEmphasis,
                              onSelectionChanged: (selection, _) {
                                if (!selection.isCollapsed) {
                                  autoScrollController.stop(
                                    AutoScrollStopReason.selection,
                                  );
                                }
                                if (selection.isCollapsed) {
                                  selectedContext.value = null;
                                  selectedColorText.value = null;
                                  return;
                                }
                                final displayRange = layout.visibleToDisplay(
                                  selection.start,
                                  selection.end,
                                );
                                if (!displayRange.isExact) {
                                  selectedContext.value = null;
                                  selectedColorText.value = null;
                                  return;
                                }
                                final range = projection.displayToRaw(
                                  displayRange.start,
                                  displayRange.end,
                                );
                                if (!range.isExact) {
                                  selectedContext.value = null;
                                  selectedColorText.value = null;
                                  return;
                                }
                                final rawStart = start + range.start;
                                final rawEnd = start + range.end;
                                selectedColorText.value = layout.text.substring(
                                  selection.start,
                                  selection.end,
                                );
                                selectedContext.value =
                                    ReadingContextSelection(
                                      text: value.rawText.substring(
                                        rawStart,
                                        rawEnd,
                                      ),
                                      href: 'text:${chapter.id}',
                                      locator: chapter.locator(
                                        start: rawStart,
                                        end: rawEnd,
                                      ),
                                      chapterIndex: index,
                                      chapterTitle: chapter.title,
                                    );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: '上一章',
                            onPressed: index > 0
                                ? () => selectChapter(index - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              '${chapter.title} · ${positionMetrics.label}',
                              key: const Key('text-reader-position-label'),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '下一章',
                            onPressed: index < value.chapters.length - 1
                                ? () => selectChapter(index + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const Positioned(right: 20, bottom: 70, child: PomodoroBreakBanner()),
        ],
      ),
    );
    return ReaderCommandShortcuts(
      settings: readerCommands,
      callbacks: commandCallbacks,
      child: scaffold,
    );
  }
}

enum _TextColoringBookMode { followGlobal, enabled, disabled }

class _TextColoringOverrideResult {
  const _TextColoringOverrideResult(this.value);

  final bool? value;
}

class _TextColoringBookDialog extends StatefulWidget {
  const _TextColoringBookDialog({
    required this.bookId,
    required this.settings,
    required this.bookOverride,
  });

  final String bookId;
  final TextColoringSettings settings;
  final bool? bookOverride;

  @override
  State<_TextColoringBookDialog> createState() =>
      _TextColoringBookDialogState();
}

class _TextColoringBookDialogState extends State<_TextColoringBookDialog> {
  late _TextColoringBookMode _mode = switch (widget.bookOverride) {
    true => _TextColoringBookMode.enabled,
    false => _TextColoringBookMode.disabled,
    null => _TextColoringBookMode.followGlobal,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('本书文字前景色'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_TextColoringBookMode>(
            segments: const [
              ButtonSegment(
                value: _TextColoringBookMode.followGlobal,
                label: Text('跟随全局'),
              ),
              ButtonSegment(
                value: _TextColoringBookMode.enabled,
                label: Text('开启'),
              ),
              ButtonSegment(
                value: _TextColoringBookMode.disabled,
                label: Text('关闭'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 16),
          Text(
            widget.settings.enabled
                ? '全局文字前景色当前已开启；本书设置可覆盖全局开关。'
                : '全局文字前景色当前已关闭；可仅为本书开启。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => TextColorTermsManagerDialog(
                settings: widget.settings,
                title: '本书文字词条',
                bookId: widget.bookId,
              ),
            ),
            icon: const Icon(Icons.format_color_text_outlined),
            label: const Text('管理本书词条'),
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
          _TextColoringOverrideResult(
            switch (_mode) {
              _TextColoringBookMode.followGlobal => null,
              _TextColoringBookMode.enabled => true,
              _TextColoringBookMode.disabled => false,
            },
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

int _safeSplitOffset(String text) {
  if (text.length < 2) return text.length;
  final middle = text.length ~/ 2;
  final blankAfter = text.indexOf('\n\n', middle);
  if (blankAfter >= 0 && blankAfter + 2 < text.length) return blankAfter + 2;
  final lineAfter = text.indexOf('\n', middle);
  if (lineAfter >= 0 && lineAfter + 1 < text.length) return lineAfter + 1;
  var offset = middle.clamp(1, text.length - 1).toInt();
  final previous = text.codeUnitAt(offset - 1);
  final current = text.codeUnitAt(offset);
  if (previous >= 0xd800 &&
      previous <= 0xdbff &&
      current >= 0xdc00 &&
      current <= 0xdfff) {
    offset++;
  }
  return offset.clamp(1, text.length - 1).toInt();
}
