import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reading_settings.dart';

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

  static const _currentLocator = 'chapter-2:start';
  static const _chapterTitle = '第二章 阅读的层次';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingOverride = ref.watch(bookReadingOverrideProvider(bookId));
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    final tocVisible = useState(true);
    final sidePanelVisible = useState(true);
    final showBookmarks = useState(false);
    final override = readingOverride.value;
    final bookmarkItems = bookmarks.value ?? const <Bookmark>[];
    final settings = override?.settings ?? readingSettings;
    final isLoading = readingOverride.isLoading || bookmarks.isLoading;
    final isBookmarked = bookmarkItems.any(
      (bookmark) => bookmark.locator == _currentLocator,
    );

    Future<void> toggleBookmark() async {
      final repository = ref.read(bookmarkRepositoryProvider);
      final existing = bookmarkItems
          .where((bookmark) => bookmark.locator == _currentLocator)
          .firstOrNull;
      if (existing != null) {
        await repository.remove(existing.id);
      } else {
        await repository.add(
          bookId: bookId,
          locator: _currentLocator,
          chapterTitle: _chapterTitle,
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
              onToggleToc: () => tocVisible.value = !tocVisible.value,
              onToggleSidePanel: () =>
                  sidePanelVisible.value = !sidePanelVisible.value,
              onToggleBookmark: toggleBookmark,
              onOpenBookSettings: openBookSettings,
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Material(
                      child: Row(
                        children: [
                          if (showToc)
                            const SizedBox(
                              width: 260,
                              child: _ReaderTocPanel(),
                            ),
                          if (showToc) const VerticalDivider(width: 1),
                          Expanded(child: _ReaderArticle(settings: settings)),
                          if (showSidePanel) const VerticalDivider(width: 1),
                          if (showSidePanel)
                            SizedBox(
                              width: 280,
                              child: _ReaderSidePanel(
                                showBookmarks: showBookmarks.value,
                                bookmarks: bookmarkItems,
                                onPanelChanged: (value) =>
                                    showBookmarks.value = value,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            const _ReaderFooter(),
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
    required this.onToggleToc,
    required this.onToggleSidePanel,
    required this.onToggleBookmark,
    required this.onOpenBookSettings,
  });

  final String title;
  final bool tocVisible;
  final bool sidePanelVisible;
  final bool bookmarked;
  final VoidCallback onToggleToc;
  final VoidCallback onToggleSidePanel;
  final VoidCallback onToggleBookmark;
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
  const _ReaderTocPanel();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('目录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...const [
          '序言',
          '第一章 阅读的活力与艺术',
          '第二章 阅读的层次',
          '第三章 基础阅读',
          '第四章 检视阅读',
        ].map(
          (chapter) => ListTile(
            contentPadding: EdgeInsets.zero,
            selected: chapter.startsWith('第二章'),
            title: Text(chapter),
          ),
        ),
      ],
    );
  }
}

class _ReaderArticle extends StatelessWidget {
  const _ReaderArticle({required this.settings});

  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) {
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
            Text('第二章', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              '阅读的层次',
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
                    paragraphs: _articleText,
                    settings: settings,
                  );
                }
                final splitAt = (_articleText.length / 2).ceil();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ArticleColumn(
                        paragraphs: _articleText.take(splitAt).toList(),
                        settings: settings,
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      child: _ArticleColumn(
                        paragraphs: _articleText.skip(splitAt).toList(),
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
  const _ArticleColumn({required this.paragraphs, required this.settings});

  final List<String> paragraphs;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: paragraphs
        .map(
          (paragraph) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              paragraph,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontFamily: settings.font.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
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
    required this.onPanelChanged,
  });

  final bool showBookmarks;
  final List<Bookmark> bookmarks;
  final ValueChanged<bool> onPanelChanged;

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
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 8, backgroundColor: Colors.amber),
              title: Text('真正的阅读是一种主动的工作。'),
              subtitle: Text('第二章 · 位置 38%'),
            ),
            const Divider(),
            Text(
              '选中文本后可创建高亮和笔记。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReaderFooter extends StatelessWidget {
  const _ReaderFooter();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Row(
          children: [
            IconButton(
              tooltip: '上一页',
              onPressed: () {},
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 8),
            const Expanded(child: LinearProgressIndicator(value: .38)),
            const SizedBox(width: 12),
            const Text('38% · 16 / 264'),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '下一页',
              onPressed: () {},
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

const _articleText = [
  '有些人把阅读视为消遣，有些人把它当作获取资讯的手段。但真正的阅读，始终是一种主动的工作。读者并不是被动地接收文字，而是在作者的引导下不断提问、判断与回应。',
  '我们可以把阅读分成不同层次。每一个层次都建立在前一个层次之上，并带来更完整的理解。读得更多并不必然意味着读得更好，关键在于你是否能用恰当的方法，面对眼前这本书。',
  '最基础的阅读，帮助我们辨认文字与理解句子；检视阅读则让我们在有限时间内掌握一本书的轮廓。更进一步的分析阅读，要求读者和作者进行一场耐心而严肃的对话。',
  '当你发现某个观点值得停留，不妨划下一段文字，写下当时的疑问。一本读过、思考过、留下痕迹的书，会逐渐成为你自己的书。',
];
