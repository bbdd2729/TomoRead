import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../app/providers.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_settings.dart';
import 'epub_webview_android.dart';

class EpubWebView extends HookConsumerWidget {
  const EpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
    required this.annotations,
    required this.focusedAnnotationId,
    required this.annotationFocusRevision,
    required this.initialScrollRatio,
    required this.initialAnchor,
    required this.direction,
    required this.requestedPage,
    required this.restoreRevision,
    required this.onNavigateToHref,
    required this.onScrollPositionChanged,
    required this.onPaginationChanged,
    required this.onRequestPrevious,
    required this.onRequestNext,
    required this.onTextSelectionChanged,
    required this.onToggleControls,
  });

  static const _hostName = 'reader.tomoread';

  final String bookId;
  final String href;
  final ReadingSettings settings;
  final List<ReadingAnnotation> annotations;
  final String? focusedAnnotationId;
  final int annotationFocusRevision;
  final double initialScrollRatio;
  final String? initialAnchor;
  final ReadingDirection direction;
  final int? requestedPage;
  final int restoreRevision;
  final ValueChanged<String> onNavigateToHref;
  final void Function(String href, double ratio, String? anchor)
  onScrollPositionChanged;
  final void Function(int pageIndex, int pageCount) onPaginationChanged;
  final VoidCallback onRequestPrevious;
  final VoidCallback onRequestNext;
  final ValueChanged<ReaderTextSelection> onTextSelectionChanged;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) {
      return AndroidEpubWebView(
        bookId: bookId,
        href: href,
        settings: settings,
        initialScrollRatio: initialScrollRatio,
        initialAnchor: initialAnchor,
        direction: direction,
        restoreRevision: restoreRevision,
        onNavigateToHref: onNavigateToHref,
        onScrollPositionChanged: onScrollPositionChanged,
        onToggleControls: onToggleControls,
      );
    }
    final extractedDirectory = ref.watch(
      epubExtractedDirectoryProvider(bookId),
    );
    final controller = useMemoized(WebviewController.new);
    final initialized = useState(false);
    final initializationError = useState<Object?>(null);
    final styleScript = _styleScript(context, settings);
    final annotationScript = _annotationScript(
      annotations,
      href,
      focusedAnnotationId,
      annotationFocusRevision,
    );
    final resourceDirectory = extractedDirectory.value;

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

    useEffect(() {
      if (!initialized.value) return null;
      final subscription = controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          unawaited(applyStyle());
          unawaited(applyAnnotations());
          unawaited(restoreScrollPosition());
        }
      });
      unawaited(controller.loadUrl(_chapterUrl(href)));
      return subscription.cancel;
    }, [controller, href, initialized.value]);

    useEffect(() {
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
    }, [controller, href, onNavigateToHref]);

    useEffect(() {
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
            );
          }
        } else if (message['type'] == 'pageChanged') {
          final pageIndex = message['pageIndex'];
          final pageCount = message['pageCount'];
          if (pageIndex is num && pageCount is num) {
            onPaginationChanged(pageIndex.toInt(), pageCount.toInt());
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
              ),
            );
          }
        } else if (message['type'] == 'readerControls') {
          onToggleControls();
        }
      });
      return subscription.cancel;
    }, [controller, onScrollPositionChanged, onTextSelectionChanged]);

    useEffect(() {
      if (initialized.value) unawaited(applyStyle());
      return null;
    }, [initialized.value, styleScript]);

    useEffect(() {
      if (initialized.value) unawaited(applyAnnotations());
      return null;
    }, [initialized.value, annotationScript]);

    useEffect(() {
      if (initialized.value) unawaited(restoreScrollPosition());
      return null;
    }, [initialized.value, href, initialAnchor, restoreRevision]);

    useEffect(() {
      final page = requestedPage;
      if (!initialized.value || page == null) return null;
      unawaited(controller.executeScript(_goToPageScript(page)));
      return null;
    }, [controller, href, initialized.value, requestedPage]);

    useEffect(
      () =>
          () => unawaited(controller.dispose()),
      [controller],
    );

    if (extractedDirectory.hasError || initializationError.value != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '无法启动 EPUB 渲染器：${initializationError.value ?? extractedDirectory.error}',
          ),
        ),
      );
    }
    if (extractedDirectory.isLoading || !initialized.value) {
      return const Center(child: CircularProgressIndicator());
    }
    return Webview(controller);
  }

  String _chapterUrl(String chapterHref) =>
      Uri(scheme: 'https', host: _hostName, path: chapterHref).toString();

  String _styleScript(BuildContext context, ReadingSettings settings) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPaginated = settings.layoutMode == ReaderLayoutMode.paginated;
    final readingDirection = direction == ReadingDirection.rtl ? 'rtl' : 'ltr';
    final margin = settings.pageMargin;
    final layoutCss = isPaginated
        ? '''
html {
  height: 100%;
  overflow-x: auto !important;
  overflow-y: hidden !important;
  scroll-snap-type: x mandatory;
}
body {
  height: 100vh !important;
  width: 100vw !important;
  min-width: 100vw !important;
  max-width: none !important;
  margin: 0 !important;
  padding: ${margin}px !important;
  column-width: calc((100vw - ${margin * 3}px) / 2) !important;
  column-gap: ${margin}px !important;
  column-fill: auto !important;
  overflow: visible !important;
}
@media (max-width: 720px) {
  body {
    column-width: calc(100vw - ${margin * 2}px) !important;
  }
}
body > * { break-inside: avoid; }
'''
        : '''
html { overflow-x: hidden; overflow-y: auto; }
body {
  max-width: 980px;
  margin: 0 auto;
  padding: ${margin}px;
}
''';
    final css =
        '''
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
      if (!window.__tomoReadScrollListener) {
        let scheduled = false;
        const reportProgress = () => {
          if (scheduled) return;
          scheduled = true;
          window.setTimeout(() => {
            scheduled = false;
            const root = document.scrollingElement || document.documentElement;
            const paginated = window.__tomoReadPaginated === true;
            const viewportSize = paginated ? window.innerWidth : window.innerHeight;
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
        window.addEventListener('scroll', reportProgress, { passive: true });
        window.__tomoReadReportProgress = reportProgress;
        window.__tomoReadScrollListener = true;
      }
      window.__tomoReadGoToPage = (requestedPage) => {
        const root = document.scrollingElement || document.documentElement;
        if (window.__tomoReadPaginated !== true) return;
        const viewportSize = window.innerWidth;
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
            const root = document.scrollingElement || document.documentElement;
            const ratio = Number.isFinite(window.__tomoReadLastRatio)
              ? window.__tomoReadLastRatio
              : 0;
            const range = Math.max(0, root.scrollWidth - window.innerWidth);
            root.scrollLeft = window.__tomoReadRtl ? -range * ratio : range * ratio;
            window.__tomoReadReportProgress?.();
          }, 80);
        });
        window.__tomoReadNavigationListener = true;
      }
      window.__tomoReadReportProgress?.();
      if (!window.__tomoReadSelectionListener) {
        const reportSelection = () => {
          const selection = window.getSelection();
          if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return;
          const range = selection.getRangeAt(0);
          if (!document.body.contains(range.commonAncestorContainer)) return;
          const text = selection.toString().replace(/\\s+/g, ' ').trim();
          if (!text) return;
          const before = range.cloneRange();
          before.selectNodeContents(document.body);
          before.setEnd(range.startContainer, range.startOffset);
          window.chrome?.webview?.postMessage({
            type: 'textSelection',
            href: window.location.pathname.replace(/^\\//, ''),
            text,
            startOffset: before.toString().length,
            endOffset: before.toString().length + range.toString().length,
          });
        };
        document.addEventListener('selectionchange', reportSelection);
        window.__tomoReadSelectionListener = true;
      }
      if (!window.__tomoReadControlsListener) {
        window.addEventListener('click', (event) => {
          const target = event.target;
          if (target?.closest?.('a, button, input, textarea, select')) return;
          if (window.getSelection?.()?.toString().trim()) return;
          const x = event.clientX / window.innerWidth;
          const y = event.clientY / window.innerHeight;
          if (x < .25 || x > .75 || y < .25 || y > .75) return;
          window.chrome?.webview?.postMessage({ type: 'readerControls' });
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
            'id': annotation.id,
          };
        })
        .where((annotation) => (annotation['start']! as int) >= 0)
        .toList();
    return '''(() => {
      const supportsHighlights = window.CSS?.highlights && typeof Highlight !== 'undefined';
      if (supportsHighlights) {
        for (const name of Array.from(CSS.highlights.keys())) {
          if (name.startsWith('tomoread-')) CSS.highlights.delete(name);
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
        const ranges = grouped.get(annotation.color) || [];
        ranges.push(range);
        grouped.set(annotation.color, ranges);
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
            const scrollRoot = document.scrollingElement || document.documentElement;
            const offset = Math.abs(scrollRoot.scrollLeft) + rect.left;
            window.__tomoReadGoToPage?.(Math.max(0, Math.round(offset / window.innerWidth)));
          } else {
            const scrollRoot = document.scrollingElement || document.documentElement;
            scrollRoot.scrollTop += rect.top - 24;
            window.__tomoReadReportProgress?.();
          }
        });
      }
    })();''';
  }

  String _restoreScrollScript(double ratio, String? anchor) =>
      '''(() => {
    const root = document.scrollingElement || document.documentElement;
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
        const viewportSize = paginated ? window.innerWidth : window.innerHeight;
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

  String _goToPageScript(int pageIndex) =>
      'window.__tomoReadGoToPage?.(${pageIndex.clamp(0, 100000)});';

  String _cssColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
}
