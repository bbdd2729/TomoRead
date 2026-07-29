import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../app/providers.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_settings.dart';

class EpubWebView extends HookConsumerWidget {
  const EpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
    required this.annotations,
    required this.initialScrollRatio,
    required this.restoreRevision,
    required this.onNavigateToHref,
    required this.onScrollPositionChanged,
    required this.onTextSelectionChanged,
  });

  static const _hostName = 'reader.tomoread';

  final String bookId;
  final String href;
  final ReadingSettings settings;
  final List<ReadingAnnotation> annotations;
  final double initialScrollRatio;
  final int restoreRevision;
  final ValueChanged<String> onNavigateToHref;
  final void Function(String href, double ratio) onScrollPositionChanged;
  final ValueChanged<ReaderTextSelection> onTextSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extractedDirectory = ref.watch(
      epubExtractedDirectoryProvider(bookId),
    );
    final controller = useMemoized(WebviewController.new);
    final initialized = useState(false);
    final initializationError = useState<Object?>(null);
    final styleScript = _styleScript(context, settings);
    final annotationScript = _annotationScript(annotations, href);
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
          _restoreScrollScript(initialScrollRatio),
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
    }, [controller, href, initialized.value, styleScript]);

    useEffect(() {
      final subscription = controller.url.listen((url) {
        final uri = Uri.tryParse(url);
        if (uri?.host != _hostName) return;
        final nextHref = uri!.path.startsWith('/')
            ? uri.path.substring(1)
            : uri.path;
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
          if (messageHref is String && ratio is num) {
            onScrollPositionChanged(messageHref, ratio.toDouble());
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
    }, [initialized.value, href, restoreRevision]);

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
    final css =
        '''
html { color-scheme: ${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}; }
html, body { background: ${_cssColor(colorScheme.surface)} !important; color: ${_cssColor(colorScheme.onSurface)} !important; }
body { box-sizing: border-box; max-width: 980px; margin: 0 auto; padding: ${settings.pageMargin}px; font-family: ${jsonEncode(settings.font.fontFamily)} !important; font-size: ${settings.fontSize}px !important; line-height: ${settings.lineHeight} !important; }
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
      if (!window.__tomoReadScrollListener) {
        let scheduled = false;
        const reportProgress = () => {
          if (scheduled) return;
          scheduled = true;
          window.setTimeout(() => {
            scheduled = false;
            const root = document.scrollingElement || document.documentElement;
            const range = Math.max(0, root.scrollHeight - window.innerHeight);
            const ratio = range === 0 ? 0 : root.scrollTop / range;
            window.chrome?.webview?.postMessage({
              type: 'scrollProgress',
              href: window.location.pathname.replace(/^\\//, ''),
              ratio,
            });
          }, 200);
        };
        window.addEventListener('scroll', reportProgress, { passive: true });
        window.__tomoReadScrollListener = true;
      }
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
    })();''';
  }

  String _annotationScript(List<ReadingAnnotation> annotations, String href) {
    final values = annotations
        .where((annotation) => annotation.href == href)
        .map((annotation) {
          final offsets = annotation.locator.split(':');
          return {
            'start': int.tryParse(offsets.first) ?? -1,
            'end': offsets.length == 2 ? int.tryParse(offsets.last) ?? -1 : -1,
            'color': annotation.color.name,
          };
        })
        .where((annotation) => (annotation['start']! as int) >= 0)
        .toList();
    return '''(() => {
      if (!window.CSS?.highlights || typeof Highlight === 'undefined') return;
      for (const name of Array.from(CSS.highlights.keys())) {
        if (name.startsWith('tomoread-')) CSS.highlights.delete(name);
      }
      const annotations = ${jsonEncode(values)};
      const root = document.body;
      const rangeAt = (offset) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
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
      }
      for (const [color, ranges] of grouped) {
        CSS.highlights.set(`tomoread-\${color}`, new Highlight(...ranges));
      }
    })();''';
  }

  String _restoreScrollScript(double ratio) =>
      '''(() => {
    const root = document.scrollingElement || document.documentElement;
    const clampedRatio = ${ratio.clamp(0, 1)};
    window.requestAnimationFrame(() => {
      window.setTimeout(() => {
        const range = Math.max(0, root.scrollHeight - window.innerHeight);
        root.scrollTop = range * clampedRatio;
      }, 0);
    });
  })();''';

  String _cssColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
}
