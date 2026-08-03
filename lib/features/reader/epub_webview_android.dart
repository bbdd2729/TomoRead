import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/app_diagnostics.dart';
import '../../app/providers.dart';
import '../../domain/models/epub_interaction.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_coloring.dart';
import 'android_epub_resource_handler.dart';
import 'epub_interaction_presenter.dart';
import 'reader_navigation_command.dart';

enum _AndroidEpubLoadPhase { loading, ready, failed }

class AndroidEpubWebView extends HookConsumerWidget {
  const AndroidEpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
    required this.textColoring,
    this.ttsHighlightHref,
    this.ttsHighlightText,
    this.ttsHighlightStart,
    this.ttsHighlightEnd,
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
    required this.onAutoScrollChanged,
    required this.onTextSelectionChanged,
    required this.onSelectionContextMenu,
    required this.onToggleControls,
  });

  final String bookId;
  final String href;
  final ReadingSettings settings;
  final ResolvedTextColoring textColoring;
  final String? ttsHighlightHref;
  final String? ttsHighlightText;
  final int? ttsHighlightStart;
  final int? ttsHighlightEnd;
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
  final ValueChanged<bool> onAutoScrollChanged;
  final ValueChanged<ReaderTextSelection> onTextSelectionChanged;
  final ValueChanged<ReaderSelectionContextMenu> onSelectionContextMenu;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerSession = ref.watch(epubReaderSessionProvider(bookId));
    final epubManifest = ref.watch(readerManifestProvider(bookId));
    final fontFaceCss = ref.watch(epubFontFaceCssProvider(settings.font)).value;
    final error = useState<Object?>(null);
    final loadPhase = useState(_AndroidEpubLoadPhase.loading);
    final retryRevision = useState(0);
    final readinessTimer = useRef<Timer?>(null);
    final active = useRef(true);
    final runtimeSettingsScript = _runtimeSettingsScript(
      context,
      settings,
      fontFaceCss,
    );
    final runtimeTextColoringScript = _runtimeTextColoringScript(
      context,
      textColoring,
    );
    final runtimeTtsHighlightScript = _runtimeTtsHighlightScript(
      href: ttsHighlightHref,
      text: ttsHighlightText,
      start: ttsHighlightStart,
      end: ttsHighlightEnd,
    );
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
            fontFaceCss,
          );
    final runtimeScriptRef = useRef<String?>(runtimeScript);
    runtimeScriptRef.value = runtimeScript;
    final textColoringScriptRef = useRef(runtimeTextColoringScript);
    textColoringScriptRef.value = runtimeTextColoringScript;
    final runtimeLoaded = useRef(false);
    final runtimeBridgeReady = useRef(false);
    void reportReady() {
      if (!active.value) return;
      final wasReady = loadPhase.value == _AndroidEpubLoadPhase.ready;
      readinessTimer.value?.cancel();
      readinessTimer.value = null;
      error.value = null;
      loadPhase.value = _AndroidEpubLoadPhase.ready;
      if (!wasReady) {
        AppDiagnostics.info('epub.webview', 'renderer ready');
      }
    }

    void reportFailure(Object exception) {
      if (!active.value) return;
      readinessTimer.value?.cancel();
      readinessTimer.value = null;
      error.value = exception;
      loadPhase.value = _AndroidEpubLoadPhase.failed;
      AppDiagnostics.error(
        'epub.webview',
        'renderer failed',
        error: exception,
      );
    }

    final messageHandlerRef = useRef<void Function(String)?>(null);
    messageHandlerRef.value = (rawMessage) => _handleRuntimeMessage(
      context,
      rawMessage,
      epubManifest.value,
      () {
        runtimeBridgeReady.value = true;
        reportReady();
      },
      reportReady,
      reportFailure,
      onAutoScrollChanged,
    );
    final resourceHandler = useMemoized<AndroidEpubResourceHandler?>(
      () {
        final directory = readerSession.value?.directoryPath;
        return directory == null
            ? null
            : AndroidEpubResourceHandler(
                bookId: bookId,
                bookDirectoryPath: directory,
              );
      },
      [bookId, readerSession.value?.directoryPath],
    );
    final controller = useState<InAppWebViewController?>(null);

    useEffect(() {
      runtimeLoaded.value = false;
      readinessTimer.value?.cancel();
      error.value = null;
      loadPhase.value = _AndroidEpubLoadPhase.loading;
      return null;
    }, [bookId, retryRevision.value]);

    useEffect(
      () => () {
        active.value = false;
        readinessTimer.value?.cancel();
        readinessTimer.value = null;
      },
      const [],
    );

    useEffect(
      () {
        final webViewController = controller.value;
        if (runtimeScript == null ||
            runtimeLoaded.value ||
            resourceHandler == null ||
            webViewController == null) {
          return null;
        }
        Future<void> loadChapter() async {
          final entryPoint = await resourceHandler.load(
            resourceHandler.runtimeEntryPoint,
          );
          if (!entryPoint.isSuccess) {
            AppDiagnostics.error(
              'epub.webview',
              'runtime entry point missing',
              details: {'statusCode': entryPoint.statusCode},
            );
            reportFailure(StateError('EPUB chapter is unavailable: $href'));
            return;
          }
          try {
            AppDiagnostics.info(
              'epub.webview',
              'loading virtual runtime entry point',
              details: {'url': resourceHandler.runtimeEntryPoint.toString()},
            );
            await webViewController.loadUrl(
              urlRequest: URLRequest(
                url: WebUri(resourceHandler.runtimeEntryPoint.toString()),
              ),
            );
          } catch (exception, stackTrace) {
            AppDiagnostics.error(
              'epub.webview',
              'runtime entry point load failed',
              error: exception,
              stackTrace: stackTrace,
            );
            reportFailure(exception);
          }
        }

        runtimeLoaded.value = true;
        unawaited(loadChapter());
        return null;
      },
      [
        controller.value,
        resourceHandler,
        epubManifest.value,
        bookId,
        retryRevision.value,
      ],
    );

    useEffect(() {
      final webViewController = controller.value;
      if (loadPhase.value == _AndroidEpubLoadPhase.ready &&
          webViewController != null) {
        unawaited(
          _runJavaScript(
            webViewController,
            runtimeSettingsScript,
            onError: reportFailure,
          ),
        );
      }
      return null;
    }, [controller.value, runtimeSettingsScript, loadPhase.value]);

    useEffect(() {
      final webViewController = controller.value;
      if (loadPhase.value == _AndroidEpubLoadPhase.ready &&
          webViewController != null) {
        unawaited(
          _runJavaScript(
            webViewController,
            runtimeTextColoringScript,
            onError: reportFailure,
          ),
        );
      }
      return null;
    }, [controller.value, runtimeTextColoringScript, loadPhase.value]);

    useEffect(() {
      final webViewController = controller.value;
      if (loadPhase.value == _AndroidEpubLoadPhase.ready &&
          webViewController != null) {
        unawaited(
          _runJavaScript(
            webViewController,
            runtimeTtsHighlightScript,
            onError: reportFailure,
          ),
        );
      }
      return null;
    }, [controller.value, runtimeTtsHighlightScript, loadPhase.value]);

    useEffect(() {
      final command = navigationCommand;
      final webViewController = controller.value;
      if (command == null ||
          loadPhase.value != _AndroidEpubLoadPhase.ready ||
          webViewController == null) {
        return null;
      }
      unawaited(
        _runJavaScript(
          webViewController,
          _runtimeCommandScript(command),
          onError: reportFailure,
        ),
      );
      return null;
    }, [controller.value, navigationCommand, loadPhase.value]);

    if (readerSession.hasError || epubManifest.hasError) {
      final providerError = readerSession.error ?? epubManifest.error;
      return _AndroidEpubLoadFailure(
        message: '无法准备 EPUB 阅读资源：$providerError',
        onRetry: () {
          ref.invalidate(epubReaderSessionProvider(bookId));
          ref.invalidate(readerManifestProvider(bookId));
        },
      );
    }
    if (readerSession.isLoading || epubManifest.isLoading) {
      return const _AndroidEpubLoading();
    }
    if (resourceHandler == null) {
      return const _AndroidEpubLoading();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        InAppWebView(
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            javaScriptEnabled: true,
            resourceCustomSchemes: [AndroidEpubResourceHandler.virtualScheme],
            useShouldOverrideUrlLoading: true,
          ),
          onWebViewCreated: (webViewController) {
            webViewController.addJavaScriptHandler(
              handlerName: 'TomoRead',
              callback: (arguments) {
                if (arguments.isNotEmpty && arguments.first is String) {
                  messageHandlerRef.value?.call(arguments.first as String);
                }
                return null;
              },
            );
            controller.value = webViewController;
            AppDiagnostics.info('epub.webview', 'virtual-origin webview created');
          },
          onLoadStart: (_, url) {
            if (Uri.tryParse(url?.toString() ?? '')?.scheme !=
                AndroidEpubResourceHandler.virtualScheme) {
              return;
            }
            if (!active.value) return;
            readinessTimer.value?.cancel();
            runtimeBridgeReady.value = false;
            error.value = null;
            loadPhase.value = _AndroidEpubLoadPhase.loading;
            AppDiagnostics.info(
              'epub.webview',
              'runtime page started',
              details: {'url': url?.toString()},
            );
          },
          onLoadStop: (webViewController, url) {
            if (Uri.tryParse(url?.toString() ?? '')?.scheme !=
                AndroidEpubResourceHandler.virtualScheme) {
              return;
            }
            if (!active.value) return;
            AppDiagnostics.info(
              'epub.webview',
              'runtime page finished',
              details: {
                'url': url?.toString(),
                'bridgeReady': runtimeBridgeReady.value,
              },
            );
            final script = runtimeScriptRef.value;
            if (script == null) return;
            unawaited(
              _runJavaScript(
                webViewController,
                script,
                onError: reportFailure,
              ),
            );
            unawaited(
              _runJavaScript(
                webViewController,
                textColoringScriptRef.value,
                onError: reportFailure,
              ),
            );
            if (runtimeBridgeReady.value) return;
            readinessTimer.value?.cancel();
            readinessTimer.value = Timer(const Duration(seconds: 12), () {
              AppDiagnostics.error(
                'epub.webview',
                'runtime readiness timed out',
                details: {
                  'timeoutSeconds': 12,
                  'url': url?.toString(),
                },
              );
              reportFailure(
                StateError('EPUB renderer did not become ready in time.'),
              );
            });
            AppDiagnostics.info(
              'epub.webview',
              'waiting for runtime bridge',
              details: {'timeoutSeconds': 12},
            );
          },
          onLoadResourceWithCustomScheme: (_, request) async {
            final response = await resourceHandler.loadRequestUrl(
              request.url.toString(),
              method: request.method,
            );
            return CustomSchemeResponse(
              data: response.data,
              contentType: response.contentType,
            );
          },
          shouldOverrideUrlLoading: (_, navigationAction) async {
            final uri = Uri.tryParse(navigationAction.request.url.toString());
            final allowed =
                uri?.scheme == AndroidEpubResourceHandler.virtualScheme &&
                uri?.host == AndroidEpubResourceHandler.virtualHost;
            return allowed
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL;
          },
          onReceivedError: (_, request, webError) {
            if (Uri.tryParse(request.url.toString())?.scheme !=
                AndroidEpubResourceHandler.virtualScheme) {
              return;
            }
            AppDiagnostics.error(
              'epub.webview',
              'web resource failed',
              details: {
                'mainFrame': request.isForMainFrame == true,
                'url': request.url.toString(),
              },
              error: StateError(webError.description),
            );
            if (request.isForMainFrame == true) {
              reportFailure(
                StateError(
                  'Unable to load EPUB renderer: ${webError.description}',
                ),
              );
            }
          },
          onConsoleMessage: (_, message) => AppDiagnostics.info(
            'epub.console',
            'JavaScript console message',
            details: {
              'level': message.messageLevel.toString(),
              'message': message.message,
            },
          ),
        ),
        if (loadPhase.value == _AndroidEpubLoadPhase.loading)
          const _AndroidEpubLoading(),
        if (loadPhase.value == _AndroidEpubLoadPhase.failed)
          _AndroidEpubLoadFailure(
            message: '无法启动 EPUB 渲染器：${error.value}',
            onRetry: () => retryRevision.value += 1,
          ),
      ],
    );
  }

  void _handleRuntimeMessage(
    BuildContext context,
    String rawMessage,
    EpubManifest? manifest,
    VoidCallback onRuntimeReady,
    VoidCallback onReady,
    ValueChanged<Object> onFailure,
    ValueChanged<bool> onAutoScrollChanged,
  ) {
    Object? runtimeMessage;
    try {
      runtimeMessage = jsonDecode(rawMessage);
    } on FormatException {
      // Legacy scroll and tap messages use a compact pipe format.
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'runtimeBoot') {
      AppDiagnostics.info(
        'epub.bridge',
        'runtime script booted',
        details: {'runtimeVersion': runtimeMessage['runtimeVersion']},
      );
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'runtimeReady') {
      AppDiagnostics.info(
        'epub.bridge',
        'runtime bridge ready',
        details: {'runtimeVersion': runtimeMessage['runtimeVersion']},
      );
      onRuntimeReady();
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'runtimeWarning') {
      final runtimeStack = runtimeMessage['stack'];
      AppDiagnostics.info(
        'epub.bridge',
        'runtime reported a warning',
        details: {
          'context': runtimeMessage['context'],
          'message': runtimeMessage['message'],
        },
      );
      if (runtimeStack is String && runtimeStack.isNotEmpty) {
        AppDiagnostics.error(
          'epub.bridge',
          'runtime warning stack',
          stackTrace: StackTrace.fromString(runtimeStack),
        );
      }
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'epubInteraction') {
      if (manifest == null || !context.mounted) return;
      try {
        final interaction = EpubInteraction.fromBridgeMessage(
          runtimeMessage,
          manifest: manifest,
        );
        unawaited(presentEpubInteraction(context, interaction));
      } on FormatException {
        reportInvalidEpubInteraction(context);
      }
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'runtimeRelocate') {
      onReady();
      final messageHref = runtimeMessage['href'];
      final ratio = runtimeMessage['ratio'];
      final pageIndex = runtimeMessage['pageIndex'];
      final pageCount = runtimeMessage['pageCount'];
      if (messageHref is String && ratio is num) {
        onScrollPositionChanged(
          messageHref,
          EpubLocation.normalizedRelocationRatio(
            reportedRatio: ratio.toDouble(),
            paginated: runtimeMessage['flow'] != 'scrolled',
            pageIndex: pageIndex is num ? pageIndex.toInt() : null,
            pageCount: pageCount is num ? pageCount.toInt() : null,
          ),
          runtimeMessage['anchor'] as String?,
          runtimeMessage['cfi'] as String?,
        );
      }
      if (runtimeMessage['flow'] != 'scrolled' &&
          pageIndex is num &&
          pageCount is num) {
        onPaginationChanged(pageIndex.toInt(), pageCount.toInt());
      }
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'runtimeError') {
      final runtimeStack = runtimeMessage['stack'];
      AppDiagnostics.error(
        'epub.bridge',
        'runtime reported an error',
        error: StateError(runtimeMessage['message'] ?? 'Unknown runtime error'),
        stackTrace: runtimeStack is String && runtimeStack.isNotEmpty
            ? StackTrace.fromString(runtimeStack)
            : null,
      );
      onFailure(
        StateError(runtimeMessage['message'] ?? 'Unknown runtime error'),
      );
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'autoScrollChanged') {
      onAutoScrollChanged(runtimeMessage['active'] == true);
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'commandCompleted') {
      final commandId = runtimeMessage['id'];
      if (commandId == 0) onReady();
      if (commandId is num) onNavigationCommandFinished(commandId.toInt());
      return;
    }
    if (runtimeMessage is Map<String, dynamic> &&
        runtimeMessage['type'] == 'commandFailed') {
      final commandId = runtimeMessage['id'];
      final runtimeStack = runtimeMessage['stack'];
      AppDiagnostics.error(
        'epub.bridge',
        'runtime command failed',
        details: {'commandId': commandId},
        error: StateError(runtimeMessage['message'] ?? 'Unknown command error'),
        stackTrace: runtimeStack is String && runtimeStack.isNotEmpty
            ? StackTrace.fromString(runtimeStack)
            : null,
      );
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

  String _runtimeOpenScript(
    BuildContext context,
    ReadingSettings settings,
    String href,
    double ratio,
    String? anchor,
    String? cfi,
    EpubManifest manifest,
    String? fontFaceCss,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final payload = jsonEncode({
      'href': href,
      'ratio': ratio.clamp(0, 1),
      'anchor': anchor,
      'cfi': cfi,
      'session': {
        'manifest': manifest.toJson(),
        'resourceBase': AndroidEpubResourceHandler.resourceBaseForBook(bookId),
      },
      'settings': {
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
        'foreground':
            '#${scheme.onSurface.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        'background':
            '#${scheme.surface.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        'direction': direction == ReadingDirection.rtl ? 'rtl' : 'ltr',
        'pageTransition': settings.pageTransition.name,
        'tapNavigationEnabled': settings.tapToTurnPages,
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
      ReaderNavigationKind.scrollBy => 'scrollBy',
      ReaderNavigationKind.startAutoScroll => 'startAutoScroll',
      ReaderNavigationKind.stopAutoScroll => 'stopAutoScroll',
    };
    return '''(() => {
      const runtime = window.TomoReadEpubRuntime;
      if (runtime) void runtime.command(${jsonEncode({
      'id': command.id,
      'type': type,
      'payload': {
        'href': command.href,
        'ratio': command.ratio,
        'anchor': command.anchor,
        'cfi': command.cfi,
        'amount': command.amount,
        'unit': command.unit,
        'speed': command.speed,
      },
    })});
    })();''';
  }

  String _runtimeSettingsScript(
    BuildContext context,
    ReadingSettings settings,
    String? fontFaceCss,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return '''(() => {
      const runtime = window.TomoReadEpubRuntime;
      if (runtime) void runtime.command(${jsonEncode({
      'type': 'setSettings',
      'payload': {
        'settings': {'flow': settings.layoutMode == ReaderLayoutMode.paginated ? 'paginated' : 'scrolled', 'columnCount': settings.doubleColumn ? 2 : 1, 'maxInlineSize': 760, 'margin': settings.pageMargin, 'fontFamily': settings.font.fontFamily, 'fontFaceCss': fontFaceCss, 'fontSize': settings.fontSize, 'lineHeight': settings.lineHeight, 'foreground': _cssColor(scheme.onSurface), 'background': _cssColor(scheme.surface), 'direction': direction == ReadingDirection.rtl ? 'rtl' : 'ltr', 'pageTransition': settings.pageTransition.name, 'tapNavigationEnabled': settings.tapToTurnPages},
      },
    })});
    })();''';
  }

  String _runtimeTextColoringScript(
    BuildContext context,
    ResolvedTextColoring textColoring,
  ) => _runtimeCall(
    'runtime.setTextColoring(${jsonEncode(textColoring.toRuntimeJson(dark: Theme.of(context).brightness == Brightness.dark))})',
  );

  String _runtimeTtsHighlightScript({
    required String? href,
    required String? text,
    required int? start,
    required int? end,
  }) {
    final payload = text == null || href == null
        ? null
        : <String, Object?>{
            'href': href,
            'text': text,
            'start': start,
            'end': end,
          };
    return _runtimeCall(
      'runtime.setTtsHighlight(${jsonEncode(payload)})',
    );
  }

  String _runtimeCall(String invocation) => '''(() => {
    let attempts = 0;
    const run = () => {
      const runtime = window.TomoReadEpubRuntime;
      if (runtime) { void $invocation; }
      else if (attempts++ < 100) { window.setTimeout(run, 20); }
    };
    run();
  })();''';

  String _cssColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  static Future<void> _runJavaScript(
    InAppWebViewController controller,
    String script, {
    required ValueChanged<Object> onError,
  }) async {
    try {
      await controller.evaluateJavascript(source: script);
    } catch (error, stackTrace) {
      AppDiagnostics.error(
        'epub.webview',
        'host JavaScript execution failed',
        error: error,
        stackTrace: stackTrace,
      );
      onError(error);
    }
  }

}

class _AndroidEpubLoading extends StatelessWidget {
  const _AndroidEpubLoading();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在加载 EPUB…'),
        ],
      ),
    ),
  );
}

class _AndroidEpubLoadFailure extends StatelessWidget {
  const _AndroidEpubLoadFailure({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    ),
  );
}
