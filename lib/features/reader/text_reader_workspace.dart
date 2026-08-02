import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/text_decoder_service.dart';
import '../../data/services/content_chunk_service.dart';
import '../../domain/models/display_projection.dart';
import '../../domain/models/content_chunk.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/reading_context.dart';
import '../../domain/models/reading_activity.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_chapter.dart';
import '../../domain/models/visual_artifact.dart';
import 'pomodoro_controller.dart';
import 'pomodoro_widgets.dart';
import 'content_search_dialog.dart';
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
    final contentIndexState = ref.watch(contentIndexStateProvider(bookId));
    final readingOverride = ref.watch(bookReadingOverrideProvider(bookId)).value;
    final settings = readingOverride?.settings ?? readingSettings;
    ref.watch(readingFontReadyProvider(settings.font));
    final chapterIndex = useState(0);
    final scrollController = useScrollController();
    final selectedContext = useState<ReadingContextSelection?>(null);
    final projectionConfigState = ref.watch(
      textProjectionConfigProvider(bookId),
    );
    final lifecycle = useAppLifecycleState();
    final pomodoro = ref.watch(pomodoroControllerProvider).value;
    final breakActive = pomodoro?.isBreak == true && pomodoro?.isRunning == true;
    final tracker = ref.read(readingActivityTrackerProvider);
    final document = documentState.value;
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

    useEffect(
      () => () => unawaited(projectionJob.cancel()),
      [projectionJob],
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
      final book = document?.book;
      if (book != null && document!.chapters.isNotEmpty) {
        chapterIndex.value = book.chapterIndex.clamp(
          0,
          document.chapters.length - 1,
        ).toInt();
        final locatorParts = book.locator?.split('|');
        final rawOffset = locatorParts?.length == 4 &&
                locatorParts?.first == 'text:v1'
            ? int.tryParse(locatorParts![2])
            : null;
        if (rawOffset != null) {
          final chapter = document.chapters[chapterIndex.value];
          final ratio = chapter.rawEnd <= chapter.rawStart
              ? 0.0
              : ((rawOffset - chapter.rawStart) /
                        (chapter.rawEnd - chapter.rawStart))
                    .clamp(0, 1)
                    .toDouble();
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
      return null;
    }, [lifecycle, breakActive]);

    Future<void> selectChapter(int index) async {
      final current = document;
      if (current == null || index < 0 || index >= current.chapters.length) {
        return;
      }
      chapterIndex.value = index;
      selectedContext.value = null;
      if (scrollController.hasClients) scrollController.jumpTo(0);
      final chapter = current.chapters[index];
      final progress = current.chapters.length <= 1
          ? 1.0
          : index / (current.chapters.length - 1);
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

    Future<void> searchIndexedContent() async {
      final chunk = await showDialog<ContentChunk>(
        context: context,
        builder: (context) => ContentSearchDialog(
          bookId: bookId,
          maxChapterIndex: null,
        ),
      );
      final current = document;
      if (chunk == null || current == null || !context.mounted) return;
      chapterIndex.value = chunk.chapterIndex
          .clamp(0, current.chapters.length - 1)
          .toInt();
      selectedContext.value = null;
      await ref.read(bookRepositoryProvider).updateReadingPosition(
        bookId: bookId,
        chapterIndex: chapterIndex.value,
        progress: current.chapters.length <= 1
            ? 0
            : chapterIndex.value / (current.chapters.length - 1),
        locator: chunk.locatorStart,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final chapter = current.chapters[chapterIndex.value];
        final ratio = chapter.rawEnd <= chapter.rawStart
            ? 0.0
            : ((chunk.rawStart - chapter.rawStart) /
                      (chapter.rawEnd - chapter.rawStart))
                  .clamp(0, 1)
                  .toDouble();
        if (scrollController.hasClients) {
          scrollController.jumpTo(
            scrollController.position.maxScrollExtent * ratio,
          );
        }
      });
    }

    Future<void> openReadingAssistant() async {
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
      final locatorParts = citation.locator.split('|');
      final rawOffset = locatorParts.length == 4 &&
              locatorParts.first == 'text:v1'
          ? int.tryParse(locatorParts[2])
          : null;
      final progress = current.chapters.length <= 1
          ? 0.0
          : nextIndex / (current.chapters.length - 1);
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
        scrollController.jumpTo(
          scrollController.position.maxScrollExtent * ratio,
        );
      });
    }

    Future<void> openVisualization() async {
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回书库',
          onPressed: onExitReader,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          PomodoroToolbarButton(bookId: bookId),
          IconButton(
            tooltip: '章节目录',
            onPressed: document == null
                ? null
                : () => openChapters(document.chapters),
            icon: const Icon(Icons.format_list_bulleted),
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
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => TextProjectionDialog(bookId: bookId),
            ),
            icon: const Icon(Icons.translate),
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
              final projection = projectionSnapshot.data;
              final content = projection?.rawText == rawContent
                  ? projection!.displayText
                  : rawContent;
              final textStyle = TextStyle(
                fontFamily: settings.font.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
              );
              return Column(
                children: [
                  if (projectionSnapshot.hasError)
                    MaterialBanner(
                      content: Text('显示转换失败，已回退原文：${projectionSnapshot.error}'),
                      actions: const [SizedBox.shrink()],
                    )
                  else if (projection?.hasAmbiguousRanges == true)
                    const MaterialBanner(
                      content: Text(
                        '本章含无法精确映射的转换区段；这些区段不会创建可回跳标注。',
                      ),
                      actions: [SizedBox.shrink()],
                    ),
                  Expanded(
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
                          child: value.book.format == 'markdown'
                              ? SelectionArea(
                                  child: MarkdownBody(
                                    data: content,
                                    styleSheet: MarkdownStyleSheet(
                                      p: textStyle,
                                      blockquote: textStyle,
                                      listBullet: textStyle,
                                    ),
                                  ),
                                )
                              : SelectableText(
                                  content,
                                  style: textStyle,
                                  onSelectionChanged: (selection, _) {
                                    if (selection.isCollapsed ||
                                        projection == null) {
                                      selectedContext.value = null;
                                      return;
                                    }
                                    final range = projection.displayToRaw(
                                      selection.start,
                                      selection.end,
                                    );
                                    if (!range.isExact) {
                                      selectedContext.value = null;
                                      return;
                                    }
                                    final rawStart = start + range.start;
                                    final rawEnd = start + range.end;
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
                              '${chapter.title} · ${index + 1}/${value.chapters.length}',
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
  }
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
