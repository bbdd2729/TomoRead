import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/text_decoder_service.dart';
import '../../domain/models/pomodoro.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reading_activity.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_chapter.dart';
import 'pomodoro_controller.dart';
import 'pomodoro_widgets.dart';
import '../text_import/text_content_controller.dart';

enum _TextChapterAction { rename, split, mergeNext }

class TextReaderWorkspace extends HookConsumerWidget {
  const TextReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
    required this.readingSettings,
    required this.onExitReader,
  });

  final String bookId;
  final String title;
  final ReadingSettings readingSettings;
  final VoidCallback onExitReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentState = ref.watch(textBookDocumentProvider(bookId));
    final readingOverride = ref.watch(bookReadingOverrideProvider(bookId)).value;
    final settings = readingOverride?.settings ?? readingSettings;
    final chapterIndex = useState(0);
    final lifecycle = useAppLifecycleState();
    final pomodoro = ref.watch(pomodoroControllerProvider).value;
    final breakActive = pomodoro?.isBreak == true && pomodoro?.isRunning == true;
    final tracker = ref.read(readingActivityTrackerProvider);
    final document = documentState.value;

    useEffect(() {
      final book = document?.book;
      if (book != null && document!.chapters.isNotEmpty) {
        chapterIndex.value = book.chapterIndex.clamp(
          0,
          document.chapters.length - 1,
        ).toInt();
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
    }, [bookId, document?.book.id]);

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
            tooltip: '编辑章节',
            onPressed: document == null ? null : editCurrentChapter,
            icon: const Icon(Icons.edit_note),
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
              final content = value.rawText.substring(start, end);
              final textStyle = TextStyle(
                fontFamily: settings.font.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
              );
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
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
                              : SelectableText(content, style: textStyle),
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
