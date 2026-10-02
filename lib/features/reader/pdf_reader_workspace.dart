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
import '../../domain/models/reading_settings.dart';
import '../../domain/models/reader_theme.dart';
import '../chat/chat_controller.dart';
import '../notes/notes_providers.dart';
import 'pdf_annotation_widgets.dart';
import 'pdf_bookmarks_dialog.dart';
import 'pdf_navigation_dialog.dart';
import 'pdf_search_dialog.dart';
import 'reader_chrome.dart';
import 'reader_theme_controller.dart';
import 'reader_theme_data.dart';
import 'volume_control_service.dart';
import 'volume_key_page_turner.dart';

void _noopPdfReaderAction() {}

enum _PdfSelectionAction {
  highlight,
  underline,
  note,
  askAi,
  explainAi,
  summarizeAi,
}

class PdfReaderWorkspace extends ConsumerWidget {
  const PdfReaderWorkspace({
    super.key,
    required this.bookId,
    required this.title,
    required this.readingSettings,
    this.onExitReader = _noopPdfReaderAction,
    this.onOpenChat = _noopPdfReaderAction,
  });

  final String bookId;
  final String title;
  final ReadingSettings readingSettings;
  final VoidCallback onExitReader;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(bookReadingOverrideProvider(bookId)).value;
    final customThemes =
        ref.watch(customReaderThemesProvider).value ??
        const <CustomReaderTheme>[];
    final settings = (override?.settings ?? readingSettings).copyWith(
      volumeKeyTurnsPage: readingSettings.volumeKeyTurnsPage,
    );
    return Theme(
      data: ReaderThemeData.build(Theme.of(context), settings, customThemes),
      child: _PdfReaderWorkspaceContent(
        bookId: bookId,
        title: title,
        volumeKeyTurnsPage: settings.volumeKeyTurnsPage,
        onExitReader: onExitReader,
        onOpenChat: onOpenChat,
      ),
    );
  }
}

class _PdfReaderWorkspaceContent extends HookConsumerWidget {
  const _PdfReaderWorkspaceContent({
    required this.bookId,
    required this.title,
    required this.volumeKeyTurnsPage,
    required this.onExitReader,
    required this.onOpenChat,
  });

  final String bookId;
  final String title;
  final bool volumeKeyTurnsPage;
  final VoidCallback onExitReader;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookState = ref.watch(readerBookProvider(bookId));
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    final annotations = ref.watch(annotationsForBookProvider(bookId));
    final currentPage = useState<int?>(null);
    final volumeKeyTurner = useMemoized(
      () => VolumeKeyPageTurner(control: VolumeControlService()),
    );
    final volumeKeyPrevious = useRef<VoidCallback?>(null);
    final volumeKeyNext = useRef<VoidCallback?>(null);
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

    useEffect(
      () => () {
        unawaited(volumeKeyTurner.dispose());
      },
      [volumeKeyTurner],
    );

    useEffect(() {
      unawaited(
        volumeKeyTurner.configure(
          enabled: volumeKeyTurnsPage,
          onPrevious: () => volumeKeyPrevious.value?.call(),
          onNext: () => volumeKeyNext.value?.call(),
        ),
      );
      return null;
    }, [volumeKeyTurner, volumeKeyTurnsPage]);

    void toggleControls() => controlsVisible.value = !controlsVisible.value;

    useEffect(() {
      return () => textSearcher.value?.dispose();
    }, [viewerController]);

