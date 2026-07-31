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
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_settings.dart';
import 'reader_navigation_command.dart';

class AndroidEpubWebView extends HookConsumerWidget {
  const AndroidEpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
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

  final String bookId;
  final String href;
  final ReadingSettings settings;
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
    final extractedDirectory = ref.watch(
      epubExtractedDirectoryProvider(bookId),
    );
    final readerSession = ref.watch(epubReaderSessionProvider(bookId));
    final epubManifest = ref.watch(readerManifestProvider(bookId));
    final error = useState<Object?>(null);
    final style = _styleScript(context, settings, direction);
    final runtimeSettingsScript = _runtimeSettingsScript(context, settings);
    final runtimeScript = epubManifest.value == null
        ? null
        : _runtimeOpenScript(
            context,
            settings,
            href,
            initialScrollRatio,
            initialAnchor,
            initialCfi,
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

    useEffect(() {
      Future<void> applyStyleAndPosition() async {
        try {
          if (settings.layoutMode != ReaderLayoutMode.paginated) {
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
    }, [controller, href, style, restoreRevision, settings.layoutMode]);

    useEffect(() {
      if (settings.layoutMode != ReaderLayoutMode.paginated) return null;
      unawaited(controller.runJavaScript(runtimeSettingsScript));
      return null;
    }, [controller, runtimeSettingsScript, settings.layoutMode]);

    useEffect(() {
      final command = navigationCommand;
      if (settings.layoutMode != ReaderLayoutMode.paginated ||
          command == null) {
        return null;
      }
      unawaited(controller.runJavaScript(_runtimeCommandScript(command)));
      return null;
    }, [controller, navigationCommand, settings.layoutMode]);

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
        runtimeMessage['type'] == 'commandCompleted') {
      final commandId = runtimeMessage['id'];
      if (commandId is num) onNavigationCommandFinished(commandId.toInt());
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'commandFailed') {
      final commandId = runtimeMessage['id'];
      if (commandId is num) onNavigationCommandFinished(commandId.toInt());
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'textSelection') {
      final messageHref = runtimeMessage['href'];
      final text = runtimeMessage['text'];
      final startOffset = runtimeMessage['startOffset'];
      final endOffset = runtimeMessage['endOffset'];
      final cfi = runtimeMessage['cfi'];
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
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'selectionContextMenu') {
      final messageHref = runtimeMessage['href'];
      final text = runtimeMessage['text'];
      final startOffset = runtimeMessage['startOffset'];
      final endOffset = runtimeMessage['endOffset'];
      final cfi = runtimeMessage['cfi'];
      final x = runtimeMessage['x'];
      final y = runtimeMessage['y'];
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
    String? cfi,
    EpubManifest manifest,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final payload = jsonEncode({
      'href': href,
      'ratio': ratio.clamp(0, 1),
      'anchor': anchor,
      'cfi': cfi,
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
        if (runtime) { void runtime.command({ id: 0, type: 'open', payload: $payload }); }
        else if (attempts++ < 100) { window.setTimeout(open, 20); }
      };
      open();
    })();''';
  }

  String _runtimeCommandScript(ReaderNavigationCommand command) {
    final type = switch (command.kind) {
      ReaderNavigationKind.goToLocation => 'goToLocation',
      ReaderNavigationKind.nextPage => 'nextPage',
      ReaderNavigationKind.previousPage => 'previousPage',
    };
    return '''(() => {
      const runtime = window.TomoReadEpubRuntime;
      if (runtime) void runtime.command(${jsonEncode({
      'id': command.id,
      'type': type,
      'payload': {'href': command.href, 'ratio': command.ratio, 'anchor': command.anchor, 'cfi': command.cfi},
    })});
    })();''';
  }

  String _runtimeSettingsScript(
    BuildContext context,
    ReadingSettings settings,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return '''(() => {
      const runtime = window.TomoReadEpubRuntime;
      if (runtime) void runtime.command(${jsonEncode({
      'type': 'setSettings',
      'payload': {
        'settings': {'flow': 'paginated', 'columnCount': settings.doubleColumn ? 2 : 1, 'maxInlineSize': 760, 'margin': settings.pageMargin, 'fontFamily': settings.font.fontFamily, 'fontSize': settings.fontSize, 'lineHeight': settings.lineHeight, 'foreground': _cssColor(scheme.onSurface), 'background': _cssColor(scheme.surface), 'direction': direction == ReadingDirection.rtl ? 'rtl' : 'ltr', 'pageTransition': settings.pageTransition.name},
      },
    })});
    })();''';
  }

  String _cssColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

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
