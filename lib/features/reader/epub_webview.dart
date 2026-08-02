import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../app/providers.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_coloring.dart';
import 'epub_webview_android.dart';
import 'reader_navigation_command.dart';

class EpubWebView extends HookConsumerWidget {
  const EpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
    required this.textColoring,
    required this.annotations,
    required this.searchQuery,
    required this.focusedAnnotationId,
    required this.annotationFocusRevision,
    required this.initialScrollRatio,
    required this.initialAnchor,
    required this.initialCfi,
    required this.direction,
    required this.navigationCommand,
    required this.restoreRevision,
    required this.onNavigateToHref,
    required this.onScrollPositionChanged,
    required this.onPaginationChanged,
    required this.onRequestPrevious,
    required this.onRequestNext,
    required this.onNavigationCommandFinished,
    required this.onTextSelectionChanged,
    required this.onSelectionContextMenu,
    required this.onToggleControls,
  });

  static const _hostName = 'reader.tomoread';

  final String bookId;
  final String href;
  final ReadingSettings settings;
  final ResolvedTextColoring textColoring;
  final List<ReadingAnnotation> annotations;
  final String? searchQuery;
  final String? focusedAnnotationId;
  final int annotationFocusRevision;
  final double initialScrollRatio;
  final String? initialAnchor;
  final String? initialCfi;
  final ReadingDirection direction;
  final ReaderNavigationCommand? navigationCommand;
  final int restoreRevision;
  final ValueChanged<String> onNavigateToHref;
  final void Function(String href, double ratio, String? anchor, String? cfi)
  onScrollPositionChanged;
  final void Function(int pageIndex, int pageCount) onPaginationChanged;
  final VoidCallback onRequestPrevious;
  final VoidCallback onRequestNext;
  final ValueChanged<int> onNavigationCommandFinished;
  final ValueChanged<ReaderTextSelection> onTextSelectionChanged;
  final ValueChanged<ReaderSelectionContextMenu> onSelectionContextMenu;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) {
      return AndroidEpubWebView(
        bookId: bookId,
        href: href,
        settings: settings,
        textColoring: textColoring,
        initialScrollRatio: initialScrollRatio,
        initialAnchor: initialAnchor,
        initialCfi: initialCfi,
        direction: direction,
        navigationCommand: navigationCommand,
        restoreRevision: restoreRevision,
        onNavigateToHref: onNavigateToHref,
        onScrollPositionChanged: onScrollPositionChanged,
        onPaginationChanged: onPaginationChanged,
        onRequestPrevious: onRequestPrevious,
        onRequestNext: onRequestNext,
        onNavigationCommandFinished: onNavigationCommandFinished,
        onTextSelectionChanged: onTextSelectionChanged,
        onSelectionContextMenu: onSelectionContextMenu,
        onToggleControls: onToggleControls,
      );
    }
    final readerSession = ref.watch(epubReaderSessionProvider(bookId));
    final fontFaceCss = ref.watch(epubFontFaceCssProvider(settings.font)).value;
    final controller = useMemoized(WebviewController.new);
    final initialized = useState(false);
    final initializationError = useState<Object?>(null);
    final runtimeLoaded = useRef(false);
    final styleScript = _styleScript(context, settings, fontFaceCss);
    final annotationScript = _annotationScript(
      annotations,
      href,
      focusedAnnotationId,
      annotationFocusRevision,
    );
    final runtimeAnnotationScript = _runtimeAnnotationScript(
      annotations,
      focusedAnnotationId,
    );
    final runtimeSearchScript = _runtimeSearchScript(searchQuery);
    final runtimeSettingsScript = _runtimeSettingsScript(
      context,
      settings,
      fontFaceCss,
    );
    final runtimeTextColoringScript = _runtimeTextColoringScript(
      context,
      textColoring,
    );
    final resourceDirectory = readerSession.value?.directoryPath;
    // Foliate owns both pagination and continuous scrolling. Keeping the two
    // modes in the same runtime prevents the legacy one-chapter WebView from
    // truncating a scrolling chapter to its first viewport.
    final useFoliateRuntime = resourceDirectory != null;
    final runtimeEntryPoint = readerSession.value?.virtualEntryPointUrl(
      _hostName,
    );

    Future<void> applyStyle() async {
      try {
        await controller.executeScript(styleScript);
      } catch (_) {
        // The document can change while the WebView is navigating.
      }
    }

    Future<void> restoreScrollPosition() async {
      try {
        await controller.executeScript(
          _restoreScrollScript(initialScrollRatio, initialAnchor),
        );
      } catch (_) {
        // Navigation can complete while the controller is being disposed.
      }
    }

    Future<void> applyAnnotations() async {
      try {
        await controller.executeScript(annotationScript);
      } catch (_) {
        // The document can change while the WebView is navigating.
      }
    }

    Future<void> applyFoliateAnnotations() async {
      try {
        await controller.executeScript(runtimeAnnotationScript);
      } catch (_) {
        // An adjacent chapter can finish loading while its annotations update.
      }
    }

    Future<void> applyFoliateSearch() async {
      try {
        await controller.executeScript(runtimeSearchScript);
      } catch (_) {
        // The active iframe can change while search highlights are updated.
      }
    }

    Future<void> openFoliateRuntime() async {
      try {
        await controller.executeScript(
          _runtimeOpenScript(
            context,
            settings,
            href,
            initialScrollRatio,
            initialAnchor,
            initialCfi,
            fontFaceCss,
          ),
        );
      } catch (_) {
        // The runtime module can still be initializing after navigation.
      }
    }

    Future<void> updateFoliateRuntimeSettings() async {
      try {
        await controller.executeScript(runtimeSettingsScript);
      } catch (_) {
        // The runtime is reconfigured after its module becomes available.
      }
    }

    Future<void> updateFoliateTextColoring() async {
      try {
        await controller.executeScript(runtimeTextColoringScript);
      } catch (_) {
        // Text coloring is a display preference and may safely retry later.
      }
    }

    useEffect(() {
      if (resourceDirectory == null) return null;
      var disposed = false;

      Future<void> initialize() async {
        try {
          await controller.initialize();
          if (disposed) return;
          await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
          await controller.addVirtualHostNameMapping(
            _hostName,
            resourceDirectory,
            WebviewHostResourceAccessKind.deny,
          );
          if (!disposed) initialized.value = true;
        } catch (error) {
          if (!disposed) initializationError.value = error;
        }
      }

      unawaited(initialize());
      return () => disposed = true;
    }, [controller, resourceDirectory]);

    useEffect(
      () {
        if (!initialized.value) return null;
        final subscription = controller.loadingState.listen((state) {
          if (state == LoadingState.navigationCompleted) {
            if (useFoliateRuntime) {
              unawaited(openFoliateRuntime());
            } else {
              unawaited(applyStyle());
              unawaited(applyAnnotations());
              unawaited(restoreScrollPosition());
            }
          }
        });
        if (useFoliateRuntime) {
          if (runtimeEntryPoint != null && !runtimeLoaded.value) {
            runtimeLoaded.value = true;
            unawaited(controller.loadUrl(runtimeEntryPoint));
          }
        } else {
          runtimeLoaded.value = false;
          unawaited(controller.loadUrl(_chapterUrl(href)));
        }
        return subscription.cancel;
      },
      [
        controller,
        href,
        initialized.value,
        runtimeEntryPoint,
        useFoliateRuntime,
      ],
    );

    useEffect(() {
      if (initialized.value && useFoliateRuntime) {
        unawaited(applyFoliateSearch());
      }
      return null;
    }, [initialized.value, runtimeSearchScript, useFoliateRuntime]);

    useEffect(() {
      if (useFoliateRuntime) return null;
      final subscription = controller.url.listen((url) {
        final uri = Uri.tryParse(url);
        if (uri?.host != _hostName) return;
        final path = uri!.path.startsWith('/')
            ? uri.path.substring(1)
            : uri.path;
        final nextHref = uri.fragment.isEmpty ? path : '$path#${uri.fragment}';
        if (nextHref != href) onNavigateToHref(nextHref);
      });
      return subscription.cancel;
    }, [controller, href, onNavigateToHref, useFoliateRuntime]);

    useEffect(
      () {
        final subscription = controller.webMessage.listen((message) {
          if (message is! Map) return;
          final messageHref = message['href'];
          if (message['type'] == 'scrollProgress') {
            final ratio = message['ratio'];
            final anchor = message['anchor'];
            if (messageHref is String && ratio is num) {
              onScrollPositionChanged(
                messageHref,
                ratio.toDouble(),
                anchor is String && anchor.isNotEmpty ? anchor : null,
                null,
              );
            }
          } else if (message['type'] == 'pageChanged') {
            final pageIndex = message['pageIndex'];
            final pageCount = message['pageCount'];
            if (pageIndex is num && pageCount is num) {
              onPaginationChanged(pageIndex.toInt(), pageCount.toInt());
            }
          } else if (message['type'] == 'runtimeRelocate') {
            final href = message['href'];
            final ratio = message['ratio'];
            final anchor = message['anchor'];
            final cfi = message['cfi'];
            final pageIndex = message['pageIndex'];
            final pageCount = message['pageCount'];
            if (href is String && ratio is num) {
              onScrollPositionChanged(
                href,
                EpubLocation.normalizedRelocationRatio(
                  reportedRatio: ratio.toDouble(),
                  paginated: message['flow'] != 'scrolled',
                  pageIndex: pageIndex is num ? pageIndex.toInt() : null,
                  pageCount: pageCount is num ? pageCount.toInt() : null,
                ),
                anchor is String && anchor.isNotEmpty ? anchor : null,
                cfi is String && cfi.isNotEmpty ? cfi : null,
              );
            }
            if (message['flow'] != 'scrolled' &&
                pageIndex is num &&
                pageCount is num) {
              onPaginationChanged(pageIndex.toInt(), pageCount.toInt());
            }
          } else if (message['type'] == 'runtimeError') {
            final runtimeError = message['message'];
            if (runtimeError is String && runtimeError.isNotEmpty) {
              initializationError.value = StateError(runtimeError);
            }
          } else if (message['type'] == 'commandCompleted') {
            final commandId = message['id'];
            if (commandId is num) {
              onNavigationCommandFinished(commandId.toInt());
            }
          } else if (message['type'] == 'commandFailed') {
            final commandId = message['id'];
            if (commandId is num) {
              onNavigationCommandFinished(commandId.toInt());
            }
          } else if (message['type'] == 'readerNavigation') {
            switch (message['direction']) {
              case 'previous':
                onRequestPrevious();
              case 'next':
                onRequestNext();
            }
          } else if (message['type'] == 'textSelection') {
            final text = message['text'];
            final startOffset = message['startOffset'];
            final endOffset = message['endOffset'];
            final cfi = message['cfi'];
            if (messageHref is String &&
                text is String &&
                startOffset is num &&
                endOffset is num) {
              onTextSelectionChanged(
                ReaderTextSelection(
                  href: messageHref,
                  text: text,
                  startOffset: startOffset.toInt(),
                  endOffset: endOffset.toInt(),
                  cfi: cfi is String && cfi.isNotEmpty ? cfi : null,
                ),
              );
            }
          } else if (message['type'] == 'selectionContextMenu') {
            final text = message['text'];
            final startOffset = message['startOffset'];
            final endOffset = message['endOffset'];
            final cfi = message['cfi'];
            final x = message['x'];
            final y = message['y'];
            if (messageHref is String &&
                text is String &&
                startOffset is num &&
                endOffset is num &&
                x is num &&
                y is num) {
              onSelectionContextMenu(
                ReaderSelectionContextMenu(
                  selection: ReaderTextSelection(
                    href: messageHref,
                    text: text,
                    startOffset: startOffset.toInt(),
                    endOffset: endOffset.toInt(),
                    cfi: cfi is String && cfi.isNotEmpty ? cfi : null,
                  ),
                  x: x.toDouble(),
                  y: y.toDouble(),
                ),
              );
            }
          } else if (message['type'] == 'readerControls') {
            onToggleControls();
          }
        });
        return subscription.cancel;
      },
      [
        controller,
        onScrollPositionChanged,
        onTextSelectionChanged,
        onNavigationCommandFinished,
      ],
    );

    useEffect(() {
      if (!initialized.value) return null;
      if (useFoliateRuntime) {
        unawaited(updateFoliateRuntimeSettings());
      } else {
        unawaited(applyStyle());
      }
      return null;
    }, [initialized.value, styleScript, useFoliateRuntime]);

    useEffect(() {
      if (initialized.value && useFoliateRuntime) {
        unawaited(updateFoliateTextColoring());
      }
      return null;
    }, [initialized.value, runtimeTextColoringScript, useFoliateRuntime]);

    useEffect(
      () {
        if (initialized.value) {
          if (useFoliateRuntime) {
            unawaited(applyFoliateAnnotations());
          } else {
            unawaited(applyAnnotations());
          }
        }
        return null;
      },
      [
        initialized.value,
        annotationScript,
        runtimeAnnotationScript,
        useFoliateRuntime,
      ],
    );

    useEffect(() {
      if (!initialized.value) return null;
      if (!useFoliateRuntime) {
        unawaited(restoreScrollPosition());
      }
      return null;
    }, [initialized.value, href, restoreRevision, useFoliateRuntime]);

    useEffect(() {
      final command = navigationCommand;
      if (!initialized.value || !useFoliateRuntime || command == null) {
        return null;
      }
      unawaited(controller.executeScript(_runtimeCommandScript(command)));
      return null;
    }, [controller, initialized.value, navigationCommand, useFoliateRuntime]);

    useEffect(
      () =>
          () => unawaited(controller.dispose()),
      [controller],
    );

    if (readerSession.hasError || initializationError.value != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '无法启动 EPUB 渲染器：${initializationError.value ?? readerSession.error}',
          ),
        ),
      );
    }
    if (readerSession.isLoading || !initialized.value) {
      return const Center(child: CircularProgressIndicator());
    }
    return Webview(controller);
  }

  String _chapterUrl(String chapterHref) =>
      Uri(scheme: 'https', host: _hostName, path: chapterHref).toString();

  String _styleScript(
    BuildContext context,
    ReadingSettings settings,
    String? fontFaceCss,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPaginated = settings.layoutMode == ReaderLayoutMode.paginated;
    final readingDirection = direction == ReadingDirection.rtl ? 'rtl' : 'ltr';
    final margin = settings.pageMargin;
    final layoutCss = isPaginated
        ? '''
html, body {
  height: 100% !important;
  width: 100% !important;
  min-width: 0 !important;
  overflow: hidden !important;
}
body {
  max-width: none !important;
  margin: 0 !important;
  padding: 0 !important;
}
#tomoread-pagination-viewport {
  width: 100% !important;
  height: 100% !important;
  /* Match Foliate's paginator: the column strip is navigated in code, never
     exposed as a user-scrollable horizontal document. */
  overflow-x: hidden !important;
  overflow-y: hidden !important;
}
#tomoread-pagination-content {
  box-sizing: border-box !important;
  /* Keep the column container one-page wide. The viewport shows two of its
     overflow columns at once, so EPUB width rules never span both pages. */
  width: calc((100vw + ${margin * 2}px) / 2) !important;
  min-width: calc((100vw + ${margin * 2}px) / 2) !important;
  height: 100% !important;
  padding: ${margin}px !important;
  column-count: 1 !important;
  column-width: auto !important;
  column-gap: ${margin}px !important;
  column-fill: auto !important;
}
@media (max-width: 720px) {
  #tomoread-pagination-content {
    width: 100% !important;
    min-width: 100% !important;
  }
}
#tomoread-pagination-content > * { break-inside: avoid; }
'''
        : '''
html, body { height: 100% !important; width: 100% !important; overflow: hidden !important; }
body { margin: 0 !important; padding: 0 !important; }
#tomoread-pagination-viewport { width: 100%; height: 100%; overflow-x: hidden; overflow-y: auto; }
#tomoread-pagination-content {
  box-sizing: border-box;
  max-width: 980px;
  margin: 0 auto;
  padding: ${margin}px;
}
''';
    final css =
        '''
${fontFaceCss ?? ''}
html { color-scheme: ${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}; }
html, body { background: ${_cssColor(colorScheme.surface)} !important; color: ${_cssColor(colorScheme.onSurface)} !important; direction: $readingDirection !important; }
body { box-sizing: border-box; font-family: ${jsonEncode(settings.font.fontFamily)} !important; font-size: ${settings.fontSize}px !important; line-height: ${settings.lineHeight} !important; }
$layoutCss
body * { max-width: 100%; box-sizing: border-box; }
p, li, blockquote { font: inherit; line-height: inherit; }
img, svg, video { display: block; height: auto !important; margin: 1.25em auto; }
pre { overflow-x: auto; white-space: pre-wrap; }
a { color: ${_cssColor(colorScheme.primary)}; }
::highlight(tomoread-yellow) { background: #f7d15499; }
::highlight(tomoread-green) { background: #80c78399; }
::highlight(tomoread-blue) { background: #7db8f299; }
::highlight(tomoread-pink) { background: #ec91b699; }
::highlight(tomoread-underline-yellow) { color: #b8860b; text-decoration: underline 2px #d2a72c; text-underline-offset: .16em; }
::highlight(tomoread-underline-green) { color: #397a48; text-decoration: underline 2px #53a56b; text-underline-offset: .16em; }
::highlight(tomoread-underline-blue) { color: #397fbd; text-decoration: underline 2px #5a9bd5; text-underline-offset: .16em; }
::highlight(tomoread-underline-pink) { color: #b95373; text-decoration: underline 2px #d76d8c; text-underline-offset: .16em; }
''';
    return '''(() => {
      let style = document.getElementById('tomoread-reader-style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'tomoread-reader-style';
        document.head.appendChild(style);
      }
      style.textContent = ${jsonEncode(css)};
      window.__tomoReadPaginated = $isPaginated;
      window.__tomoReadRtl = ${direction == ReadingDirection.rtl};
      window.__tomoReadEnsureLayoutRoots = () => {
        let viewport = document.getElementById('tomoread-pagination-viewport');
        let content = document.getElementById('tomoread-pagination-content');
        if (viewport && content) return { viewport, content };
        viewport = document.createElement('div');
        viewport.id = 'tomoread-pagination-viewport';
        content = document.createElement('div');
        content.id = 'tomoread-pagination-content';
        const children = Array.from(document.body.childNodes);
        for (const child of children) content.appendChild(child);
        viewport.appendChild(content);
        document.body.appendChild(viewport);
        return { viewport, content };
      };
      const layoutRoots = window.__tomoReadEnsureLayoutRoots();
      window.__tomoReadScrollRoot = () => layoutRoots.viewport;
      if (!window.__tomoReadScrollListener) {
        let scheduled = false;
        const reportProgress = () => {
          if (scheduled) return;
          scheduled = true;
          window.setTimeout(() => {
            scheduled = false;
            const root = window.__tomoReadScrollRoot?.() || document.scrollingElement || document.documentElement;
            const paginated = window.__tomoReadPaginated === true;
            const viewportSize = paginated ? root.clientWidth : root.clientHeight;
            const extent = paginated ? root.scrollWidth : root.scrollHeight;
            const offset = paginated ? Math.abs(root.scrollLeft) : root.scrollTop;
            const range = Math.max(0, extent - viewportSize);
            const ratio = range === 0 ? 0 : offset / range;
            window.__tomoReadLastRatio = ratio;
            const viewportOffset = offset + 16;
            let activeAnchor = '';
            for (const element of document.querySelectorAll('[id]')) {
              const rect = element.getBoundingClientRect();
              const position = paginated
                ? rect.left + offset
                : rect.top + root.scrollTop;
              if (position <= viewportOffset) activeAnchor = element.id;
            }
            window.chrome?.webview?.postMessage({
              type: 'scrollProgress',
              href: window.location.pathname.replace(/^\\//, ''),
              ratio,
              anchor: activeAnchor,
            });
            if (paginated) {
              const pageCount = Math.max(1, Math.ceil(extent / viewportSize));
              const pageIndex = Math.min(
                pageCount - 1,
                Math.max(0, Math.round(offset / viewportSize)),
              );
              window.chrome?.webview?.postMessage({
                type: 'pageChanged',
                pageIndex,
                pageCount,
              });
            }
          }, 200);
        };
        (window.__tomoReadScrollRoot?.() || window).addEventListener('scroll', reportProgress, { passive: true });
        window.__tomoReadReportProgress = reportProgress;
        window.__tomoReadScrollListener = true;
      }
      window.__tomoReadGoToPage = (requestedPage) => {
        const root = window.__tomoReadScrollRoot?.() || document.scrollingElement || document.documentElement;
        if (window.__tomoReadPaginated !== true) return;
        const viewportSize = root.clientWidth;
        const pageCount = Math.max(1, Math.ceil(root.scrollWidth / viewportSize));
        const pageIndex = Math.min(pageCount - 1, Math.max(0, requestedPage));
        root.scrollLeft = window.__tomoReadRtl ? -pageIndex * viewportSize : pageIndex * viewportSize;
        window.requestAnimationFrame(() => window.__tomoReadReportProgress?.());
      };
      if (!window.__tomoReadNavigationListener) {
        const requestNavigation = (direction) => {
          if (window.__tomoReadPaginated !== true) return;
          window.chrome?.webview?.postMessage({
            type: 'readerNavigation',
            direction,
          });
        };
        window.__tomoReadRequestNavigation = requestNavigation;
        const isEditableTarget = (target) => target instanceof HTMLInputElement ||
          target instanceof HTMLTextAreaElement || target?.isContentEditable;
        window.addEventListener('keydown', (event) => {
          if (window.__tomoReadPaginated !== true || isEditableTarget(event.target)) return;
          const rtl = window.__tomoReadRtl === true;
          let direction = '';
          switch (event.key) {
            case 'ArrowLeft':
              direction = rtl ? 'next' : 'previous';
              break;
            case 'ArrowRight':
              direction = rtl ? 'previous' : 'next';
              break;
            case 'PageUp':
              direction = 'previous';
              break;
            case 'PageDown':
              direction = 'next';
              break;
            case ' ':
            case 'Spacebar':
              direction = event.shiftKey ? 'previous' : 'next';
              break;
          }
          if (!direction) return;
          event.preventDefault();
          requestNavigation(direction);
        });
        let wheelDelta = 0;
        window.addEventListener('wheel', (event) => {
          if (window.__tomoReadPaginated !== true || event.ctrlKey) return;
          if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;
          wheelDelta += event.deltaY;
          if (Math.abs(wheelDelta) < 48) return;
          event.preventDefault();
          requestNavigation(wheelDelta > 0 ? 'next' : 'previous');
          wheelDelta = 0;
        }, { passive: false });
        window.addEventListener('mousedown', (event) => {
          if (window.__tomoReadPaginated !== true) return;
          if (event.button === 3 || event.button === 4) {
            event.preventDefault();
            requestNavigation(event.button === 3 ? 'previous' : 'next');
          }
        });
        let resizeTimer;
        window.addEventListener('resize', () => {
          if (window.__tomoReadPaginated !== true) return;
          window.clearTimeout(resizeTimer);
          resizeTimer = window.setTimeout(() => {
            const root = window.__tomoReadScrollRoot?.() || document.scrollingElement || document.documentElement;
            const ratio = Number.isFinite(window.__tomoReadLastRatio)
              ? window.__tomoReadLastRatio
              : 0;
            const range = Math.max(0, root.scrollWidth - root.clientWidth);
            root.scrollLeft = window.__tomoReadRtl ? -range * ratio : range * ratio;
            window.__tomoReadReportProgress?.();
          }, 80);
        });
        window.__tomoReadNavigationListener = true;
      }
      window.__tomoReadReportProgress?.();
      if (!window.__tomoReadSelectionListener) {
        const readSelection = () => {
          const selection = window.getSelection();
          if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
          const range = selection.getRangeAt(0);
          if (!document.body.contains(range.commonAncestorContainer)) return null;
          const text = selection.toString().replace(/\\s+/g, ' ').trim();
          if (!text) return null;
          const before = range.cloneRange();
          before.selectNodeContents(document.body);
          before.setEnd(range.startContainer, range.startOffset);
          return {
            href: window.location.pathname.replace(/^\\//, ''),
            text,
            startOffset: before.toString().length,
            endOffset: before.toString().length + range.toString().length,
          };
        };
        const reportSelection = () => {
          const selection = readSelection();
          if (selection) window.chrome?.webview?.postMessage({ type: 'textSelection', ...selection });
        };
        document.addEventListener('selectionchange', reportSelection);
        document.addEventListener('pointerup', reportSelection);
        document.addEventListener('contextmenu', (event) => {
          const selection = readSelection();
          if (!selection) return;
          event.preventDefault();
          window.chrome?.webview?.postMessage({
            type: 'selectionContextMenu',
            ...selection,
            x: event.clientX,
            y: event.clientY,
          });
        });
        window.__tomoReadSelectionListener = true;
      }
      if (!window.__tomoReadControlsListener) {
        window.addEventListener('click', (event) => {
          const target = event.target;
          if (target?.closest?.('a, button, input, textarea, select')) return;
          if (window.getSelection?.()?.toString().trim()) return;
          const x = event.clientX / window.innerWidth;
          const y = event.clientY / window.innerHeight;
          if (x >= .25 && x <= .75 && y >= .25 && y <= .75) {
            window.chrome?.webview?.postMessage({ type: 'readerControls' });
            return;
          }
          if (window.__tomoReadPaginated !== true) return;
          if (x < .25) {
            window.__tomoReadRequestNavigation?.('previous');
          } else if (x > .75) {
            window.__tomoReadRequestNavigation?.('next');
          }
        });
        window.__tomoReadControlsListener = true;
      }
    })();''';
  }

  String _annotationScript(
    List<ReadingAnnotation> annotations,
    String href,
    String? focusedAnnotationId,
    int focusRevision,
  ) {
    final values = annotations
        .where((annotation) => annotation.href == href)
        .map((annotation) {
          final offsets = annotation.locator.split(':');
          return {
            'start': int.tryParse(offsets.first) ?? -1,
            'end': offsets.length == 2 ? int.tryParse(offsets.last) ?? -1 : -1,
            'color': annotation.color.name,
            'style': annotation.renderStyle.name,
            'id': annotation.id,
          };
        })
        .where((annotation) => (annotation['start']! as int) >= 0)
        .toList();
    return '''(() => {
      const supportsHighlights = window.CSS?.highlights && typeof Highlight !== 'undefined';
      if (supportsHighlights) {
        for (const name of Array.from(CSS.highlights.keys())) {
          if (/^tomoread-(underline-)?(yellow|green|blue|pink)\$/.test(name)) {
            CSS.highlights.delete(name);
          }
        }
      }
      const annotations = ${jsonEncode(values)};
      const focusedAnnotationId = ${jsonEncode(focusedAnnotationId)};
      const focusRevision = $focusRevision;
      const contentRoot = document.body;
      const rangeAt = (offset) => {
        const walker = document.createTreeWalker(contentRoot, NodeFilter.SHOW_TEXT);
        let remaining = offset;
        let node;
        while ((node = walker.nextNode())) {
          if (remaining <= node.textContent.length) {
            return { node, offset: remaining };
          }
          remaining -= node.textContent.length;
        }
        return null;
      };
      const grouped = new Map();
      let focusedRange;
      for (const annotation of annotations) {
        const start = rangeAt(annotation.start);
        const end = rangeAt(annotation.end);
        if (!start || !end || annotation.end <= annotation.start) continue;
        const range = document.createRange();
        range.setStart(start.node, start.offset);
        range.setEnd(end.node, end.offset);
        const groupKey = annotation.style === 'underline'
          ? `underline-\${annotation.color}`
          : annotation.color;
        const ranges = grouped.get(groupKey) || [];
        ranges.push(range);
        grouped.set(groupKey, ranges);
        if (annotation.id === focusedAnnotationId) focusedRange = range;
      }
      if (supportsHighlights) {
        for (const [color, ranges] of grouped) {
          CSS.highlights.set(`tomoread-\${color}`, new Highlight(...ranges));
        }
      }
      if (focusedRange) {
        window.requestAnimationFrame(() => {
          const rect = focusedRange.getBoundingClientRect();
          if (window.__tomoReadPaginated === true) {
            const scrollRoot = window.__tomoReadScrollRoot?.() || document.scrollingElement || document.documentElement;
            const offset = Math.abs(scrollRoot.scrollLeft) + rect.left;
            window.__tomoReadGoToPage?.(Math.max(0, Math.round(offset / scrollRoot.clientWidth)));
          } else {
            const scrollRoot = window.__tomoReadScrollRoot?.() || document.scrollingElement || document.documentElement;
            scrollRoot.scrollTop += rect.top - 24;
            window.__tomoReadReportProgress?.();
          }
        });
      }
    })();''';
  }

  String _restoreScrollScript(double ratio, String? anchor) =>
      '''(() => {
    const root = window.__tomoReadScrollRoot?.() || document.scrollingElement || document.documentElement;
    const clampedRatio = ${ratio.clamp(0, 1)};
    const anchor = ${jsonEncode(anchor)};
    window.requestAnimationFrame(() => {
      window.setTimeout(() => {
        if (anchor && clampedRatio == 0) {
          const target = document.getElementById(anchor);
          if (target) {
            target.scrollIntoView({ block: 'start', inline: 'start' });
            window.__tomoReadReportProgress?.();
            return;
          }
        }
        const paginated = window.__tomoReadPaginated === true;
        const viewportSize = paginated ? root.clientWidth : root.clientHeight;
        const extent = paginated ? root.scrollWidth : root.scrollHeight;
        const range = Math.max(0, extent - viewportSize);
        if (paginated) {
          const pageIndex = Math.round((range * clampedRatio) / viewportSize);
          const pageOffset = Math.min(range, pageIndex * viewportSize);
          root.scrollLeft = window.__tomoReadRtl ? -pageOffset : pageOffset;
        } else {
          root.scrollTop = range * clampedRatio;
        }
        window.__tomoReadReportProgress?.();
      }, 0);
    });
  })();''';

  String _runtimeOpenScript(
    BuildContext context,
    ReadingSettings settings,
    String href,
    double ratio,
    String? anchor,
    String? cfi,
    String? fontFaceCss,
  ) {
    final payload = jsonEncode({
      'href': href,
      'ratio': ratio.clamp(0, 1),
      'anchor': anchor,
      'cfi': cfi,
      'settings': _runtimeSettings(context, settings, fontFaceCss),
    });
    return _runtimeCall(
      "runtime.command({ id: 0, type: 'open', payload: $payload })",
    );
  }

  String _runtimeSettingsScript(
    BuildContext context,
    ReadingSettings settings,
    String? fontFaceCss,
  ) => _runtimeCall(
    "runtime.command({ type: 'setSettings', payload: { settings: ${jsonEncode(_runtimeSettings(context, settings, fontFaceCss))} } })",
  );

  String _runtimeTextColoringScript(
    BuildContext context,
    ResolvedTextColoring textColoring,
  ) => _runtimeCall(
    'runtime.setTextColoring(${jsonEncode(textColoring.toRuntimeJson(dark: Theme.of(context).brightness == Brightness.dark))})',
  );

  String _runtimeCommandScript(ReaderNavigationCommand command) {
    final type = switch (command.kind) {
      ReaderNavigationKind.goToLocation => 'goToLocation',
      ReaderNavigationKind.nextPage => 'nextPage',
      ReaderNavigationKind.previousPage => 'previousPage',
    };
    return _runtimeCall(
      'runtime.command(${jsonEncode({
        'id': command.id,
        'type': type,
        'payload': {'href': command.href, 'ratio': command.ratio, 'anchor': command.anchor, 'cfi': command.cfi},
      })})',
    );
  }

  String _runtimeAnnotationScript(
    List<ReadingAnnotation> annotations,
    String? focusedAnnotationId,
  ) {
    final values = annotations
        .map(
          (annotation) => {
            'id': annotation.id,
            'href': annotation.href,
            'locator': annotation.locator,
            'color': annotation.color.name,
            'style': annotation.renderStyle.name,
          },
        )
        .toList();
    return _runtimeCall(
      'runtime.setAnnotations(${jsonEncode(values)}, ${jsonEncode(focusedAnnotationId)})',
    );
  }

  String _runtimeSearchScript(String? query) =>
      _runtimeCall('runtime.setSearchQuery(${jsonEncode(query)})');

  String _runtimeCall(String invocation) =>
      '''(() => {
    let attempts = 0;
    const run = () => {
      const runtime = window.TomoReadEpubRuntime;
      if (runtime) {
        void $invocation;
      } else if (attempts++ < 100) {
        window.setTimeout(run, 20);
      }
    };
    run();
  })();''';

  Map<String, Object?> _runtimeSettings(
    BuildContext context,
    ReadingSettings settings,
    [String? fontFaceCss],
  ) {
    final scheme = Theme.of(context).colorScheme;
    return {
      'flow': settings.layoutMode == ReaderLayoutMode.paginated
          ? 'paginated'
          : 'scrolled',
      'columnCount': settings.doubleColumn ? 2 : 1,
      'maxInlineSize': 760,
      'margin': settings.pageMargin,
      'fontFamily': settings.font.fontFamily,
      'fontFaceCss': fontFaceCss,
      'fontSize': settings.fontSize,
      'lineHeight': settings.lineHeight,
      'pageTransition': settings.pageTransition.name,
      'tapNavigationEnabled': settings.tapToTurnPages,
      'foreground': _cssColor(scheme.onSurface),
      'background': _cssColor(scheme.surface),
      'direction': direction == ReadingDirection.rtl ? 'rtl' : 'ltr',
    };
  }

  String _cssColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
}
