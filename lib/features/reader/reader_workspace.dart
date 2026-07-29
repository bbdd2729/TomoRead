import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reader_chapter.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_settings.dart';
import 'epub_webview.dart';

class ReaderWorkspace extends HookConsumerWidget {
  const ReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
    required this.readingSettings,
  });

  final String bookId;
  final String title;
  final ReadingSettings readingSettings;

  static double _scrollRatioFromLocator(String? locator, int chapterIndex) {
    final values = locator?.split(':');
    if (values == null || values.length != 2) return 0;
    if (int.tryParse(values.first) != chapterIndex) return 0;
    return (double.tryParse(values.last) ?? 0).clamp(0, 1).toDouble();
  }

  static String _locatorFor(int chapterIndex, double scrollRatio) =>
      '$chapterIndex:${scrollRatio.clamp(0, 1).toStringAsFixed(5)}';

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
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    final readerBook = ref.watch(readerBookProvider(bookId));
    final manifest = ref.watch(readerManifestProvider(bookId));
    final annotationsState = ref.watch(annotationsForBookProvider(bookId));
    final tocVisible = useState(true);
    final sidePanelVisible = useState(true);
    final showBookmarks = useState(false);
    final chapterIndex = useState(0);
    final scrollRatio = useState(0.0);
    final restoreRevision = useState(0);
    final progressWriteTimer = useRef<Timer?>(null);
    final selectedText = useState<ReaderTextSelection?>(null);
    final override = readingOverride.value;
    final bookmarkItems = bookmarks.value ?? const <Bookmark>[];
    final annotations = annotationsState.value ?? const <ReadingAnnotation>[];
    final settings = override?.settings ?? readingSettings;
    final totalChapters = manifest.value?.spine.length ?? 0;
    final activeChapterIndex = totalChapters == 0
        ? chapterIndex.value
        : chapterIndex.value.clamp(0, totalChapters - 1).toInt();
    final chapter = ref.watch(
      readerChapterProvider((bookId: bookId, chapterIndex: activeChapterIndex)),
    );
    final currentLocator = 'chapter-$activeChapterIndex:start';
    final chapterTitle =
        chapter.value?.title ?? '第 ${activeChapterIndex + 1} 章';
    final isLoading =
        readingOverride.isLoading || bookmarks.isLoading || chapter.isLoading;
    final isBookmarked = bookmarkItems.any(
      (bookmark) => bookmark.locator == currentLocator,
    );

    useEffect(() {
      final savedIndex = readerBook.value?.chapterIndex;
      if (savedIndex != null) {
        chapterIndex.value = savedIndex;
        scrollRatio.value = _scrollRatioFromLocator(
          readerBook.value?.locator,
          savedIndex,
        );
        restoreRevision.value++;
      }
      return null;
    }, [bookId, readerBook.value?.chapterIndex, readerBook.value?.locator]);

    useEffect(
      () =>
          () => progressWriteTimer.value?.cancel(),
      [bookId],
    );

    void scheduleProgressWrite({
      required int index,
      required double chapterRatio,
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
                locator: _locatorFor(index, chapterRatio),
              );
          if (context.mounted) ref.invalidate(libraryBooksProvider);
        },
      );
    }

    Future<void> selectChapter(int index) async {
      if (totalChapters == 0 || index < 0 || index >= totalChapters) return;
      progressWriteTimer.value?.cancel();
      chapterIndex.value = index;
      scrollRatio.value = 0;
      restoreRevision.value++;
      await ref
          .read(bookRepositoryProvider)
          .updateReadingPosition(
            bookId: bookId,
            chapterIndex: index,
            progress: _overallProgress(index, 0, totalChapters),
            locator: _locatorFor(index, 0),
          );
      ref.invalidate(libraryBooksProvider);
    }

    Future<void> toggleBookmark() async {
      final repository = ref.read(bookmarkRepositoryProvider);
      final existing = bookmarkItems
          .where((bookmark) => bookmark.locator == currentLocator)
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowPanels = constraints.maxWidth >= 980;
        final showToc = canShowPanels && tocVisible.value;
        final showSidePanel = canShowPanels && sidePanelVisible.value;
        return Column(
          children: [
            _ReaderToolbar(
              title: title,
              tocVisible: tocVisible.value,
              sidePanelVisible: sidePanelVisible.value,
              bookmarked: isBookmarked,
              canCreateAnnotation:
                  selectedText.value?.href == chapter.value?.href,
              onToggleToc: () => tocVisible.value = !tocVisible.value,
              onToggleSidePanel: () =>
                  sidePanelVisible.value = !sidePanelVisible.value,
              onToggleBookmark: toggleBookmark,
              onCreateAnnotation: createAnnotation,
              onOpenBookSettings: openBookSettings,
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Material(
                      child: Row(
                        children: [
                          if (showToc)
                            SizedBox(
                              width: 260,
                              child: _ReaderTocPanel(
                                toc: manifest.value?.toc ?? const [],
                                activeChapterIndex: activeChapterIndex,
                                onSelected: selectChapter,
                              ),
                            ),
                          if (showToc) const VerticalDivider(width: 1),
                          Expanded(
                            child: _ReaderArticle(
                              settings: settings,
                              chapter: chapter.value,
                              error: chapter.error,
                              bookId: readerBook.value == null ? null : bookId,
                              initialScrollRatio: scrollRatio.value,
                              annotations: annotations,
                              restoreRevision: restoreRevision.value,
                              onNavigateToHref: (href) {
                                final nextIndex = manifest.value?.spine
                                    .indexWhere((item) => item.href == href);
                                if (nextIndex != null && nextIndex >= 0) {
                                  selectChapter(nextIndex);
                                }
                              },
                              onScrollPositionChanged: (href, ratio) {
                                if (href != chapter.value?.href) return;
                                final clampedRatio = ratio
                                    .clamp(0, 1)
                                    .toDouble();
                                scrollRatio.value = clampedRatio;
                                scheduleProgressWrite(
                                  index: activeChapterIndex,
                                  chapterRatio: clampedRatio,
                                );
                              },
                              onTextSelectionChanged: (selection) {
                                if (selection.href == chapter.value?.href) {
                                  selectedText.value = selection;
                                }
                              },
                            ),
                          ),
                          if (showSidePanel) const VerticalDivider(width: 1),
                          if (showSidePanel)
                            SizedBox(
                              width: 280,
                              child: _ReaderSidePanel(
                                showBookmarks: showBookmarks.value,
                                bookmarks: bookmarkItems,
                                annotations: annotations,
                                onPanelChanged: (value) =>
                                    showBookmarks.value = value,
                                onRemoveAnnotation: (annotation) async {
                                  await ref
                                      .read(annotationRepositoryProvider)
                                      .remove(annotation.id);
                                  ref.invalidate(
                                    annotationsForBookProvider(bookId),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            _ReaderFooter(
              chapterIndex: activeChapterIndex,
              chapterCount: totalChapters,
              onPrevious: activeChapterIndex > 0
                  ? () => selectChapter(activeChapterIndex - 1)
                  : null,
              onNext:
                  totalChapters > 0 && activeChapterIndex < totalChapters - 1
                  ? () => selectChapter(activeChapterIndex + 1)
                  : null,
            ),
          ],
        );
      },
    );
  }
}

class _ReaderToolbar extends StatelessWidget {
  const _ReaderToolbar({
    required this.title,
    required this.tocVisible,
    required this.sidePanelVisible,
    required this.bookmarked,
    required this.canCreateAnnotation,
    required this.onToggleToc,
    required this.onToggleSidePanel,
    required this.onToggleBookmark,
    required this.onCreateAnnotation,
    required this.onOpenBookSettings,
  });

  final String title;
  final bool tocVisible;
  final bool sidePanelVisible;
  final bool bookmarked;
  final bool canCreateAnnotation;
  final VoidCallback onToggleToc;
  final VoidCallback onToggleSidePanel;
  final VoidCallback onToggleBookmark;
  final VoidCallback onCreateAnnotation;
  final VoidCallback onOpenBookSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: tocVisible ? '隐藏目录' : '显示目录',
              onPressed: onToggleToc,
              key: const Key('reader-toc'),
              icon: Icon(
                tocVisible ? Icons.format_list_bulleted : Icons.menu_open,
              ),
            ),
            IconButton(
              tooltip: sidePanelVisible ? '隐藏笔记面板' : '显示笔记面板',
              onPressed: onToggleSidePanel,
              key: const Key('reader-side-panel'),
              icon: const Icon(Icons.sticky_note_2_outlined),
            ),
            IconButton(
              tooltip: bookmarked ? '移除书签' : '添加书签',
              onPressed: onToggleBookmark,
              key: const Key('reader-bookmark'),
              icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
            ),
            IconButton(
              tooltip: canCreateAnnotation ? '高亮或添加笔记' : '请先选择文本',
              onPressed: canCreateAnnotation ? onCreateAnnotation : null,
              icon: const Icon(Icons.highlight_alt_outlined),
            ),
            const Spacer(),
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
            const Spacer(),
            IconButton(
              tooltip: '本书阅读设置',
              onPressed: onOpenBookSettings,
              key: const Key('reader-book-settings'),
              icon: const Icon(Icons.format_size),
            ),
            IconButton(
              tooltip: '搜索书内内容',
              onPressed: () {},
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderTocPanel extends StatelessWidget {
  const _ReaderTocPanel({
    required this.toc,
    required this.activeChapterIndex,
    required this.onSelected,
  });

  final List<EpubTocItem> toc;
  final int activeChapterIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('目录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (toc.isEmpty) const Text('该书没有可用目录。') else ..._buildTocItems(toc),
      ],
    );
  }

  List<Widget> _buildTocItems(List<EpubTocItem> items, [int depth = 0]) {
    return [
      for (final item in items) ...[
        ListTile(
          contentPadding: EdgeInsets.only(left: depth * 16.0),
          enabled: item.spineIndex >= 0,
          selected: item.spineIndex == activeChapterIndex,
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: item.spineIndex < 0 ? null : () => onSelected(item.spineIndex),
        ),
        ..._buildTocItems(item.children, depth + 1),
      ],
    ];
  }
}

class _ReaderArticle extends StatelessWidget {
  const _ReaderArticle({
    required this.settings,
    required this.chapter,
    required this.error,
    required this.bookId,
    required this.initialScrollRatio,
    required this.restoreRevision,
    required this.annotations,
    required this.onNavigateToHref,
    required this.onScrollPositionChanged,
    required this.onTextSelectionChanged,
  });

  final ReadingSettings settings;
  final ReaderChapter? chapter;
  final Object? error;
  final String? bookId;
  final double initialScrollRatio;
  final int restoreRevision;
  final List<ReadingAnnotation> annotations;
  final ValueChanged<String> onNavigateToHref;
  final void Function(String href, double ratio) onScrollPositionChanged;
  final ValueChanged<ReaderTextSelection> onTextSelectionChanged;

  @override
  Widget build(BuildContext context) {
    if (chapter == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error == null ? '正在加载章节…' : '无法加载章节：$error'),
        ),
      );
    }
    if (bookId != null) {
      return EpubWebView(
        bookId: bookId!,
        href: chapter!.href,
        settings: settings,
        initialScrollRatio: initialScrollRatio,
        restoreRevision: restoreRevision,
        annotations: annotations,
        onNavigateToHref: onNavigateToHref,
        onScrollPositionChanged: onScrollPositionChanged,
        onTextSelectionChanged: onTextSelectionChanged,
      );
    }
    final blocks = chapter!.blocks;
    final titleBlock = blocks.where((block) => block.isHeading).firstOrNull;
    final bodyBlocks = titleBlock == null
        ? blocks
        : blocks.where((block) => !identical(block, titleBlock)).toList();
    return Center(
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
                  return _ArticleColumn(blocks: bodyBlocks, settings: settings);
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
    );
  }
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
    required this.onRemoveAnnotation,
  });

  final bool showBookmarks;
  final List<Bookmark> bookmarks;
  final List<ReadingAnnotation> annotations;
  final ValueChanged<bool> onPanelChanged;
  final Future<void> Function(ReadingAnnotation annotation) onRemoveAnnotation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.sticky_note_2_outlined),
                label: Text('笔记'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.bookmark_border),
                label: Text('书签'),
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
                      trailing: IconButton(
                        tooltip: '删除标注',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onRemoveAnnotation(annotation),
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

class _AnnotationDraft {
  const _AnnotationDraft({required this.color, this.note});

  final AnnotationColor color;
  final String? note;
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
    required this.onPrevious,
    required this.onNext,
  });

  final int chapterIndex;
  final int chapterCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final progress = chapterCount == 0
        ? 0.0
        : (chapterIndex + 1) / chapterCount;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Row(
          children: [
            IconButton(
              tooltip: '上一章',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 8),
            Expanded(child: LinearProgressIndicator(value: progress)),
            const SizedBox(width: 12),
            Text(
              chapterCount == 0
                  ? '正在读取目录'
                  : '${(progress * 100).round()}% · ${chapterIndex + 1} / $chapterCount',
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '下一章',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
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
