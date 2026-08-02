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
import '../../domain/models/epub_location.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_coloring.dart';
import 'reader_navigation_command.dart';

class AndroidEpubWebView extends HookConsumerWidget {
  const AndroidEpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
    required this.textColoring,
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
  final ResolvedTextColoring textColoring;
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
    final readerSession = ref.watch(epubReaderSessionProvider(bookId));
    final epubManifest = ref.watch(readerManifestProvider(bookId));
    final error = useState<Object?>(null);
    final runtimeSettingsScript = _runtimeSettingsScript(context, settings);
    final runtimeTextColoringScript = _runtimeTextColoringScript(
      context,
      textColoring,
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
          );
    final runtimeScriptRef = useRef<String?>(runtimeScript);
    runtimeScriptRef.value = runtimeScript;
    final textColoringScriptRef = useRef(runtimeTextColoringScript);
    textColoringScriptRef.value = runtimeTextColoringScript;
    final runtimeLoaded = useRef(false);
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
                unawaited(
                  webViewController.runJavaScript(textColoringScriptRef.value),
                );
              }
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

    useEffect(() {
      runtimeLoaded.value = false;
      return null;
    }, [bookId]);

    useEffect(
      () {
        if (runtimeScript == null || runtimeLoaded.value) return null;
        final directory = readerSession.value?.directoryPath;
        if (directory == null) return null;
        final file = File(
          path.join(directory, '.tomoread-reader', 'index.html'),
        );
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

        runtimeLoaded.value = true;
        unawaited(loadChapter());
        return null;
      },
      [
        controller,
        readerSession.value?.directoryPath,
        epubManifest.value,
        bookId,
      ],
    );

    useEffect(() {
      unawaited(controller.runJavaScript(runtimeSettingsScript));
      return null;
    }, [controller, runtimeSettingsScript]);

    useEffect(() {
      unawaited(controller.runJavaScript(runtimeTextColoringScript));
      return null;
    }, [controller, runtimeTextColoringScript]);

    useEffect(() {
      final command = navigationCommand;
      if (command == null) return null;
      unawaited(controller.runJavaScript(_runtimeCommandScript(command)));
      return null;
    }, [controller, navigationCommand]);

    if (readerSession.hasError ||
        epubManifest.hasError ||
        error.value != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to start EPUB renderer: ${error.value ?? readerSession.error ?? epubManifest.error}',
          ),
        ),
      );
    }
    if (readerSession.isLoading || epubManifest.isLoading) {
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
        'flow': settings.layoutMode == ReaderLayoutMode.paginated
            ? 'paginated'
            : 'scrolled',
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
        'settings': {'flow': settings.layoutMode == ReaderLayoutMode.paginated ? 'paginated' : 'scrolled', 'columnCount': settings.doubleColumn ? 2 : 1, 'maxInlineSize': 760, 'margin': settings.pageMargin, 'fontFamily': settings.font.fontFamily, 'fontSize': settings.fontSize, 'lineHeight': settings.lineHeight, 'foreground': _cssColor(scheme.onSurface), 'background': _cssColor(scheme.surface), 'direction': direction == ReadingDirection.rtl ? 'rtl' : 'ltr', 'pageTransition': settings.pageTransition.name, 'tapNavigationEnabled': settings.tapToTurnPages},
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
}