    useEffect(() {
      final book = bookState.value;
      if (book == null) return null;
      final pageNumber =
          PdfDocumentLocator.tryParse(book.locator)?.pageNumber ??
          book.chapterIndex + 1;
      unawaited(
        ref
            .read(libraryBooksProvider.notifier)
            .updateReadingPosition(
              bookId: bookId,
              chapterIndex: pageNumber - 1,
              progress: book.progress,
              locator:
                  book.locator ??
                  PdfDocumentLocator(pageNumber: pageNumber).serialize(),
            ),
      );
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
      error: (error, _) => Center(child: Text('تعذر تحميل ملف PDF: $error')),
      data: (book) {
        if (book == null) return const Center(child: Text('لم يتم العثور على كتب PDF.'));
        final pageCount = book.chapterCount;
        final savedPage = PdfDocumentLocator.tryParse(book.locator)?.pageNumber;
        final initialPage = pageCount == 0
            ? 1
            : (savedPage ?? book.chapterIndex + 1).clamp(1, pageCount).toInt();
        final displayedPage = currentPage.value ?? initialPage;
        final displayedProgress = pageCount <= 1
            ? 0.0
            : (displayedPage - 1) / (pageCount - 1);
        final chromeLayout = ReaderChromeLayout.resolve(
          context,
          maxWidth: MediaQuery.sizeOf(context).width,
        );
        final usesOverflowActions = chromeLayout.usesOverflowActions(
          MediaQuery.sizeOf(context).width,
        );
        final pageLabel = pageCount > 0
            ? 'صفحة $displayedPage من $pageCount'
            : 'قراءة الصفحات';
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
              .read(libraryBooksProvider.notifier)
              .updateReadingPosition(
                bookId: bookId,
                chapterIndex: pageNumber - 1,
                progress: progress,
                locator: locator,
              );
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
                    PdfDocumentLocator.tryParse(bookmark.locator)?.pageNumber ==
                    displayedPage,
              )
              .firstOrNull;
          if (existing != null) {
            await repository.remove(existing.id);
          } else {
            await repository.add(
              bookId: bookId,
              locator: currentLocator,
              chapterTitle: 'الصفحة $displayedPage',
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
              if (annotation.renderStyle == AnnotationRenderStyle.underline) {
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
              showReaderMessage('تعذر التحقق من موقع وسيلة شرح PDF هذه، وتم الحفاظ على موقع القراءة الحالي.');
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
            showReaderMessage('تعذر قراءة تحديد PDF: $error');
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
                chapterTitle: 'الفقرتان 102${selection.locator.pageNumber}الصفحة',
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
                    chapterTitle: 'الفقرتان 102${selection.locator.pageNumber}الصفحة',
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
                  builder: (context) =>
                      const PdfAnnotationColorDialog(title: 'تحديد لون التمييز'),
                );
                if (highlightColor != null && context.mounted) {
                  await saveSelection(delegate, selection, highlightColor);
                }
              case _PdfSelectionAction.underline:
                final underlineColor = await showDialog<AnnotationColor>(
                  context: context,
                  builder: (context) =>
                      const PdfAnnotationColorDialog(title: 'تحديد لون لوحة القيادة'),
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
                  builder: (context) =>
                      PdfAnnotationEditorDialog(selectedText: selection.text),
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
                  'فيما يتعلق بنص PDF هذا، أود أن أسأل:',
                );
              case _PdfSelectionAction.explainAi:
                await openAiWithSelection(
                  delegate,
                  selection,
                  'يرجى توضيح المعنى والمفاهيم الأساسية لنص PDF هذا.',
                );
              case _PdfSelectionAction.summarizeAi:
                await openAiWithSelection(
                  delegate,
                  selection,
                  'يرجى تلخيص النقاط الأساسية لنص PDF هذا بإيجاز.',
                );
            }
          } on Object catch (error) {
            showReaderMessage('فشلت عملية شرح PDF: $error');
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

          addAction('Ø¥Ø¨Ø±Ø§Ø²', _PdfSelectionAction.highlight);
          addAction('DASH', _PdfSelectionAction.underline);
          addAction('ملاحظة', _PdfSelectionAction.note);
          addAction('اسأل الذكاء الاصطناعي', _PdfSelectionAction.askAi);
          addAction('التفسير', _PdfSelectionAction.explainAi);
          addAction('الموجز', _PdfSelectionAction.summarizeAi);
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
                ? 'اضغط لفترة طويلة أو اسحب لتحديد النص في هذه الصفحة، ثم قم بتمييز أو تسطير أو إضافة ملاحظات أو طلب الذكاء الاصطناعي.'
                : 'لا توجد طبقات نصية متاحة للصفحة الحالية، ولا تدعم ملفات PDF الممسوحة ضوئيًا أو المحمية التعليقات التوضيحية النصية.',
          );
        }

        Future<void> openAnnotations() async {
          final selected = await showDialog<ReadingAnnotation>(
            context: context,
            builder: (context) => PdfAnnotationsDialog(
              annotations: annotations.value ?? const [],
              onDelete: (annotation) =>
                  ref.read(annotationControllerProvider).remove(annotation.id),
            ),
          );
          final document = pdfDocument.value;
          if (selected == null || document == null || !context.mounted) return;
          final locator = PdfDocumentLocator.tryParse(selected.locator);
          if (locator == null) {
            showReaderMessage('لا تحتوي وسيلة الشرح هذه على معلومات موقع PDF صالحة.');
            return;
          }
          await navigateToLocator(document, locator);
        }

        Future<void> goToPage(int pageNumber) async {
          if (pageNumber < 1 ||
              pageNumber > pageCount ||
              !viewerController.isReady) {
            return;
          }
          await viewerController.goToPage(pageNumber: pageNumber);
          await savePage(pageNumber);
        }

        volumeKeyPrevious.value = displayedPage > 1
            ? () => unawaited(goToPage(displayedPage - 1))
            : null;
        volumeKeyNext.value = pageCount > 0 && displayedPage < pageCount
            ? () => unawaited(goToPage(displayedPage + 1))
            : null;

        void openPdfProgressSheet() {
          unawaited(
            showReaderProgressSheet(
              context,
              title: 'تقدم قراءة PDF',
              positionLabel: pageLabel,
              progress: displayedProgress,
              onChangeEnd: (value) => unawaited(seekToProgress(value)),
            ),
          );
        }

        void openPdfMoreSheet() {
          unawaited(
            showReaderMoreSheet(
              context,
              title: 'أدوات PDF',
              groups: [
                ReaderChromeActionGroup(
                  title: 'يبحث...',
                  actions: [
                    ReaderChromeAction(
                      id: 'pdf-bookmarks',
                      label: 'عرض الإشارات المرجعية',
                      icon: Icons.bookmarks_outlined,
                      onPressed: bookmarks.isLoading
                          ? null
                          : () => unawaited(openBookmarks()),
                      disabledDescription: 'قراءة الإشارات المرجعية',
                    ),
                    ReaderChromeAction(
                      id: 'pdf-bookmark',
                      label: isBookmarked ? 'إزالة الإشارة المرجعية' : 'أضف علامة',
                      icon: isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      onPressed: () => unawaited(toggleBookmark()),
                    ),
                    ReaderChromeAction(
                      id: 'pdf-navigation',
                      label: 'جدول المحتويات والتنقل في الصفحة',
                      icon: Icons.menu_book_outlined,
                      onPressed: pdfDocument.value == null
                          ? null
                          : () => unawaited(openNavigation()),
                      disabledDescription: 'قراءة كتالوج PDF',
                    ),
                    ReaderChromeAction(
                      id: 'pdf-search',
                      label: 'البحث في ملف PDF',
                      icon: Icons.search,
                      onPressed: textSearcher.value == null
                          ? null
                          : () => unawaited(openSearch()),
                      disabledDescription: 'إعداد فهرس البحث',
                    ),
                  ],
                ),
                ReaderChromeActionGroup(
                  title: 'القراءة',
                  actions: [
                    const ReaderChromeAction(
                      id: 'pdf-tts',
                      label: 'قراءات نظام PDF',
                      icon: Icons.headphones_outlined,
                      disabledDescription: 'لا يمكن التحقق من قائمة انتظار قراءة النص الكامل لملف PDF بعد',
                    ),
                    ReaderChromeAction(
                      id: 'pdf-focus',
                      label: 'إخفاء عناصر التحكم في القراءة',
                      icon: Icons.center_focus_strong_outlined,
                      onPressed: toggleControls,
                    ),
                  ],
                ),
                ReaderChromeActionGroup(
                  title: 'أدوات PDF',
                  actions: [
                    ReaderChromeAction(
                      id: 'pdf-selection-help',
                      label: 'وسيلة شرح نص PDF',
                      icon: Icons.highlight_alt_outlined,
                      onPressed: pdfDocument.value == null
                          ? null
                          : () => unawaited(explainTextSelection()),
                      disabledDescription: 'قراءة طبقات نص PDF',
                    ),
                    ReaderChromeAction(
                      id: 'pdf-annotations',
                      label: 'عرض وسيلة شرح PDF',
                      icon: Icons.format_quote_outlined,
                      onPressed: annotations.isLoading
                          ? null
                          : () => unawaited(openAnnotations()),
                      disabledDescription: 'قراءة التعليقات التوضيحية بصيغة PDF',
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              // The PDF canvas keeps its full viewport; controls are a
              // foreground layer so toggling them cannot rescale pages.
              child: ReaderContentTapDetector(
                onTap: toggleControls,
                child: PdfViewer.file(
                  book.filePath,
                  controller: viewerController,
                  initialPageNumber: initialPage,
                  params: PdfViewerParams(
                    // Never recolor the PDF itself: its page appearance is
                    // part of the document. The surrounding reading canvas
                    // still follows the selected app palette on every
                    // platform, including the paper preset.
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLow,
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
                      if (locator?.precision ==
                          DocumentLocatorPrecision.exact) {
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
                child: chromeLayout.isCompact
                    ? ReaderCompactTopBar(
                        title: title,
                        contextLabel: pageLabel,
                        onBack: onExitReader,
                        onOpenMore: openPdfMoreSheet,
                        backKey: const Key('pdf-reader-back'),
                        moreKey: const Key('pdf-reader-more-actions'),
                      )
                    : Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                ReaderChromeIconButton(
                                  key: const Key('pdf-reader-back'),
                                  tooltip: 'العودة إلى المكتبة',
                                  icon: Icons.arrow_back,
                                  onPressed: onExitReader,
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.picture_as_pdf_outlined),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Semantics(
                                    header: true,
                                    label: '$title，$pageLabel',
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (usesOverflowActions) ...[
                                  ReaderChromeIconButton(
                                    tooltip: isBookmarked ? 'إزالة الإشارة المرجعية' : 'أضف علامة',
                                    icon: isBookmarked
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    onPressed: () =>
                                        unawaited(toggleBookmark()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    tooltip: 'البحث في ملف PDF',
                                    icon: Icons.search,
                                    onPressed: textSearcher.value == null
                                        ? null
                                        : () => unawaited(openSearch()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    key: const Key('pdf-reader-more-actions'),
                                    tooltip: 'قراءة المزيد من الإجراءات',
                                    icon: Icons.more_vert,
                                    onPressed: openPdfMoreSheet,
                                  ),
                                ] else ...[
                                  ReaderChromeIconButton(
                                    tooltip: isBookmarked ? 'إزالة الإشارة المرجعية' : 'أضف علامة',
                                    icon: isBookmarked
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    onPressed: () =>
                                        unawaited(toggleBookmark()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    tooltip: 'عرض الإشارات المرجعية',
                                    icon: Icons.bookmarks_outlined,
                                    onPressed: bookmarks.isLoading
                                        ? null
                                        : () => unawaited(openBookmarks()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    tooltip: 'جدول المحتويات والتنقل في الصفحة',
                                    icon: Icons.menu_book_outlined,
                                    onPressed: pdfDocument.value == null
                                        ? null
                                        : () => unawaited(openNavigation()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    tooltip: 'البحث في ملف PDF',
                                    icon: Icons.search,
                                    onPressed: textSearcher.value == null
                                        ? null
                                        : () => unawaited(openSearch()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    key: const Key('pdf-reader-selection-help'),
                                    tooltip: 'وسيلة شرح نص PDF',
                                    icon: Icons.highlight_alt_outlined,
                                    onPressed: pdfDocument.value == null
                                        ? null
                                        : () =>
                                              unawaited(explainTextSelection()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    key: const Key('pdf-reader-annotations'),
                                    tooltip: 'عرض وسيلة شرح PDF',
                                    icon: Icons.format_quote_outlined,
                                    onPressed: annotations.isLoading
                                        ? null
                                        : () => unawaited(openAnnotations()),
                                  ),
                                  const SizedBox(width: 8),
                                  ReaderChromeIconButton(
                                    key: const Key('pdf-reader-focus-mode'),
                                    tooltip: 'إخفاء عناصر التحكم في القراءة',
                                    icon: Icons.center_focus_strong_outlined,
                                    onPressed: toggleControls,
                                  ),
                                ],
                              ],
                            ),
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
                child: chromeLayout.isExpanded
                    ? Material(
                        key: const Key('pdf-reader-footer'),
                        color: Theme.of(context).colorScheme.surface,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                ReaderChromeIconButton(
                                  key: const Key('pdf-reader-toc'),
                                  tooltip: 'جدول المحتويات والتنقل في الصفحة',
                                  icon: Icons.menu_book_outlined,
                                  onPressed: pdfDocument.value == null
                                      ? null
                                      : () => unawaited(openNavigation()),
                                ),
                                const SizedBox(width: 8),
                                ReaderChromeIconButton(
                                  key: const Key('pdf-reader-previous-page'),
                                  tooltip: 'الصفحة السابقة',
                                  icon: Icons.chevron_left,
                                  onPressed: displayedPage > 1
                                      ? () => unawaited(
                                          goToPage(displayedPage - 1),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Semantics(
                                  key: const Key('pdf-reader-position-label'),
                                  label: '$pageLabel، تقدم القراءة المفتوحة',
                                  button: true,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: openPdfProgressSheet,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      child: Text(pageLabel),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _PdfReaderProgressSlider(
                                    progress: displayedProgress,
                                    onChanged: seekToProgress,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ReaderChromeIconButton(
                                  key: const Key('pdf-reader-next-page'),
                                  tooltip: 'الصفحة التالية',
                                  icon: Icons.chevron_right,
                                  onPressed:
                                      pageCount > 0 && displayedPage < pageCount
                                      ? () => unawaited(
                                          goToPage(displayedPage + 1),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                ReaderChromeIconButton(
                                  key: const Key('pdf-reader-tools'),
                                  tooltip: 'أدوات PDF',
                                  icon: Icons.tune_outlined,
                                  onPressed: openPdfMoreSheet,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ReaderCompactNavigationBar(
                        key: const Key('pdf-reader-footer'),
                        tocKey: const Key('pdf-reader-toc'),
                        previousKey: const Key('pdf-reader-previous-page'),
                        positionKey: const Key('pdf-reader-position-label'),
                        nextKey: const Key('pdf-reader-next-page'),
                        styleKey: const Key('pdf-reader-tools'),
                        positionLabel: pageLabel,
                        onOpenToc: pdfDocument.value == null
                            ? null
                            : () => unawaited(openNavigation()),
                        onPrevious: displayedPage > 1
                            ? () => unawaited(goToPage(displayedPage - 1))
                            : null,
                        onNext: pageCount > 0 && displayedPage < pageCount
                            ? () => unawaited(goToPage(displayedPage + 1))
                            : null,
                        onOpenProgress: openPdfProgressSheet,
                        onOpenStyle: openPdfMoreSheet,
                        tocTooltip: 'جدول المحتويات والتنقل في الصفحة',
                        styleTooltip: 'أدوات PDF',
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
