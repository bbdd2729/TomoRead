import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/providers.dart';
import '../../data/services/pdf_selection_locator_service.dart';
import '../../data/services/pdf_text_selection_bridge.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/document_locator.dart';
import '../../domain/models/reading_activity.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_position_metrics.dart';
import '../chat/chat_controller.dart';
import '../notes/notes_providers.dart';
import 'pdf_annotation_widgets.dart';
import 'pdf_bookmarks_dialog.dart';
import 'pdf_navigation_dialog.dart';
import 'pdf_search_dialog.dart';

void _noopPdfReaderAction() {}

enum _PdfSelectionAction {
  highlight,
  underline,
  note,
  askAi,
  explainAi,
  summarizeAi,
}

enum _PdfToolbarAction {
  bookmarks,
  navigation,
  search,
  selectionHelp,
  annotations,
  focus,
}

class PdfReaderWorkspace extends HookConsumerWidget {
  const PdfReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
    this.onExitReader = _noopPdfReaderAction,
    this.onOpenChat = _noopPdfReaderAction,
  });

  final String bookId;
  final String title;
  final VoidCallback onExitReader;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookState = ref.watch(readerBookProvider(bookId));
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    final annotations = ref.watch(annotationsForBookProvider(bookId));
    final currentPage = useState<int?>(null);
    final viewerController = useMemoized(PdfViewerController.new);
    final selectionBridge = useMemoized(PdfTextSelectionBridge.new);
    final textSearcher = useState<PdfTextSearcher?>(null);
    final pdfDocument = useState<PdfDocument?>(null);
    final verifiedAnnotations = useState(const <ReadingAnnotation>[]);
    final pendingNavigationLocator = useState<PdfDocumentLocator?>(null);
    final outline = useState(const <PdfOutlineNode>[]);
    final outlineLoading = useState(false);
    final outlineError = useState<Object?>(null);
    final controlsVisible = useState(false);
    final activityTracker = ref.read(readingActivityTrackerProvider);
    final lifecycleState = useAppLifecycleState();

    void toggleControls() => controlsVisible.value = !controlsVisible.value;

    useEffect(() {
      return () => textSearcher.value?.dispose();
    }, [viewerController]);

    useEffect(() {
      final book = bookState.value;
      if (book == null) return null;
      activityTracker.open(
        ReaderIdentity(bookId: bookId, format: ReaderFormat.pdf),
        ReaderPosition(progress: book.progress, locator: book.locator),
      );
      return () {
        unawaited(activityTracker.close());
      };
    }, [bookId, bookState.value?.id]);

    useEffect(() {
      activityTracker.setForeground(
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed,
      );
      return null;
    }, [lifecycleState]);

    useEffect(() {
      final locator = PdfDocumentLocator.tryParse(bookState.value?.locator);
      pendingNavigationLocator.value =
          locator?.precision == DocumentLocatorPrecision.exact ? locator : null;
      return null;
    }, [bookState.value?.id, bookState.value?.locator]);

    useEffect(() {
      final document = pdfDocument.value;
      final source = annotations.value;
      var active = true;
      if (document == null || source == null) {
        verifiedAnnotations.value = const [];
        if (viewerController.isReady) viewerController.invalidate();
        return () => active = false;
      }
      unawaited(() async {
        final next = await selectionBridge.verifyAnnotations(document, source);
        if (active && context.mounted) {
          verifiedAnnotations.value = next;
          if (viewerController.isReady) viewerController.invalidate();
        }
      }());
      return () => active = false;
    }, [annotations.value, pdfDocument.value, selectionBridge]);

    Future<void> loadOutline(PdfDocument document) async {
      outlineLoading.value = true;
      outlineError.value = null;
      try {
        final loadedOutline = await document.loadOutline();
        if (!context.mounted) return;
        outline.value = loadedOutline;
      } catch (error) {
        if (!context.mounted) return;
        outlineError.value = error;
      } finally {
        if (context.mounted) outlineLoading.value = false;
      }
    }

    return bookState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('无法加载 PDF：$error')),
      data: (book) {
        if (book == null) return const Center(child: Text('找不到 PDF 书籍。'));
        final pageCount = book.chapterCount;
        final savedPage = PdfDocumentLocator.tryParse(
          book.locator,
        )?.pageNumber;
        final initialPage = pageCount == 0
            ? 1
            : (savedPage ?? book.chapterIndex + 1)
                  .clamp(1, pageCount)
                  .toInt();
        final displayedPage = currentPage.value ?? initialPage;
        final displayedProgress = pageCount <= 1
            ? 0.0
            : (displayedPage - 1) / (pageCount - 1);
        final positionMetrics = ReadingPositionMetrics.progressOnly(
          displayedProgress,
        );
        final bookmarkItems = bookmarks.value ?? const <Bookmark>[];
        final currentLocator = PdfDocumentLocator(
          pageNumber: displayedPage,
        ).serialize();
        final isBookmarked = bookmarkItems.any(
          (bookmark) =>
              PdfDocumentLocator.tryParse(bookmark.locator)?.pageNumber ==
              displayedPage,
        );

        Future<void> savePage(int? pageNumber) async {
          if (pageNumber == null || pageNumber < 1) return;
          currentPage.value = pageNumber;
          final progress = pageCount <= 1
              ? 0.0
              : (pageNumber - 1) / (pageCount - 1);
          final pending = pendingNavigationLocator.value;
          final locator = pending?.pageNumber == pageNumber
              ? pending!.serialize()
              : PdfDocumentLocator(pageNumber: pageNumber).serialize();
          if (pending != null && pending.pageNumber != pageNumber) {
            pendingNavigationLocator.value = null;
          }
          await ref
              .read(bookRepositoryProvider)
              .updateReadingPosition(
                bookId: bookId,
                chapterIndex: pageNumber - 1,
                progress: progress,
                locator: locator,
              );
          ref.invalidate(libraryBooksProvider);
          activityTracker.recordInteraction(
            ReaderPosition(progress: progress, locator: locator),
            ReadingInteraction.pageTurn,
          );
        }

        Future<void> toggleBookmark() async {
          final repository = ref.read(bookmarkRepositoryProvider);
          final existing = bookmarkItems
              .where(
                (bookmark) =>
                    PdfDocumentLocator.tryParse(
                      bookmark.locator,
                    )?.pageNumber ==
                    displayedPage,
              )
              .firstOrNull;
          if (existing != null) {
            await repository.remove(existing.id);
          } else {
            await repository.add(
              bookId: bookId,
              locator: currentLocator,
              chapterTitle: '第 $displayedPage 页',
            );
          }
          ref.invalidate(bookmarksForBookProvider(bookId));
        }

        Future<void> openBookmarks() async {
          final bookmark = await showDialog<Bookmark>(
            context: context,
            builder: (context) => PdfBookmarksDialog(bookmarks: bookmarkItems),
          );
          final page = bookmark == null
              ? null
              : PdfDocumentLocator.tryParse(bookmark.locator)?.pageNumber;
          if (page != null && viewerController.isReady) {
            await viewerController.goToPage(pageNumber: page);
          }
        }

        Future<void> openSearch() async {
          final searcher = textSearcher.value;
          if (searcher == null) return;
          await showDialog<void>(
            context: context,
            builder: (context) => PdfSearchDialog(searcher: searcher),
          );
        }

        Future<void> openNavigation() async {
          final document = pdfDocument.value;
          if (document == null) return;
          final destination = await showDialog<PdfDest>(
            context: context,
            builder: (context) => PdfNavigationDialog(
              document: document,
              outline: outline.value,
              isOutlineLoading: outlineLoading.value,
              outlineError: outlineError.value,
              currentPage: displayedPage,
            ),
          );
          if (destination != null && viewerController.isReady) {
            await viewerController.goToDest(destination);
          }
        }

        Future<void> seekToProgress(double progress) async {
          if (pageCount <= 0 || !viewerController.isReady) return;
          final page =
              (progress.clamp(0, 1) * (pageCount - 1))
                  .round()
                  .clamp(0, pageCount - 1)
                  .toInt() +
              1;
          await viewerController.goToPage(pageNumber: page);
          await savePage(page);
        }

        void showReaderMessage(String message) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }

        void paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
          for (final annotation in verifiedAnnotations.value) {
            final locator = PdfDocumentLocator.tryParse(annotation.locator);
            if (locator == null || locator.pageNumber != page.pageNumber) {
              continue;
            }
            final color = pdfAnnotationColor(annotation.color);
            for (final normalized in locator.rects) {
              final rect = Rect.fromLTWH(
                pageRect.left + normalized.left * pageRect.width,
                pageRect.top + normalized.top * pageRect.height,
                normalized.width * pageRect.width,
                normalized.height * pageRect.height,
              );
              if (annotation.renderStyle ==
                  AnnotationRenderStyle.underline) {
                canvas.drawLine(
                  rect.bottomLeft,
                  rect.bottomRight,
                  Paint()
                    ..color = color
                    ..strokeWidth = (rect.height * .09)
                        .clamp(1.2, 3.0)
                        .toDouble(),
                );
              } else {
                canvas.drawRect(
                  rect,
                  Paint()
                    ..color = color.withValues(alpha: .32)
                    ..style = PaintingStyle.fill,
                );
              }
            }
          }
        }

        Future<bool> navigateToLocator(
          PdfDocument document,
          PdfDocumentLocator locator, {
          bool showFailure = true,
        }) async {
          final verified = await selectionBridge.verifyLocator(
            document,
            locator,
          );
          final target = verified
              ? selectionBridge.targetRect(document, locator)
              : null;
          if (!verified || target == null || !viewerController.isReady) {
            if (showFailure) {
              showReaderMessage('无法验证这条 PDF 标注的位置，已保留当前阅读位置。');
            }
            return false;
          }
          pendingNavigationLocator.value = locator;
          await viewerController.goToPage(pageNumber: locator.pageNumber);
          if (!viewerController.isReady) return false;
          final documentRect = viewerController.calcRectForRectInsidePage(
            pageNumber: locator.pageNumber,
            rect: target,
          );
          await viewerController.ensureVisible(documentRect, margin: 24);
          return true;
        }

        Future<PdfVerifiedSelection?> captureSelection(
          PdfTextSelectionDelegate delegate,
        ) async {
          final document = pdfDocument.value;
          if (document == null) return null;
          try {
            return await selectionBridge.capture(
              delegate: delegate,
              document: document,
            );
          } on PdfSelectionException catch (error) {
            showReaderMessage(error.message);
          } on Object catch (error) {
            showReaderMessage('无法读取 PDF 选区：$error');
          }
          return null;
        }

        Future<void> saveSelection(
          PdfTextSelectionDelegate delegate,
          PdfVerifiedSelection selection,
          AnnotationColor color, {
          AnnotationRenderStyle renderStyle = AnnotationRenderStyle.highlight,
          String? note,
        }) async {
          await ref
              .read(annotationControllerProvider)
              .add(
                bookId: bookId,
                href: 'pdf:page:${selection.locator.pageNumber}',
                locator: selection.locator.serialize(),
                selectedText: selection.text,
                color: color,
                renderStyle: renderStyle,
                note: note,
                chapterIndex: selection.locator.pageNumber - 1,
                chapterTitle: '第 ${selection.locator.pageNumber} 页',
              );
          await delegate.clearTextSelection();
        }

        Future<void> openAiWithSelection(
          PdfTextSelectionDelegate delegate,
          PdfVerifiedSelection selection,
          String prompt,
        ) async {
          ref
              .read(pendingChatDraftProvider.notifier)
              .set(
                PendingChatDraft(
                  attachment: ChatContextAttachment(
                    bookId: bookId,
                    bookTitle: book.title,
                    href: 'pdf:page:${selection.locator.pageNumber}',
                    locator: selection.locator.serialize(),
                    chapterIndex: selection.locator.pageNumber - 1,
                    chapterTitle: '第 ${selection.locator.pageNumber} 页',
                    quote: selection.text,
                  ),
                  prompt: prompt,
                ),
              );
          await delegate.clearTextSelection();
          onOpenChat();
        }

        Future<void> performSelectionAction(
          PdfTextSelectionDelegate delegate,
          _PdfSelectionAction action,
        ) async {
          final selection = await captureSelection(delegate);
          if (selection == null || !context.mounted) return;
          try {
            switch (action) {
              case _PdfSelectionAction.highlight:
                final highlightColor = await showDialog<AnnotationColor>(
                  context: context,
                  builder: (context) => const PdfAnnotationColorDialog(
                    title: '选择高亮颜色',
                  ),
                );
                if (highlightColor != null && context.mounted) {
                  await saveSelection(delegate, selection, highlightColor);
                }
              case _PdfSelectionAction.underline:
                final underlineColor = await showDialog<AnnotationColor>(
                  context: context,
                  builder: (context) => const PdfAnnotationColorDialog(
                    title: '选择划线颜色',
                  ),
                );
                if (underlineColor != null && context.mounted) {
                  await saveSelection(
                    delegate,
                    selection,
                    underlineColor,
                    renderStyle: AnnotationRenderStyle.underline,
                  );
                }
              case _PdfSelectionAction.note:
                final draft = await showDialog<PdfAnnotationDraft>(
                  context: context,
                  builder: (context) => PdfAnnotationEditorDialog(
                    selectedText: selection.text,
                  ),
                );
                if (draft != null && context.mounted) {
                  await saveSelection(
                    delegate,
                    selection,
                    draft.color,
                    note: draft.note,
                  );
                }
              case _PdfSelectionAction.askAi:
                await openAiWithSelection(
                  delegate,
                  selection,
                  '关于这段 PDF 文字，我想问：',
                );
              case _PdfSelectionAction.explainAi:
                await openAiWithSelection(
                  delegate,
                  selection,
                  '请解释这段 PDF 文字的含义和关键概念。',
                );
              case _PdfSelectionAction.summarizeAi:
                await openAiWithSelection(
                  delegate,
                  selection,
                  '请简洁总结这段 PDF 文字的核心观点。',
                );
            }
          } on Object catch (error) {
            showReaderMessage('PDF 标注操作失败：$error');
          }
        }

        void customizeSelectionMenu(
          PdfViewerContextMenuBuilderParams params,
          List<ContextMenuButtonItem> items,
        ) {
          if (params.contextMenuFor != PdfViewerPart.selectedText ||
              !params.textSelectionDelegate.hasSelectedText) {
            return;
          }
          void addAction(String label, _PdfSelectionAction action) {
            items.add(
              ContextMenuButtonItem(
                label: label,
                onPressed: () {
                  params.dismissContextMenu();
                  unawaited(
                    performSelectionAction(
                      params.textSelectionDelegate,
                      action,
                    ),
                  );
                },
              ),
            );
          }

          addAction('高亮', _PdfSelectionAction.highlight);
          addAction('划线', _PdfSelectionAction.underline);
          addAction('笔记', _PdfSelectionAction.note);
          addAction('询问 AI', _PdfSelectionAction.askAi);
          addAction('解释', _PdfSelectionAction.explainAi);
          addAction('总结', _PdfSelectionAction.summarizeAi);
        }

        Future<void> explainTextSelection() async {
          final document = pdfDocument.value;
          if (document == null) return;
          final supported = await selectionBridge.pageSupportsText(
            document,
            displayedPage,
          );
          if (!context.mounted) return;
          showReaderMessage(
            supported
                ? '长按或拖动选择本页文字，然后可高亮、划线、添加笔记或询问 AI。'
                : '当前页没有可用文本层，扫描版或受保护 PDF 不支持文本标注。',
          );
        }

        Future<void> openAnnotations() async {
          final selected = await showDialog<ReadingAnnotation>(
            context: context,
            builder: (context) => PdfAnnotationsDialog(
              annotations: annotations.value ?? const [],
              onDelete: (annotation) => ref
                  .read(annotationControllerProvider)
                  .remove(annotation.id),
            ),
          );
          final document = pdfDocument.value;
          if (selected == null || document == null || !context.mounted) return;
          final locator = PdfDocumentLocator.tryParse(selected.locator);
          if (locator == null) {
            showReaderMessage('这条标注没有有效的 PDF 定位信息。');
            return;
          }
          await navigateToLocator(document, locator);
        }

        return Stack(
          children: [
            Positioned.fill(
              child: _PdfCenterTapDetector(
                onTap: toggleControls,
                child: PdfViewer.file(
                  book.filePath,
                  controller: viewerController,
                  initialPageNumber: initialPage,
                  params: PdfViewerParams(
                    onPageChanged: savePage,
                    onViewerReady: (_, controller) {
                      if (textSearcher.value == null) {
                        textSearcher.value = PdfTextSearcher(controller);
                      }
                      if (pdfDocument.value == null) {
                        pdfDocument.value = controller.document;
                        loadOutline(controller.document);
                      }
                      final locator = PdfDocumentLocator.tryParse(book.locator);
                      if (locator?.precision == DocumentLocatorPrecision.exact) {
                        pendingNavigationLocator.value = locator;
                        unawaited(
                          navigateToLocator(
                            controller.document,
                            locator!,
                            showFailure: false,
                          ),
                        );
                      }
                    },
                    textSelectionParams: const PdfTextSelectionParams(
                      enabled: true,
                    ),
                    customizeContextMenuItems: customizeSelectionMenu,
                    pagePaintCallbacks: [
                      if (textSearcher.value != null)
                        textSearcher.value!.pageTextMatchPaintCallback,
                      paintAnnotations,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _PdfReaderChrome(
                visible: controlsVisible.value,
                hiddenOffset: const Offset(0, -1),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '返回书库',
                          onPressed: onExitReader,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Icon(Icons.picture_as_pdf_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(title, overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          tooltip: isBookmarked ? '移除书签' : '添加书签',
                          onPressed: toggleBookmark,
                          icon: Icon(
                            isBookmarked
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                          ),
                        ),
                        if (MediaQuery.sizeOf(context).width >= 760) ...[
                          IconButton(
                            tooltip: '查看书签',
                            onPressed: bookmarks.isLoading
                                ? null
                                : openBookmarks,
                            icon: const Icon(Icons.format_list_bulleted),
                          ),
                          const VerticalDivider(width: 20),
                          IconButton(
                            tooltip: '目录和页面导航',
                            onPressed: pdfDocument.value == null
                                ? null
                                : openNavigation,
                            icon: const Icon(Icons.menu_book_outlined),
                          ),
                          IconButton(
                            tooltip: '搜索 PDF',
                            onPressed: textSearcher.value == null
                                ? null
                                : openSearch,
                            icon: const Icon(Icons.search),
                          ),
                          IconButton(
                            key: const Key('pdf-reader-selection-help'),
                            tooltip: 'PDF 文本标注',
                            onPressed: pdfDocument.value == null
                                ? null
                                : explainTextSelection,
                            icon: const Icon(Icons.highlight_alt_outlined),
                          ),
                          IconButton(
                            key: const Key('pdf-reader-annotations'),
                            tooltip: '查看 PDF 标注',
                            onPressed: annotations.isLoading
                                ? null
                                : openAnnotations,
                            icon: const Icon(Icons.format_quote_outlined),
                          ),
                          const VerticalDivider(width: 20),
                          IconButton(
                            key: const Key('pdf-reader-focus-mode'),
                            tooltip: '隐藏阅读控制',
                            onPressed: toggleControls,
                            icon: const Icon(
                              Icons.center_focus_strong_outlined,
                            ),
                          ),
                        ],
                        if (MediaQuery.sizeOf(context).width < 760)
                          PopupMenuButton<_PdfToolbarAction>(
                            key: const Key('pdf-reader-more-actions'),
                            tooltip: '更多阅读操作',
                            onSelected: (action) {
                              switch (action) {
                                case _PdfToolbarAction.bookmarks:
                                  unawaited(openBookmarks());
                                case _PdfToolbarAction.navigation:
                                  unawaited(openNavigation());
                                case _PdfToolbarAction.search:
                                  unawaited(openSearch());
                                case _PdfToolbarAction.selectionHelp:
                                  unawaited(explainTextSelection());
                                case _PdfToolbarAction.annotations:
                                  unawaited(openAnnotations());
                                case _PdfToolbarAction.focus:
                                  toggleControls();
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: _PdfToolbarAction.bookmarks,
                                enabled: !bookmarks.isLoading,
                                child: const Text('查看书签'),
                              ),
                              PopupMenuItem(
                                value: _PdfToolbarAction.navigation,
                                enabled: pdfDocument.value != null,
                                child: const Text('目录和页面导航'),
                              ),
                              PopupMenuItem(
                                value: _PdfToolbarAction.search,
                                enabled: textSearcher.value != null,
                                child: const Text('搜索 PDF'),
                              ),
                              PopupMenuItem(
                                key: const Key(
                                  'pdf-reader-selection-help-menu',
                                ),
                                value: _PdfToolbarAction.selectionHelp,
                                enabled: pdfDocument.value != null,
                                child: const Text('PDF 文本标注'),
                              ),
                              PopupMenuItem(
                                key: const Key(
                                  'pdf-reader-annotations-menu',
                                ),
                                value: _PdfToolbarAction.annotations,
                                enabled: !annotations.isLoading,
                                child: const Text('查看 PDF 标注'),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: _PdfToolbarAction.focus,
                                child: Text('隐藏阅读控制'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _PdfReaderChrome(
                visible: controlsVisible.value,
                hiddenOffset: const Offset(0, 1),
                child: Material(
                  key: const Key('pdf-reader-footer'),
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.description_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          positionMetrics.label,
                          key: const Key('pdf-reader-position-label'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _PdfReaderProgressSlider(
                            progress: displayedProgress,
                            onChanged: seekToProgress,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PdfReaderChrome extends StatelessWidget {
  const _PdfReaderChrome({
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

class _PdfReaderProgressSlider extends StatefulWidget {
  const _PdfReaderProgressSlider({
    required this.progress,
    required this.onChanged,
  });

  final double progress;
  final ValueChanged<double> onChanged;

  @override
  State<_PdfReaderProgressSlider> createState() =>
      _PdfReaderProgressSliderState();
}

class _PdfReaderProgressSliderState extends State<_PdfReaderProgressSlider> {
  double? _dragProgress;

  @override
  Widget build(BuildContext context) {
    final value = (_dragProgress ?? widget.progress).clamp(0, 1).toDouble();
    return Slider(
      key: const Key('pdf-reader-progress-slider'),
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

class _PdfCenterTapDetector extends StatelessWidget {
  const _PdfCenterTapDetector({required this.onTap, required this.child});

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
      if (position.dx >= size.width * .25 &&
          position.dx <= size.width * .75 &&
          position.dy >= size.height * .25 &&
          position.dy <= size.height * .75) {
        onTap();
      }
    },
    child: child,
  );
}
