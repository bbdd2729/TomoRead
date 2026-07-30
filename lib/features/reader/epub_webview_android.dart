import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/providers.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reading_settings.dart';

class AndroidEpubWebView extends HookConsumerWidget {
  const AndroidEpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
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
    required this.onToggleControls,
  });

  final String bookId;
  final String href;
  final ReadingSettings settings;
  final double initialScrollRatio;
  final String? initialAnchor;
  final ReadingDirection direction;
  final int? requestedPage;
  final int restoreRevision;
  final ValueChanged<String> onNavigateToHref;
  final void Function(String href, double ratio, String? anchor, String? cfi)
  onScrollPositionChanged;
  final void Function(int pageIndex, int pageCount) onPaginationChanged;
  final VoidCallback onRequestPrevious;
  final VoidCallback onRequestNext;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extractedDirectory = ref.watch(
      epubExtractedDirectoryProvider(bookId),
    );
    final readerSession = ref.watch(epubReaderSessionProvider(bookId));
    final epubManifest = ref.watch(readerManifestProvider(bookId));
    final error = useState<Object?>(null);
    final style = _styleScript(context, settings, direction);
    final runtimeScript = epubManifest.value == null
        ? null
        : _runtimeOpenScript(
            context,
            settings,
            href,
            initialScrollRatio,
            initialAnchor,
            epubManifest.value!,
          );
    final runtimeScriptRef = useRef<String?>(runtimeScript);
    runtimeScriptRef.value = runtimeScript;
    final navigationHandlerRef = useRef<ValueChanged<String>?>(null);
    navigationHandlerRef.value = onNavigateToHref;
    final messageHandlerRef = useRef<void Function(String)?>(null);
    messageHandlerRef.value = (rawMessage) =>
        _handleRuntimeMessage(rawMessage, error);
    final controller = useMemoized(() {
      late final WebViewController webViewController;
      webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              final script = runtimeScriptRef.value;
              if (script != null) {
                unawaited(webViewController.runJavaScript(script));
              }
            },
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              if (uri != null && uri.scheme == 'file') {
                final nextHref = uri.pathSegments.isEmpty
                    ? null
                    : uri.pathSegments.last;
                if (nextHref != null &&
                    nextHref != _pathWithoutFragment(href)) {
                  navigationHandlerRef.value?.call(nextHref);
                  return NavigationDecision.prevent;
                }
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..addJavaScriptChannel(
          'TomoRead',
          onMessageReceived: (message) {
            messageHandlerRef.value?.call(message.message);
          },
        );
      return webViewController;
    });

    useEffect(
      () {
        final useRuntime = settings.layoutMode == ReaderLayoutMode.paginated;
        if (useRuntime && runtimeScript == null) return null;
        final directory = useRuntime
            ? readerSession.value?.directoryPath
            : extractedDirectory.value;
        if (directory == null) return null;
        final file = useRuntime
            ? File(path.join(directory, '.tomoread-reader', 'index.html'))
            : File(path.join(directory, _pathWithoutFragment(href)));
        Future<void> loadChapter() async {
          if (!await file.exists()) {
            error.value = StateError('EPUB chapter is unavailable: $href');
            return;
          }
          try {
            await controller.loadFile(file.path);
          } catch (exception) {
            error.value = exception;
          }
        }

        unawaited(loadChapter());
        return null;
      },
      [
        controller,
        extractedDirectory.value,
        readerSession.value?.directoryPath,
        epubManifest.value,
        href,
        settings.layoutMode,
      ],
    );

    useEffect(
      () {
        Future<void> applyStyleAndPosition() async {
          try {
            if (settings.layoutMode == ReaderLayoutMode.paginated) {
              if (runtimeScript != null) {
                await controller.runJavaScript(runtimeScript);
              }
            } else {
              await controller.runJavaScript(style);
              await controller.runJavaScript(
                _restoreScript(initialScrollRatio, initialAnchor),
              );
            }
          } catch (_) {
            // The Android WebView may still be loading the next chapter.
          }
        }

        unawaited(applyStyleAndPosition());
        return null;
      },
      [controller, href, style, runtimeScript, initialAnchor, restoreRevision],
    );

    useEffect(() {
      final page = requestedPage;
      if (settings.layoutMode != ReaderLayoutMode.paginated || page == null) {
        return null;
      }
      unawaited(controller.runJavaScript(_runtimeGoToPageScript(page)));
      return null;
    }, [controller, requestedPage, settings.layoutMode]);

    if (extractedDirectory.hasError ||
        readerSession.hasError ||
        (settings.layoutMode == ReaderLayoutMode.paginated &&
            epubManifest.hasError) ||
        error.value != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to start EPUB renderer: ${error.value ?? extractedDirectory.error ?? readerSession.error ?? epubManifest.error}',
          ),
        ),
      );
    }
    if (extractedDirectory.isLoading ||
        (settings.layoutMode == ReaderLayoutMode.paginated &&
            (readerSession.isLoading || epubManifest.isLoading))) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }

  void _handleRuntimeMessage(String rawMessage, ValueNotifier<Object?> error) {
    Object? runtimeMessage;
    try {
      runtimeMessage = jsonDecode(rawMessage);
    } on FormatException {
      // Legacy scroll and tap messages use a compact pipe format.
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'runtimeRelocate') {
      final messageHref = runtimeMessage['href'];
      final ratio = runtimeMessage['ratio'];
      if (messageHref is String && ratio is num) {
        onScrollPositionChanged(
          messageHref,
          ratio.toDouble(),
          runtimeMessage['anchor'] as String?,
          runtimeMessage['cfi'] as String?,
        );
      }
      final pageIndex = runtimeMessage['pageIndex'];
      final pageCount = runtimeMessage['pageCount'];
      if (pageIndex is num && pageCount is num) {
        onPaginationChanged(pageIndex.toInt(), pageCount.toInt());
      }
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'runtimeError') {
      error.value = StateError(
        runtimeMessage['message'] ?? 'Unknown runtime error',
      );
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'readerControls') {
      onToggleControls();
      return;
    }
    final parts = rawMessage.split('|');
    switch (parts.first) {
      case 'scroll':
        if (parts.length < 2) return;
        final ratio = double.tryParse(parts[1]);
        if (ratio != null) onScrollPositionChanged(href, ratio, null, null);
      case 'tap':
        onToggleControls();
    }
  }

  String _pathWithoutFragment(String value) => value.split('#').first;

  String _runtimeOpenScript(
    BuildContext context,
    ReadingSettings settings,
    String href,
    double ratio,
    String? anchor,
    EpubManifest manifest,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final payload = jsonEncode({
      'href': href,
      'ratio': ratio.clamp(0, 1),
      'anchor': anchor,
      'session': {'manifest': manifest.toJson()},
      'settings': {
        'flow': 'paginated',
        'columnCount': settings.doubleColumn ? 2 : 1,
        'maxInlineSize': 760,
        'margin': settings.pageMargin,
        'fontFamily': settings.font.fontFamily,
        'fontSize': settings.fontSize,
        'lineHeight': settings.lineHeight,
        'foreground':
            '#${scheme.onSurface.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        'background':
            '#${scheme.surface.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        'direction': direction == ReadingDirection.rtl ? 'rtl' : 'ltr',
        'pageTransition': settings.pageTransition.name,
      },
    });
    return '''(() => {
      let attempts = 0;
      const open = () => {
        const runtime = window.TomoReadEpubRuntime;
        if (runtime) { void runtime.open($payload); }
        else if (attempts++ < 100) { window.setTimeout(open, 20); }
      };
      open();
    })();''';
  }

  String _runtimeGoToPageScript(int pageIndex) =>
      '''(() => {
    const runtime = window.TomoReadEpubRuntime;
    if (runtime) void runtime.goToPage(${pageIndex.clamp(0, 100000)});
  })();''';

  String _styleScript(
    BuildContext context,
    ReadingSettings readingSettings,
    ReadingDirection readingDirection,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        '#${scheme.surface.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    final foreground =
        '#${scheme.onSurface.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    final direction = readingDirection == ReadingDirection.rtl ? 'rtl' : 'ltr';
    return '''(() => {
      document.documentElement.style.background = '$background';
      document.documentElement.style.color = '$foreground';
      document.body.style.cssText += ';background:$background;color:$foreground;font-family:${readingSettings.font.fontFamily};font-size:${readingSettings.fontSize}px;line-height:${readingSettings.lineHeight};padding:${readingSettings.pageMargin}px;direction:$direction;box-sizing:border-box;';
      if (!window.__tomoReadProgress) {
        let pending = false;
        window.addEventListener('scroll', () => {
          if (pending) return;
          pending = true;
          setTimeout(() => {
            pending = false;
            const root = document.scrollingElement || document.documentElement;
            const range = Math.max(0, root.scrollHeight - window.innerHeight);
            TomoRead.postMessage('scroll|' + (range === 0 ? 0 : root.scrollTop / range));
          }, 200);
        }, {passive:true});
        window.__tomoReadProgress = true;
      }
      if (!window.__tomoReadControlsListener) {
        window.addEventListener('click', (event) => {
          const target = event.target;
          if (target?.closest?.('a, button, input, textarea, select')) return;
          if (window.getSelection?.()?.toString().trim()) return;
          const x = event.clientX / window.innerWidth;
          const y = event.clientY / window.innerHeight;
          if (x >= .25 && x <= .75 && y >= .25 && y <= .75) {
            TomoRead.postMessage('tap');
          }
        });
        window.__tomoReadControlsListener = true;
      }
    })();''';
  }

  String _restoreScript(double ratio, String? anchor) {
    final clamped = ratio.clamp(0, 1);
    final encodedAnchor = anchor == null
        ? 'null'
        : "'${anchor.replaceAll("'", "\\'")}'";
    return '''(() => { const anchor = $encodedAnchor; const root = document.scrollingElement || document.documentElement; const target = anchor && document.getElementById(anchor); if (target) { target.scrollIntoView(); } else { root.scrollTop = Math.max(0, root.scrollHeight - window.innerHeight) * $clamped; } })();''';
  }
}
