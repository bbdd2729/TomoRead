import 'dart:async';

import 'package:flutter/material.dart';

import 'pomodoro_widgets.dart';
import 'reader_chrome.dart';
import 'tts_controller.dart';
import 'tts_controls.dart';

enum _MobileReaderToolbarAction {
  search,
  assistant,
  visualization,
  settings,
  pomodoro,
  focus,
}

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    required this.title,
    required this.contextLabel,
    required this.tocVisible,
    required this.sidePanelVisible,
    required this.chromeLayout,
    required this.usesOverflowActions,
    required this.bookmarked,
    required this.canCreateAnnotation,
    required this.autoScrollActive,
    required this.canAutoScroll,
    required this.onToggleToc,
    required this.onToggleSidePanel,
    required this.onExitReader,
    required this.onHideControls,
    required this.onToggleBookmark,
    required this.onCreateAnnotation,
    required this.onOpenBookSettings,
    required this.onOpenSearch,
    required this.onOpenAssistant,
    required this.onOpenVisualization,
    required this.onToggleAutoScroll,
    required this.ttsController,
    required this.bookId,
  });

  final String title;
  final String contextLabel;
  final bool tocVisible;
  final bool sidePanelVisible;
  final ReaderChromeLayout chromeLayout;
  final bool usesOverflowActions;
  bool get mobileReaderControls => chromeLayout.isMedium;
  final bool bookmarked;
  final bool canCreateAnnotation;
  final bool autoScrollActive;
  final bool canAutoScroll;
  final VoidCallback onToggleToc;
  final VoidCallback onToggleSidePanel;
  final VoidCallback onExitReader;
  final VoidCallback onHideControls;
  final VoidCallback onToggleBookmark;
  final VoidCallback onCreateAnnotation;
  final VoidCallback onOpenBookSettings;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenVisualization;
  final VoidCallback onToggleAutoScroll;
  final TtsPlaybackController ttsController;
  final String bookId;

  @override
  Widget build(BuildContext context) {
    void openMoreSheet() {
      unawaited(
        showReaderMoreSheet(
          context,
          title: '更多阅读操作',
          groups: [
            ReaderChromeActionGroup(
              title: '查阅',
              actions: [
                ReaderChromeAction(
                  id: 'notes',
                  key: const Key('reader-side-panel'),
                  label: '书签与笔记',
                  icon: Icons.sticky_note_2_outlined,
                  onPressed: onToggleSidePanel,
                ),
                ReaderChromeAction(
                  id: 'bookmark',
                  key: const Key('reader-bookmark'),
                  label: bookmarked ? '移除书签' : '添加书签',
                  icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  onPressed: onToggleBookmark,
                ),
                ReaderChromeAction(
                  id: 'search',
                  label: '搜索书内内容',
                  icon: Icons.search,
                  onPressed: onOpenSearch,
                ),
                ReaderChromeAction(
                  id: 'annotation',
                  label: '高亮或添加笔记',
                  icon: Icons.highlight_alt_outlined,
                  onPressed: canCreateAnnotation ? onCreateAnnotation : null,
                  disabledDescription: '请先选择文本',
                ),
              ],
            ),
            ReaderChromeActionGroup(
              title: '阅读',
              actions: [
                ReaderChromeAction(
                  id: 'tts',
                  label: '系统朗读',
                  icon: Icons.headphones_outlined,
                  onPressed: () {
                    if (autoScrollActive) onToggleAutoScroll();
                    unawaited(showTtsControls(context, ttsController));
                  },
                ),
                ReaderChromeAction(
                  id: 'auto-scroll',
                  label: autoScrollActive ? '停止自动滚动' : '开始自动滚动',
                  icon: autoScrollActive
                      ? Icons.pause_circle_outline
                      : Icons.slow_motion_video_outlined,
                  onPressed: canAutoScroll ? onToggleAutoScroll : null,
                  disabledDescription: '自动滚动仅支持滚动布局',
                  selected: autoScrollActive,
                ),
                ReaderChromeAction(
                  id: 'pomodoro',
                  label: '阅读专注计时',
                  icon: Icons.timer_outlined,
                  onPressed: () {
                    if (autoScrollActive) onToggleAutoScroll();
                    unawaited(
                      showDialog<void>(
                        context: context,
                        builder: (context) => PomodoroDialog(bookId: bookId),
                      ),
                    );
                  },
                ),
                ReaderChromeAction(
                  id: 'focus',
                  label: '隐藏阅读控制',
                  icon: Icons.center_focus_strong_outlined,
                  onPressed: onHideControls,
                ),
              ],
            ),
            ReaderChromeActionGroup(
              title: '智能工具',
              actions: [
                ReaderChromeAction(
                  id: 'assistant',
                  label: '阅读助手',
                  icon: Icons.auto_awesome_outlined,
                  onPressed: onOpenAssistant,
                ),
                ReaderChromeAction(
                  id: 'visualization',
                  label: '词云与思维导图',
                  icon: Icons.account_tree_outlined,
                  onPressed: onOpenVisualization,
                ),
              ],
            ),
            ReaderChromeActionGroup(
              title: '设置',
              actions: [
                ReaderChromeAction(
                  id: 'book-settings',
                  key: const Key('reader-book-settings'),
                  label: '本书阅读设置',
                  icon: Icons.format_size,
                  onPressed: onOpenBookSettings,
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (chromeLayout.isCompact) {
      return ReaderCompactTopBar(
        title: title,
        contextLabel: contextLabel,
        onBack: onExitReader,
        onOpenMore: openMoreSheet,
        backKey: const Key('reader-back'),
        moreKey: const Key('reader-mobile-more'),
      );
    }

    if (usesOverflowActions) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ReaderChromeIconButton(
                key: const Key('reader-back'),
                tooltip: '返回书库',
                icon: Icons.arrow_back,
                onPressed: onExitReader,
              ),
              const SizedBox(width: ReaderChromeLayout.actionGap),
              Expanded(
                child: Semantics(
                  header: true,
                  label: '$title，$contextLabel',
                  child: Text(
                    '$title · $contextLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: ReaderChromeLayout.actionGap),
              ReaderChromeIconButton(
                key: const Key('reader-bookmark'),
                tooltip: bookmarked ? '移除书签' : '添加书签',
                icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
                onPressed: onToggleBookmark,
              ),
              const SizedBox(width: ReaderChromeLayout.actionGap),
              ReaderChromeIconButton(
                tooltip: '搜索书内内容',
                icon: Icons.search,
                onPressed: onOpenSearch,
              ),
              const SizedBox(width: ReaderChromeLayout.actionGap),
              ReaderChromeIconButton(
                key: const Key('reader-mobile-more'),
                tooltip: '更多阅读操作',
                icon: Icons.more_vert,
                onPressed: openMoreSheet,
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
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
            TtsToolbarButton(
              controller: ttsController,
              onBeforeOpen: autoScrollActive ? onToggleAutoScroll : null,
            ),
            IconButton(
              key: const Key('reader-auto-scroll'),
              tooltip: canAutoScroll
                  ? autoScrollActive
                        ? '停止自动滚动'
                        : '开始自动滚动'
                  : '自动滚动仅支持滚动布局',
              onPressed: canAutoScroll ? onToggleAutoScroll : null,
              isSelected: autoScrollActive,
              icon: Icon(
                autoScrollActive
                    ? Icons.pause_circle_outline
                    : Icons.slow_motion_video_outlined,
              ),
            ),
            if (!mobileReaderControls)
              PomodoroToolbarButton(
                bookId: bookId,
                onOpen: autoScrollActive ? onToggleAutoScroll : null,
              ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: '搜索书内内容',
                onPressed: onOpenSearch,
                icon: const Icon(Icons.search),
              ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: '阅读助手',
                onPressed: onOpenAssistant,
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: '词云与思维导图',
                onPressed: onOpenVisualization,
                icon: const Icon(Icons.account_tree_outlined),
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
                onSelected: (action) {
                  switch (action) {
                    case _MobileReaderToolbarAction.search:
                      onOpenSearch();
                    case _MobileReaderToolbarAction.assistant:
                      onOpenAssistant();
                    case _MobileReaderToolbarAction.visualization:
                      onOpenVisualization();
                    case _MobileReaderToolbarAction.settings:
                      onOpenBookSettings();
                    case _MobileReaderToolbarAction.pomodoro:
                      if (autoScrollActive) onToggleAutoScroll();
                      unawaited(
                        showDialog<void>(
                          context: context,
                          builder: (context) => PomodoroDialog(bookId: bookId),
                        ),
                      );
                    case _MobileReaderToolbarAction.focus:
                      onHideControls();
                  }
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
                    value: _MobileReaderToolbarAction.assistant,
                    child: ListTile(
                      leading: Icon(Icons.auto_awesome_outlined),
                      title: Text('阅读助手'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.visualization,
                    child: ListTile(
                      leading: Icon(Icons.account_tree_outlined),
                      title: Text('词云与思维导图'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.settings,
                    child: ListTile(
                      leading: Icon(Icons.format_size),
                      title: Text('本书阅读设置'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.pomodoro,
                    child: ListTile(
                      leading: Icon(Icons.timer_outlined),
                      title: Text('阅读专注计时'),
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
