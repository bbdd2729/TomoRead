import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../app/providers.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reading_settings.dart';

class EpubWebView extends HookConsumerWidget {
  const EpubWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.settings,
    required this.onNavigateToHref,
  });

  static const _hostName = 'reader.tomoread';

  final String bookId;
  final String href;
  final ReadingSettings settings;
  final ValueChanged<String> onNavigateToHref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extractedDirectory = ref.watch(
      epubExtractedDirectoryProvider(bookId),
    );
    final controller = useMemoized(WebviewController.new);
    final initialized = useState(false);
    final initializationError = useState<Object?>(null);
    final styleScript = _styleScript(context, settings);
    final resourceDirectory = extractedDirectory.value;

    Future<void> applyStyle() async {
      try {
        await controller.executeScript(styleScript);
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
        if (state == LoadingState.navigationCompleted) unawaited(applyStyle());
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
      if (initialized.value) unawaited(applyStyle());
      return null;
    }, [initialized.value, styleScript]);

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
''';
    return '''(() => {
      let style = document.getElementById('tomoread-reader-style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'tomoread-reader-style';
        document.head.appendChild(style);
      }
      style.textContent = ${jsonEncode(css)};
    })();''';
  }

  String _cssColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
}
