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
    super.key,
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
          title: 'قراءة المزيد من الإجراءات',
          groups: [
            ReaderChromeActionGroup(
              title: 'يبحث...',
              actions: [
                ReaderChromeAction(
                  id: 'notes',
                  key: const Key('reader-side-panel'),
                  label: 'الإشارات المرجعية والملاحظات',
                  icon: Icons.sticky_note_2_outlined,
                  onPressed: onToggleSidePanel,
                ),
                ReaderChromeAction(
                  id: 'bookmark',
                  key: const Key('reader-bookmark'),
                  label: bookmarked ? 'إزالة الإشارة المرجعية' : 'أضف علامة',
                  icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  onPressed: onToggleBookmark,
                ),
                ReaderChromeAction(
                  id: 'search',
                  label: 'البحث في محتويات الكتاب',
                  icon: Icons.search,
                  onPressed: onOpenSearch,
                ),
                ReaderChromeAction(
                  id: 'annotation',
                  label: 'تمييز أو إضافة ملاحظات',
                  icon: Icons.highlight_alt_outlined,
                  onPressed: canCreateAnnotation ? onCreateAnnotation : null,
                  disabledDescription: 'يرجى تحديد النص أولاً',
                ),
              ],
            ),
            ReaderChromeActionGroup(
              title: 'القراءة',
              actions: [
                ReaderChromeAction(
                  id: 'tts',
                  label: 'النظام يتحدث',
                  icon: Icons.headphones_outlined,
                  onPressed: () {
                    if (autoScrollActive) onToggleAutoScroll();
                    unawaited(showTtsControls(context, ttsController));
                  },
                ),
                ReaderChromeAction(
                  id: 'auto-scroll',
                  label: autoScrollActive ? 'إيقاف التمرير التلقائي' : 'ابدأ التمرير التلقائي',
                  icon: autoScrollActive
                      ? Icons.pause_circle_outline
                      : Icons.slow_motion_video_outlined,
                  onPressed: canAutoScroll ? onToggleAutoScroll : null,
                  disabledDescription: 'يدعم التمرير التلقائي تخطيط التمرير فقط',
                  selected: autoScrollActive,
                ),
                ReaderChromeAction(
                  id: 'pomodoro',
                  label: 'قراءة توقيت التركيز',
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
                  label: 'إخفاء عناصر التحكم في القراءة',
                  icon: Icons.center_focus_strong_outlined,
                  onPressed: onHideControls,
                ),
              ],
            ),
            ReaderChromeActionGroup(
              title: 'الأدوات الذكية',
              actions: [
                ReaderChromeAction(
                  id: 'assistant',
                  label: 'مساعد قراءة',
                  icon: Icons.auto_awesome_outlined,
                  onPressed: onOpenAssistant,
                ),
                ReaderChromeAction(
                  id: 'visualization',
                  label: 'سحابة الكلمات والخرائط الذهنية',
                  icon: Icons.account_tree_outlined,
                  onPressed: onOpenVisualization,
                ),
              ],
            ),
            ReaderChromeActionGroup(
              title: 'الإعدادات',
              actions: [
                ReaderChromeAction(
                  id: 'book-settings',
                  key: const Key('reader-book-settings'),
                  label: 'إعدادات قراءة الكتاب',
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
                tooltip: 'العودة إلى المكتبة',
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
                tooltip: bookmarked ? 'إزالة الإشارة المرجعية' : 'أضف علامة',
                icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
                onPressed: onToggleBookmark,
              ),
              const SizedBox(width: ReaderChromeLayout.actionGap),
              ReaderChromeIconButton(
                tooltip: 'البحث في محتويات الكتاب',
                icon: Icons.search,
                onPressed: onOpenSearch,
              ),
              const SizedBox(width: ReaderChromeLayout.actionGap),
              ReaderChromeIconButton(
                key: const Key('reader-mobile-more'),
                tooltip: 'قراءة المزيد من الإجراءات',
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
              tooltip: 'العودة إلى المكتبة',
              onPressed: onExitReader,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: mobileReaderControls
                  ? 'فتح الدليل'
                  : tocVisible
                  ? 'إخفاء الكتالوج'
                  : 'عرض جدول المحتويات',
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
                  ? 'فتح الإشارات المرجعية والملاحظات'
                  : sidePanelVisible
                  ? 'إخفاء لوحة الملاحظات'
                  : 'عرض لوحة الملاحظات',
              onPressed: onToggleSidePanel,
              key: const Key('reader-side-panel'),
              icon: const Icon(Icons.sticky_note_2_outlined),
            ),
            if (!mobileReaderControls) const VerticalDivider(width: 20),
            IconButton(
              tooltip: bookmarked ? 'إزالة الإشارة المرجعية' : 'أضف علامة',
              onPressed: onToggleBookmark,
              key: const Key('reader-bookmark'),
              icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
            ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: canCreateAnnotation ? 'تمييز أو إضافة ملاحظات' : 'يرجى تحديد النص أولاً',
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
                        ? 'إيقاف التمرير التلقائي'
                        : 'ابدأ التمرير التلقائي'
                  : 'يدعم التمرير التلقائي تخطيط التمرير فقط',
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
                tooltip: 'البحث في محتويات الكتاب',
                onPressed: onOpenSearch,
                icon: const Icon(Icons.search),
              ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: 'مساعد قراءة',
                onPressed: onOpenAssistant,
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: 'سحابة الكلمات والخرائط الذهنية',
                onPressed: onOpenVisualization,
                icon: const Icon(Icons.account_tree_outlined),
              ),
            if (!mobileReaderControls) const VerticalDivider(width: 20),
            if (!mobileReaderControls)
              IconButton(
                tooltip: 'إعدادات قراءة الكتاب',
                onPressed: onOpenBookSettings,
                key: const Key('reader-book-settings'),
                icon: const Icon(Icons.format_size),
              ),
            if (!mobileReaderControls)
              IconButton(
                tooltip: 'إخفاء عناصر التحكم في القراءة',
                key: const Key('reader-focus-mode'),
                onPressed: onHideControls,
                icon: const Icon(Icons.center_focus_strong_outlined),
              ),
            if (mobileReaderControls)
              PopupMenuButton<_MobileReaderToolbarAction>(
                key: const Key('reader-mobile-more'),
                tooltip: 'المزيد من عناصر التحكم في القراءة',
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
                      title: Text('البحث في محتويات الكتاب'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.assistant,
                    child: ListTile(
                      leading: Icon(Icons.auto_awesome_outlined),
                      title: Text('مساعد قراءة'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.visualization,
                    child: ListTile(
                      leading: Icon(Icons.account_tree_outlined),
                      title: Text('سحابة الكلمات والخرائط الذهنية'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.settings,
                    child: ListTile(
                      leading: Icon(Icons.format_size),
                      title: Text('إعدادات قراءة الكتاب'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MobileReaderToolbarAction.pomodoro,
                    child: ListTile(
                      leading: Icon(Icons.timer_outlined),
                      title: Text('قراءة توقيت التركيز'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MobileReaderToolbarAction.focus,
                    child: ListTile(
                      leading: Icon(Icons.center_focus_strong_outlined),
                      title: Text('إخفاء عناصر التحكم في القراءة'),
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
