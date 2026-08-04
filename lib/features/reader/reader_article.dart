import 'package:flutter/material.dart';

import '../../domain/models/epub_manifest.dart';
import '../../domain/models/reader_chapter.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_coloring.dart';
import '../../domain/models/tts.dart';
import 'epub_webview.dart';
import 'reader_chrome.dart';
import 'reader_chrome_widgets.dart';
import 'reader_navigation_command.dart';

/// EPUB and fallback chapter surface. Stateful reader coordination remains in
/// [ReaderWorkspace]; this widget only renders the supplied chapter state.
class ReaderArticle extends StatelessWidget {
  const ReaderArticle({
    super.key,
    required this.settings,
    required this.textColoring,
    required this.controlsVisible,
    required this.chapter,
    required this.error,
    required this.bookId,
    required this.initialScrollRatio,
    required this.initialAnchor,
    required this.initialCfi,
    required this.direction,
    required this.navigationCommand,
    required this.restoreRevision,
    required this.annotations,
    required this.searchQuery,
    required this.focusedAnnotationId,
    required this.ttsSegment,
    required this.annotationFocusRevision,
    required this.onNavigateToHref,
    required this.onScrollPositionChanged,
    required this.onPaginationChanged,
    required this.onRequestPrevious,
    required this.onRequestNext,
    required this.onNavigationCommandFinished,
    required this.onAutoScrollChanged,
    required this.onTextSelectionChanged,
    required this.onSelectionContextMenu,
    required this.onToggleControls,
  });

  final ReadingSettings settings;
  final ResolvedTextColoring textColoring;
  final bool controlsVisible;
  final ReaderChapter? chapter;
  final Object? error;
  final String? bookId;
  final double initialScrollRatio;
  final String? initialAnchor;
  final String? initialCfi;
  final ReadingDirection direction;
  final ReaderNavigationCommand? navigationCommand;
  final int restoreRevision;
  final List<ReadingAnnotation> annotations;
  final String? searchQuery;
  final String? focusedAnnotationId;
  final TtsSegment? ttsSegment;
  final int annotationFocusRevision;
  final ValueChanged<String> onNavigateToHref;
  final void Function(
    String href,
    double ratio,
    String? anchor,
    String? cfi,
    int? chapterCharacterOffset,
    int? chapterCharacterCount,
  )
  onScrollPositionChanged;
  final void Function(int pageIndex, int pageCount) onPaginationChanged;
  final VoidCallback onRequestPrevious;
  final VoidCallback onRequestNext;
  final ValueChanged<int> onNavigationCommandFinished;
  final ValueChanged<bool> onAutoScrollChanged;
  final ValueChanged<ReaderTextSelection> onTextSelectionChanged;
  final ValueChanged<ReaderSelectionContextMenu> onSelectionContextMenu;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context) {
    if (chapter == null) {
      return ReaderContentTapDetector(
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
      return Builder(
        builder: (webViewContext) => EpubWebView(
          bookId: bookId!,
          href: chapter!.href,
          settings: settings,
          textColoring: textColoring,
          controlsVisible: controlsVisible,
          initialScrollRatio: initialScrollRatio,
          initialAnchor: initialAnchor,
          initialCfi: initialCfi,
          direction: direction,
          navigationCommand: navigationCommand,
          restoreRevision: restoreRevision,
          annotations: annotations,
          searchQuery: searchQuery,
          focusedAnnotationId: focusedAnnotationId,
          ttsHighlightHref: ttsSegment?.href,
          ttsHighlightText: ttsSegment?.text,
          ttsHighlightStart: ttsSegment?.rawStart,
          ttsHighlightEnd: ttsSegment?.rawEnd,
          annotationFocusRevision: annotationFocusRevision,
          onNavigateToHref: onNavigateToHref,
          onScrollPositionChanged: onScrollPositionChanged,
          onPaginationChanged: onPaginationChanged,
          onRequestPrevious: onRequestPrevious,
          onRequestNext: onRequestNext,
          onNavigationCommandFinished: onNavigationCommandFinished,
          onAutoScrollChanged: onAutoScrollChanged,
          onTextSelectionChanged: onTextSelectionChanged,
          onSelectionContextMenu: (menu) {
            final box = webViewContext.findRenderObject() as RenderBox?;
            final globalPosition = box?.localToGlobal(Offset(menu.x, menu.y));
            onSelectionContextMenu(
              ReaderSelectionContextMenu(
                selection: menu.selection,
                x: globalPosition?.dx ?? menu.x,
                y: globalPosition?.dy ?? menu.y,
              ),
            );
          },
          onToggleControls: onToggleControls,
        ),
      );
    }
    final blocks = chapter!.blocks;
    final titleBlock = blocks.where((block) => block.isHeading).firstOrNull;
    final bodyBlocks = titleBlock == null
        ? blocks
        : blocks.where((block) => !identical(block, titleBlock)).toList();
    return ReaderContentTapDetector(
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
                    return ReaderArticleColumn(
                      blocks: bodyBlocks,
                      settings: settings,
                    );
                  }
                  final splitAt = (bodyBlocks.length / 2).ceil();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ReaderArticleColumn(
                          blocks: bodyBlocks.take(splitAt).toList(),
                          settings: settings,
                        ),
                      ),
                      const SizedBox(width: 48),
                      Expanded(
                        child: ReaderArticleColumn(
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
